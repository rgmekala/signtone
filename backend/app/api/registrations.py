"""
Signtone - Registrations API
==============================
Handles the final step of the Signtone flow:
user confirms on the phone → their profile is sent to the event organizer.

Routes:
    POST  /registrations/              register user to an event
    GET   /registrations/              list registrations (organizer view)
    GET   /registrations/user/me       get current user's registration history
    GET   /registrations/{reg_id}      get a single registration
    POST  /registrations/sweepstake    enter a sweepstake draw
"""

import logging
from datetime import datetime, timezone
from typing import Optional
from bson import ObjectId
from fastapi import APIRouter, HTTPException, Header, Query
from pydantic import BaseModel

from app.database import col_registrations, col_events, col_users, col_sweepstakes
from app.models.user import build_profile_snapshot
from app.models.event import EventType
from app.api.auth import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter()


# ── Request / Response schemas ────────────────────────────────────────────────

class RegistrationRequest(BaseModel):
    event_id:         str
    beacon_payload:   str
    profile_override: Optional[str] = None  # "public" or "professional"


class RegistrationResponse(BaseModel):
    id:               str
    user_id:          str
    event_id:         str
    event_name:       str
    event_type:       str
    profile_type:     str
    profile_snapshot: dict
    registered_at:    datetime
    message:          str = ""


class SweepstakeEntryRequest(BaseModel):
    event_id:       str
    beacon_payload: str


# ── Register to event ─────────────────────────────────────────────────────────

@router.post("/", response_model=RegistrationResponse, status_code=201)
async def register_to_event(
    payload:       RegistrationRequest,
    authorization: str = Header(...),
):
    """
    Core Signtone action - user confirms on phone after beacon detected.
    Automatically selects the correct profile based on event type:
      - PROFESSIONAL event → sends LinkedIn profile
      - PUBLIC event       → sends public profile
    User can override with profile_override field.
    """
    user    = await get_current_user(authorization)
    user_id = str(user["_id"])

    try:
        event = await col_events().find_one({"_id": ObjectId(payload.event_id)})
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid event ID")

    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    if event.get("status") != "active":
        raise HTTPException(status_code=400, detail="Event is not active")

    max_reg = event.get("max_registrations")
    if max_reg:
        count = await col_registrations().count_documents(
            {"event_id": payload.event_id}
        )
        if count >= max_reg:
            raise HTTPException(
                status_code=409,
                detail="Event has reached maximum registrations"
            )

    existing = await col_registrations().find_one({
        "user_id":  user_id,
        "event_id": payload.event_id,
    })
    if existing:
        raise HTTPException(
            status_code=409,
            detail="You are already registered for this event"
        )

    event_type = event.get("event_type", EventType.PUBLIC)

    if payload.profile_override in ("public", "professional"):
        effective_type = payload.profile_override
    else:
        effective_type = event_type

    if effective_type == "professional":
        prof = user.get("professional_profile")
        if not prof or not prof.get("linkedin_id"):
            raise HTTPException(
                status_code=400,
                detail="LinkedIn profile required for professional events - "
                       "please connect LinkedIn in app settings"
            )

    snapshot = build_profile_snapshot(user, effective_type)

    now = datetime.now(timezone.utc)
    doc = {
        "user_id":          user_id,
        "event_id":         payload.event_id,
        "beacon_payload":   payload.beacon_payload,
        "event_type":       event_type,
        "profile_type":     effective_type,
        "profile_snapshot": snapshot.model_dump(),
        "registered_at":    now,
        "created_at":       now,
    }

    result = await col_registrations().insert_one(doc)

    await col_events().update_one(
        {"_id": ObjectId(payload.event_id)},
        {"$inc": {"registration_count": 1}}
    )

    logger.info(
        f"Registration: user={user_id} event={payload.event_id} "
        f"type={effective_type} profile={snapshot.profile_type}"
    )

    return RegistrationResponse(
        id               = str(result.inserted_id),
        user_id          = user_id,
        event_id         = payload.event_id,
        event_name       = event["name"],
        event_type       = event_type,
        profile_type     = effective_type,
        profile_snapshot = snapshot.model_dump(),
        registered_at    = now,
        message          = f"Successfully registered for {event['name']}",
    )


# ── List registrations (organizer view) ──────────────────────────────────────

@router.get("/", response_model=list[RegistrationResponse])
async def list_registrations(
    event_id: Optional[str] = Query(None),
    limit:    int = Query(100, le=500),
    skip:     int = Query(0),
):
    """List registrations - used by organizer dashboard."""
    query = {}
    if event_id:
        query["event_id"] = event_id

    cursor = col_registrations().find(query).skip(skip).limit(limit)
    docs   = await cursor.to_list(length=limit)

    results = []
    for doc in docs:
        event = await col_events().find_one({"_id": ObjectId(doc["event_id"])})
        results.append(RegistrationResponse(
            id               = str(doc["_id"]),
            user_id          = doc["user_id"],
            event_id         = doc["event_id"],
            event_name       = event["name"] if event else "Unknown",
            event_type       = doc.get("event_type", "public"),
            profile_type     = doc.get("profile_type", "public"),
            profile_snapshot = doc.get("profile_snapshot", {}),
            registered_at    = doc["registered_at"],
        ))
    return results


# ── User's registration history ───────────────────────────────────────────────
# IMPORTANT: this route must be defined BEFORE /{reg_id} to avoid FastAPI
# matching "me" as a reg_id parameter.

@router.get("/user/me", response_model=list[RegistrationResponse])
async def my_registrations(
    authorization: str = Header(...),
    limit:         int = Query(50, le=200),
    skip:          int = Query(0),
):
    """Return the current user's full registration history."""
    user    = await get_current_user(authorization)
    user_id = str(user["_id"])

    cursor = col_registrations().find(
        {"user_id": user_id}
    ).sort("registered_at", -1).skip(skip).limit(limit)

    docs    = await cursor.to_list(length=limit)
    results = []

    for doc in docs:
        event = await col_events().find_one({"_id": ObjectId(doc["event_id"])})
        results.append(RegistrationResponse(
            id               = str(doc["_id"]),
            user_id          = user_id,
            event_id         = doc["event_id"],
            event_name       = event["name"] if event else "Unknown",
            event_type       = doc.get("event_type", "public"),
            profile_type     = doc.get("profile_type", "public"),
            profile_snapshot = doc.get("profile_snapshot", {}),
            registered_at    = doc["registered_at"],
        ))
    return results


# ── Get single registration ───────────────────────────────────────────────────
# IMPORTANT: this route must be defined AFTER /user/me

@router.get("/{reg_id}", response_model=RegistrationResponse)
async def get_registration(reg_id: str):
    """Get a single registration by ID."""
    doc = await col_registrations().find_one({"_id": ObjectId(reg_id)})
    if not doc:
        raise HTTPException(status_code=404, detail="Registration not found")

    event = await col_events().find_one({"_id": ObjectId(doc["event_id"])})
    return RegistrationResponse(
        id               = str(doc["_id"]),
        user_id          = doc["user_id"],
        event_id         = doc["event_id"],
        event_name       = event["name"] if event else "Unknown",
        event_type       = doc.get("event_type", "public"),
        profile_type     = doc.get("profile_type", "public"),
        profile_snapshot = doc.get("profile_snapshot", {}),
        registered_at    = doc["registered_at"],
    )


# ── Sweepstake entry ──────────────────────────────────────────────────────────

@router.post("/sweepstake", status_code=201)
async def enter_sweepstake(
    payload:       SweepstakeEntryRequest,
    authorization: str = Header(...),
):
    """
    Enter a sweepstake draw.
    Uses public profile - no LinkedIn required.
    One entry per user per sweepstake.
    """
    user    = await get_current_user(authorization)
    user_id = str(user["_id"])

    event = await col_events().find_one({"_id": ObjectId(payload.event_id)})
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    if event.get("event_type") != EventType.PUBLIC:
        raise HTTPException(
            status_code=400,
            detail="Sweepstake entry only available for public events"
        )

    existing = await col_sweepstakes().find_one({
        "user_id":  user_id,
        "event_id": payload.event_id,
    })
    if existing:
        raise HTTPException(
            status_code=409,
            detail="You have already entered this sweepstake"
        )

    pub = user.get("public_profile")
    if not pub or not pub.get("email"):
        raise HTTPException(
            status_code=400,
            detail="Please complete your public profile before entering a sweepstake"
        )

    snapshot = build_profile_snapshot(user, "public")
    now      = datetime.now(timezone.utc)

    entry = {
        "user_id":          user_id,
        "event_id":         payload.event_id,
        "beacon_payload":   payload.beacon_payload,
        "profile_snapshot": snapshot.model_dump(),
        "entered_at":       now,
        "winner":           False,
    }

    result = await col_sweepstakes().insert_one(entry)

    await col_registrations().insert_one({
        "user_id":          user_id,
        "event_id":         payload.event_id,
        "beacon_payload":   payload.beacon_payload,
        "event_type":       "public",
        "profile_type":     "public",
        "profile_snapshot": snapshot.model_dump(),
        "registered_at":    now,
        "created_at":       now,
        "sweepstake_entry": str(result.inserted_id),
    })

    await col_events().update_one(
        {"_id": ObjectId(payload.event_id)},
        {"$inc": {"registration_count": 1}}
    )

    logger.info(f"Sweepstake entry: user={user_id} event={payload.event_id}")

    return {
        "entry_id":   str(result.inserted_id),
        "event_name": event["name"],
        "entered_at": now,
        "message":    f"You are entered in {event['name']}! Good luck!",
    }
