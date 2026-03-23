"""
Signtone - Event Models
========================
Pydantic schemas for events.
An event is what a beacon signal points to -
a conference session, a sweepstake, a radio promotion, etc.
"""

from datetime import datetime, timezone
from typing import Optional
from enum import Enum
from pydantic import BaseModel, Field


class EventType(str, Enum):
    PROFESSIONAL = "professional"  # conference, meeting, B2B → sends LinkedIn profile
    PUBLIC       = "public"        # sweepstake, contest, radio → sends public profile


class EventStatus(str, Enum):
    DRAFT    = "draft"
    ACTIVE   = "active"
    ENDED    = "ended"
    ARCHIVED = "archived"


# ── Base ──────────────────────────────────────────────────────────────────────

class EventBase(BaseModel):
    name:         str = Field(..., min_length=2, max_length=120)
    description:  Optional[str] = None
    event_type:   EventType
    organizer_id: str
    location:     Optional[str] = None
    starts_at:    Optional[datetime] = None
    ends_at:      Optional[datetime] = None
    status:       EventStatus = EventStatus.DRAFT

    # Registration settings
    max_registrations: Optional[int]  = None   # None = unlimited
    require_linkedin:  bool           = False   # force LinkedIn for public events


# ── Request schemas ───────────────────────────────────────────────────────────

class EventCreate(EventBase):
    """Sent by organizer when creating a new event."""
    pass


class EventUpdate(BaseModel):
    """Partial update - all fields optional."""
    name:              Optional[str]         = None
    description:       Optional[str]         = None
    status:            Optional[EventStatus] = None
    location:          Optional[str]         = None
    starts_at:         Optional[datetime]    = None
    ends_at:           Optional[datetime]    = None
    max_registrations: Optional[int]         = None
    require_linkedin:  Optional[bool]        = None


# ── Response schemas ──────────────────────────────────────────────────────────

class EventResponse(EventBase):
    """Returned to client after create or fetch."""
    id:                 str
    registration_count: int      = 0
    created_at:         datetime
    updated_at:         datetime

    class Config:
        from_attributes = True


class EventSummary(BaseModel):
    """
    Lightweight event info shown on the mobile confirmation card
    when a beacon is detected. Does not expose internal fields.
    """
    id:           str
    name:         str
    description:  Optional[str]  = None
    event_type:   EventType
    location:     Optional[str]  = None
    starts_at:    Optional[datetime] = None
    organizer_id: str


# ── Database document ─────────────────────────────────────────────────────────

class EventDocument(EventBase):
    """Full document as stored in MongoDB."""
    id:                 Optional[str] = Field(default=None, alias="_id")
    registration_count: int           = 0
    created_at:         datetime      = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at:         datetime      = Field(default_factory=lambda: datetime.now(timezone.utc))

    class Config:
        populate_by_name = True


# ── Helper ────────────────────────────────────────────────────────────────────

def event_from_doc(doc: dict) -> EventResponse:
    """Convert a raw MongoDB document to an EventResponse."""
    doc["id"] = str(doc.pop("_id"))
    return EventResponse(**doc)


def event_summary_from_doc(doc: dict) -> EventSummary:
    """Convert a raw MongoDB document to a lightweight EventSummary."""
    doc["id"] = str(doc.pop("_id"))
    return EventSummary(**doc)
