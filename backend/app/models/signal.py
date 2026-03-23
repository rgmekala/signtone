"""
Signtone - Signal Models
=========================
Pydantic schemas for audio signals (ultrasonic beacons).
A signal is the link between a beacon payload and an event.
"""

from datetime import datetime, timezone
from typing import Optional
from enum import Enum
from pydantic import BaseModel, Field
from bson import ObjectId


class SignalStatus(str, Enum):
    ACTIVE   = "active"
    INACTIVE = "inactive"
    EXPIRED  = "expired"


class SignalType(str, Enum):
    BEACON      = "beacon"       # ultrasonic BFSK beacon (primary)
    FINGERPRINT = "fingerprint"  # audio fingerprint match (future v2)


# ── Base ──────────────────────────────────────────────────────────────────────

class SignalBase(BaseModel):
    event_id:        str
    beacon_payload:  str = Field(
        ...,
        min_length=1,
        max_length=32,
        description="Short ASCII string encoded into the ultrasonic beacon"
    )
    signal_type:     SignalType = SignalType.BEACON
    status:          SignalStatus = SignalStatus.ACTIVE
    valid_from:      datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    expires_at:      Optional[datetime] = None
    description:     Optional[str] = None


# ── Request schemas (API input) ───────────────────────────────────────────────

class SignalCreate(SignalBase):
    """
    Sent by organizer when creating a new beacon signal.
    beacon_payload must be unique across all active signals.
    """
    pass


class SignalUpdate(BaseModel):
    """Partial update - all fields optional."""
    status:      Optional[SignalStatus] = None
    expires_at:  Optional[datetime]    = None
    description: Optional[str]         = None


# ── Response schemas (API output) ─────────────────────────────────────────────

class SignalResponse(SignalBase):
    """Returned to the client after create or fetch."""
    id:         str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class SignalMatchResult(BaseModel):
    """
    Returned by the matching endpoint when a beacon is detected.
    Contains everything the mobile app needs to show the confirmation card.
    """
    matched:         bool
    signal_id:       Optional[str]      = None
    event_id:        Optional[str]      = None
    beacon_payload:  Optional[str]      = None
    confidence:      float              = 0.0   # 0.0 - 1.0
    message:         str                = ""


# ── Database document (stored in MongoDB) ────────────────────────────────────

class SignalDocument(SignalBase):
    """
    Full document as stored in MongoDB.
    _id is stored as string (converted from ObjectId on read).
    """
    id:         Optional[str]      = Field(default=None, alias="_id")
    created_at: datetime           = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime           = Field(default_factory=lambda: datetime.now(timezone.utc))

    class Config:
        populate_by_name = True


# ── Helper ────────────────────────────────────────────────────────────────────

def signal_from_doc(doc: dict) -> SignalResponse:
    """Convert a raw MongoDB document to a SignalResponse."""
    doc["id"] = str(doc.pop("_id"))
    return SignalResponse(**doc)
