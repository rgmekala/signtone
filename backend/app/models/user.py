"""
Signtone - User Models
=======================
Pydantic schemas for users with dual profile support.

Profile A - Public profile    → used for sweepstakes, contests, radio
Profile B - Professional profile → used for conferences, meetings (LinkedIn)
"""

from datetime import datetime, timezone
from typing import Optional
from pydantic import BaseModel, Field, EmailStr


# ── Public Profile (Profile A) ────────────────────────────────────────────────

class PublicProfile(BaseModel):
    """
    General / public identity.
    Used when event_type = PUBLIC.
    Filled in manually by the user in app settings.
    """
    first_name:    str
    last_name:     str
    email:         EmailStr
    phone:         Optional[str]  = None
    date_of_birth: Optional[str]  = None   # "YYYY-MM-DD" - for age verification
    city:          Optional[str]  = None
    photo_url:     Optional[str]  = None


class PublicProfileUpdate(BaseModel):
    """Partial update for public profile."""
    first_name:    Optional[str]      = None
    last_name:     Optional[str]      = None
    email:         Optional[EmailStr] = None
    phone:         Optional[str]      = None
    date_of_birth: Optional[str]      = None
    city:          Optional[str]      = None
    photo_url:     Optional[str]      = None


# ── Professional Profile (Profile B) ─────────────────────────────────────────

class ProfessionalProfile(BaseModel):
    """
    LinkedIn-sourced professional identity.
    Used when event_type = PROFESSIONAL.
    Populated automatically via LinkedIn OAuth - not editable by user.
    """
    linkedin_id:      Optional[str]      = None
    full_name:        Optional[str]      = None
    headline:         Optional[str]      = None   # "Product Manager at Acme Corp"
    company:          Optional[str]      = None
    email:            Optional[EmailStr] = None
    profile_url:      Optional[str]      = None
    photo_url:        Optional[str]      = None
    access_token:     Optional[str]      = None   # encrypted - never returned to client
    token_expires_at: Optional[datetime] = None
    synced_at:        Optional[datetime] = None


# ── User ──────────────────────────────────────────────────────────────────────

class UserBase(BaseModel):
    email:    EmailStr
    is_active: bool = True


class UserCreate(UserBase):
    """Created on first app login."""
    public_profile: Optional[PublicProfile] = None


class UserResponse(UserBase):
    """Returned to client - never includes access tokens."""
    id:                   str
    public_profile:       Optional[PublicProfile]       = None
    professional_profile: Optional[ProfessionalProfile] = None
    has_linkedin:         bool                          = False
    created_at:           datetime
    updated_at:           datetime

    class Config:
        from_attributes = True


class UserDocument(UserBase):
    """Full document as stored in MongoDB - includes tokens."""
    id:                   Optional[str]                 = Field(default=None, alias="_id")
    public_profile:       Optional[PublicProfile]       = None
    professional_profile: Optional[ProfessionalProfile] = None
    created_at:           datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at:           datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    class Config:
        populate_by_name = True


# ── Registration Profile Snapshot ─────────────────────────────────────────────

class ProfileSnapshot(BaseModel):
    """
    Frozen copy of the profile sent at registration time.
    Stored inside the registration document so organizers
    always see what the profile looked like when the user registered -
    even if the user updates their profile later.
    """
    profile_type:  str              # "public" or "professional"
    full_name:     Optional[str]    = None
    email:         Optional[str]    = None
    phone:         Optional[str]    = None
    headline:      Optional[str]    = None
    company:       Optional[str]    = None
    profile_url:   Optional[str]    = None
    photo_url:     Optional[str]    = None
    city:          Optional[str]    = None


# ── Helper ────────────────────────────────────────────────────────────────────

def user_from_doc(doc: dict) -> UserResponse:
    """Convert a raw MongoDB document to a UserResponse."""
    doc = dict(doc)
    doc["id"] = str(doc.pop("_id"))
    # Remove sensitive fields before returning
    if doc.get("professional_profile"):
        doc["professional_profile"].pop("access_token", None)
        doc["professional_profile"].pop("token_expires_at", None)
    doc["has_linkedin"] = bool(
        doc.get("professional_profile") and
        doc["professional_profile"].get("linkedin_id")
    )
    return UserResponse(**doc)


def build_profile_snapshot(user_doc: dict, event_type: str) -> ProfileSnapshot:
    """
    Build a ProfileSnapshot from a user document.
    Selects public or professional profile based on event type.
    """
    if event_type == "professional" and user_doc.get("professional_profile"):
        prof = user_doc["professional_profile"]
        return ProfileSnapshot(
            profile_type = "professional",
            full_name    = prof.get("full_name"),
            email        = prof.get("email"),
            headline     = prof.get("headline"),
            company      = prof.get("company"),
            profile_url  = prof.get("profile_url"),
            photo_url    = prof.get("photo_url"),
        )
    else:
        pub = user_doc.get("public_profile") or {}
        return ProfileSnapshot(
            profile_type = "public",
            full_name    = f"{pub.get('first_name','')} {pub.get('last_name','')}".strip(),
            email        = pub.get("email"),
            phone        = pub.get("phone"),
            photo_url    = pub.get("photo_url"),
            city         = pub.get("city"),
        )
