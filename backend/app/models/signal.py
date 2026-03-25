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
    BEACON      = "beacon"
    FINGERPRINT = "fingerprint"


# ── Base ──────────────────────────────────────────────────────────────────────

class SignalBase(BaseModel):
    event_id:           str
    beacon_payload:     str = Field(
        ..., min_length=1, max_length=32,
        description="Short ASCII string encoded into the beacon"
    )
    signal_type:        SignalType   = SignalType.BEACON
    status:             SignalStatus = SignalStatus.ACTIVE
    valid_from:         datetime     = Field(default_factory=lambda: datetime.now(timezone.utc))
    expires_at:         Optional[datetime] = None
    description:        Optional[str]      = None

    # ── New fields ─────────────────────────────────────────────────────────
    frequency_profile:  Optional[str] = Field(
        default="ultrasonic",
        description="'ultrasonic' (15-17 kHz, ~30m) or 'audible' (4-6 kHz, ~300m)"
    )
    chime_style:        Optional[str] = Field(
        default="none",
        description="Branded chime: 'none' | 'marimba' | 'bell' | 'modern'"
    )


# ── Request schemas ───────────────────────────────────────────────────────────

class SignalCreate(SignalBase):
    """Sent by organizer when creating a new beacon signal."""
    pass


class SignalUpdate(BaseModel):
    """Partial update - all fields optional."""
    status:             Optional[SignalStatus] = None
    expires_at:         Optional[datetime]     = None
    description:        Optional[str]          = None
    frequency_profile:  Optional[str]          = None
    chime_style:        Optional[str]          = None


# ── Response schemas ──────────────────────────────────────────────────────────

class SignalResponse(SignalBase):
    """Returned to the client after create or fetch."""
    id:         str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class SignalMatchResult(BaseModel):
    """
    Returned by /signals/match.
    Contains everything the mobile app needs for the confirmation card.
    """
    matched:           bool
    signal_id:         Optional[str] = None
    event_id:          Optional[str] = None
    beacon_payload:    Optional[str] = None
    confidence:        float         = 0.0
    message:           str           = ""
    event_name:        Optional[str] = None
    event_description: Optional[str] = None
    event_type:        Optional[str] = None
    organizer_name:    Optional[str] = None


# ── Database document ─────────────────────────────────────────────────────────

class SignalDocument(SignalBase):
    id:         Optional[str] = Field(default=None, alias="_id")
    created_at: datetime      = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime      = Field(default_factory=lambda: datetime.now(timezone.utc))

    class Config:
        populate_by_name = True


# ── Helper ────────────────────────────────────────────────────────────────────

def signal_from_doc(doc: dict) -> SignalResponse:
    """Convert a raw MongoDB document to a SignalResponse."""
    doc["id"] = str(doc.pop("_id"))
    # Fill defaults for older docs that predate these fields
    doc.setdefault("frequency_profile", "ultrasonic")
    doc.setdefault("chime_style", "none")
    return SignalResponse(**doc)
