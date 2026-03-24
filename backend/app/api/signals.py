"""
Signtone - Signals API
=======================
Endpoints for managing beacon signals and matching detected audio.

Routes:
    POST   /signals/                  create a new beacon signal
    GET    /signals/                  list all signals
    GET    /signals/{signal_id}       get a single signal
    PATCH  /signals/{signal_id}       update a signal
    DELETE /signals/{signal_id}       delete a signal
    POST   /signals/match             match detected audio → find event
    GET    /signals/{signal_id}/wav   download beacon .wav file
"""

import io
import logging
from datetime import datetime, timezone
from typing import Optional
from bson import ObjectId
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import StreamingResponse

from app.database import col_signals, col_events
from app.models.signal import (
    SignalCreate, SignalUpdate, SignalResponse,
    SignalMatchResult, SignalStatus, signal_from_doc
)
from app.models.event import EventSummary
from app.services.beacon_service import (
    encode_payload, decode_signal, save_beacon_wav, SAMPLE_RATE
)
from scipy.io import wavfile
import numpy as np

logger = logging.getLogger(__name__)
router = APIRouter()


# ── Create signal ─────────────────────────────────────────────────────────────

@router.post("/", response_model=SignalResponse, status_code=201)
async def create_signal(payload: SignalCreate):
    """
    Create a new beacon signal linked to an event.
    The beacon_payload must be unique across all active signals.
    """
    # Verify event exists
    event = await col_events().find_one({"_id": ObjectId(payload.event_id)})
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    # Check beacon_payload is unique
    existing = await col_signals().find_one(
        {"beacon_payload": payload.beacon_payload, "status": SignalStatus.ACTIVE}
    )
    if existing:
        raise HTTPException(
            status_code=409,
            detail=f"Beacon payload '{payload.beacon_payload}' is already in use"
        )

    # Validate payload can be encoded
    try:
        encode_payload(payload.beacon_payload)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    now = datetime.now(timezone.utc)
    doc = {
        **payload.model_dump(),
        "created_at": now,
        "updated_at": now,
    }

    result = await col_signals().insert_one(doc)
    doc["_id"] = result.inserted_id
    logger.info(f"Signal created: {payload.beacon_payload} → event {payload.event_id}")
    return signal_from_doc(doc)


# ── List signals ──────────────────────────────────────────────────────────────

@router.get("/", response_model=list[SignalResponse])
async def list_signals(
    event_id: Optional[str] = Query(None),
    status:   Optional[SignalStatus] = Query(None),
    limit:    int = Query(50, le=200),
    skip:     int = Query(0),
):
    """List signals with optional filters."""
    query = {}
    if event_id:
        query["event_id"] = event_id
    if status:
        query["status"] = status

    cursor = col_signals().find(query).skip(skip).limit(limit)
    docs   = await cursor.to_list(length=limit)
    return [signal_from_doc(d) for d in docs]


# ── Get signal ────────────────────────────────────────────────────────────────

@router.get("/{signal_id}", response_model=SignalResponse)
async def get_signal(signal_id: str):
    """Get a single signal by ID."""
    doc = await col_signals().find_one({"_id": ObjectId(signal_id)})
    if not doc:
        raise HTTPException(status_code=404, detail="Signal not found")
    return signal_from_doc(doc)


# ── Update signal ─────────────────────────────────────────────────────────────

@router.patch("/{signal_id}", response_model=SignalResponse)
async def update_signal(signal_id: str, updates: SignalUpdate):
    """Update signal status or expiry."""
    update_data = {
        k: v for k, v in updates.model_dump().items() if v is not None
    }
    update_data["updated_at"] = datetime.now(timezone.utc)

    result = await col_signals().find_one_and_update(
        {"_id": ObjectId(signal_id)},
        {"$set": update_data},
        return_document=True,
    )
    if not result:
        raise HTTPException(status_code=404, detail="Signal not found")
    return signal_from_doc(result)


# ── Delete signal ─────────────────────────────────────────────────────────────

@router.delete("/{signal_id}", status_code=204)
async def delete_signal(signal_id: str):
    """Delete a signal permanently."""
    result = await col_signals().delete_one({"_id": ObjectId(signal_id)})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Signal not found")


# ── Match detected audio ──────────────────────────────────────────────────────
@router.post("/match", response_model=SignalMatchResult)
async def match_signal(audio_data: dict):
    """
    Called by the mobile app when it detects audio.
    Accepts EITHER:
      A) Pre-decoded payload: { "beacon_payload": "TEST_EVENT_001" }
      B) Raw PCM samples:     { "samples": [0.1, -0.2, ...], "sample_rate": 44100 }
    """
    # ── Path A: Flutter Goertzel already decoded the payload ──────────────────
    beacon_payload = audio_data.get("beacon_payload")
    if beacon_payload:
        payload = beacon_payload
    # ── Path B: Raw PCM - decode server-side ──────────────────────────────────
    else:
        samples = audio_data.get("samples")
        sr      = audio_data.get("sample_rate", SAMPLE_RATE)
        if not samples:
            raise HTTPException(status_code=400, detail="No audio samples provided")
        signal  = np.array(samples, dtype=np.float32)
        max_val = np.max(np.abs(signal))
        if max_val > 0:
           signal = signal / max_val

        payload = decode_signal(signal, sr)
        if not payload:
            return SignalMatchResult(
                matched   = False,
                confidence= 0.0,
                message   = "No beacon detected in audio"
            )

    # ── Look up signal in DB ───────────────────────────────────────────────────
    sig_doc = await col_signals().find_one({
        "beacon_payload": payload,
        "status": SignalStatus.ACTIVE,
    })
    if not sig_doc:
        return SignalMatchResult(
            matched        = False,
            beacon_payload = payload,
            confidence     = 1.0,
            message        = "Beacon decoded but no active signal found for this payload"
        )
    # Check expiry
    if sig_doc.get("expires_at") and sig_doc["expires_at"] < datetime.now(timezone.utc):
        return SignalMatchResult(
            matched  = False,
            message  = "This beacon has expired"
        )

    logger.info(f"Signal matched: '{payload}' → event {sig_doc['event_id']}")

    # Fetch event details to enrich the confirmation card
    event_doc = await col_events().find_one({"_id": ObjectId(sig_doc["event_id"])})

    return SignalMatchResult(
        matched           = True,
        signal_id         = str(sig_doc["_id"]),
        event_id          = sig_doc["event_id"],
        beacon_payload    = payload,
        confidence        = 1.0,
        message           = "Beacon matched successfully",
        event_name        = event_doc.get("name", "")          if event_doc else "",
        event_description = event_doc.get("description", "")   if event_doc else "",
        event_type        = event_doc.get("event_type", "")    if event_doc else "",
        organizer_name    = event_doc.get("organizer_name", "") if event_doc else "",
    )

# ── Download beacon .wav ──────────────────────────────────────────────────────

@router.get("/{signal_id}/wav")
async def download_beacon_wav(signal_id: str):
    """
    Generate and download the beacon .wav file for a signal.
    Organizer plays this file through their PA or radio system.
    """
    doc = await col_signals().find_one({"_id": ObjectId(signal_id)})
    if not doc:
        raise HTTPException(status_code=404, detail="Signal not found")

    payload = doc["beacon_payload"]

    # Encode to audio signal
    signal  = encode_payload(payload)
    pcm     = (signal * 32767).astype(np.int16)

    # Write to in-memory buffer
    buf = io.BytesIO()
    wavfile.write(buf, SAMPLE_RATE, pcm)
    buf.seek(0)

    filename = f"signtone_beacon_{payload}.wav"
    return StreamingResponse(
        buf,
        media_type   = "audio/wav",
        headers      = {"Content-Disposition": f"attachment; filename={filename}"}
    )
