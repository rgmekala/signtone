"""
Signtone - Events API
======================
Routes:
    POST   /events/             create a new event
    GET    /events/             list events
    GET    /events/{event_id}   get a single event
    PATCH  /events/{event_id}   update an event
    DELETE /events/{event_id}   delete an event
"""

import logging
from datetime import datetime, timezone
from typing import Optional
from bson import ObjectId
from fastapi import APIRouter, HTTPException, Query

from app.database import col_events, col_signals, col_registrations
from app.models.event import (
    EventCreate, EventUpdate, EventResponse,
    EventStatus, event_from_doc
)

logger = logging.getLogger(__name__)
router = APIRouter()


# ── Create event ──────────────────────────────────────────────────────────────

@router.post("/", response_model=EventResponse, status_code=201)
async def create_event(payload: EventCreate):
    """Create a new event."""
    now = datetime.now(timezone.utc)
    doc = {
        **payload.model_dump(),
        "registration_count": 0,
        "created_at": now,
        "updated_at": now,
    }
    result = await col_events().insert_one(doc)
    doc["_id"] = result.inserted_id
    logger.info(f"Event created: '{payload.name}' [{payload.event_type}]")
    return event_from_doc(doc)


# ── List events ───────────────────────────────────────────────────────────────

@router.get("/", response_model=list[EventResponse])
async def list_events(
    organizer_id: Optional[str]         = Query(None),
    event_type:   Optional[str]         = Query(None),
    status:       Optional[EventStatus] = Query(None),
    limit:        int = Query(50, le=200),
    skip:         int = Query(0),
):
    """List events with optional filters."""
    query = {}
    if organizer_id:
        query["organizer_id"] = organizer_id
    if event_type:
        query["event_type"] = event_type
    if status:
        query["status"] = status

    cursor = col_events().find(query).skip(skip).limit(limit)
    docs   = await cursor.to_list(length=limit)
    return [event_from_doc(d) for d in docs]


# ── Get event ─────────────────────────────────────────────────────────────────

@router.get("/{event_id}", response_model=EventResponse)
async def get_event(event_id: str):
    """Get a single event by ID."""
    try:
        oid = ObjectId(event_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid event ID")

    doc = await col_events().find_one({"_id": oid})
    if not doc:
        raise HTTPException(status_code=404, detail="Event not found")
    return event_from_doc(doc)


# ── Update event ──────────────────────────────────────────────────────────────

@router.patch("/{event_id}", response_model=EventResponse)
async def update_event(event_id: str, updates: EventUpdate):
    """Partially update an event."""
    update_data = {
        k: v for k, v in updates.model_dump().items() if v is not None
    }
    if not update_data:
        raise HTTPException(status_code=400, detail="No update fields provided")

    update_data["updated_at"] = datetime.now(timezone.utc)

    result = await col_events().find_one_and_update(
        {"_id": ObjectId(event_id)},
        {"$set": update_data},
        return_document=True,
    )
    if not result:
        raise HTTPException(status_code=404, detail="Event not found")

    logger.info(f"Event updated: {event_id}")
    return event_from_doc(result)


# ── Delete event ──────────────────────────────────────────────────────────────

@router.delete("/{event_id}", status_code=204)
async def delete_event(event_id: str):
    """
    Delete an event and all its linked signals.
    Does not delete registrations - kept for history.
    """
    oid = ObjectId(event_id)

    # Delete linked signals first
    sig_result = await col_signals().delete_many({"event_id": event_id})
    logger.info(f"Deleted {sig_result.deleted_count} signals for event {event_id}")

    result = await col_events().delete_one({"_id": oid})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Event not found")

    logger.info(f"Event deleted: {event_id}")


# ── Get event registrations ───────────────────────────────────────────────────

@router.get("/{event_id}/registrations")
async def get_event_registrations(
    event_id: str,
    limit:    int = Query(100, le=500),
    skip:     int = Query(0),
):
    """
    Get all registrations for an event.
    Used by organizer dashboard to view attendee profiles.
    """
    # Verify event exists
    doc = await col_events().find_one({"_id": ObjectId(event_id)})
    if not doc:
        raise HTTPException(status_code=404, detail="Event not found")

    cursor = col_registrations().find(
        {"event_id": event_id}
    ).skip(skip).limit(limit)

    regs = await cursor.to_list(length=limit)

    # Convert ObjectIds to strings
    for r in regs:
        r["id"] = str(r.pop("_id"))

    return {
        "event_id":   event_id,
        "event_name": doc["name"],
        "total":      len(regs),
        "registrations": regs,
    }
