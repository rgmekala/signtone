"""
Signtone - Profiles API
========================
Manages both public and professional profiles for a user.

Routes:
    GET   /profiles/me                    get both profiles
    PUT   /profiles/me/public             create or replace public profile
    PATCH /profiles/me/public             partially update public profile
    GET   /profiles/me/public             get public profile only
    GET   /profiles/me/professional       get professional (LinkedIn) profile
    DELETE /profiles/me/linkedin          disconnect LinkedIn
    GET   /profiles/me/snapshot/{type}    preview what will be sent at registration
"""

import logging
from datetime import datetime, timezone
from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel

from app.database import col_users
from app.models.user import (
    PublicProfile, PublicProfileUpdate,
    ProfessionalProfile, ProfileSnapshot,
    build_profile_snapshot, user_from_doc
)
from app.api.auth import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter()


# ── Response schemas ──────────────────────────────────────────────────────────

class ProfilesResponse(BaseModel):
    """Both profiles in one response - shown on app settings screen."""
    user_id:              str
    email:                str
    has_public_profile:   bool
    has_linkedin:         bool
    public_profile:       PublicProfile       | None = None
    professional_profile: ProfessionalProfile | None = None


# ── Get both profiles ─────────────────────────────────────────────────────────

@router.get("/me", response_model=ProfilesResponse)
async def get_my_profiles(authorization: str = Header(...)):
    """
    Return both public and professional profiles.
    Used on the app settings / profile screen.
    """
    user = await get_current_user(authorization)

    pub  = user.get("public_profile")
    prof = user.get("professional_profile")

    # Strip access token before returning
    if prof:
        prof = dict(prof)
        prof.pop("access_token", None)
        prof.pop("token_expires_at", None)

    return ProfilesResponse(
        user_id              = str(user["_id"]),
        email                = user["email"],
        has_public_profile   = bool(pub and pub.get("email")),
        has_linkedin         = bool(prof and prof.get("linkedin_id")),
        public_profile       = PublicProfile(**pub) if pub else None,
        professional_profile = ProfessionalProfile(**prof) if prof else None,
    )


# ── Get public profile only ───────────────────────────────────────────────────

@router.get("/me/public", response_model=PublicProfile)
async def get_public_profile(authorization: str = Header(...)):
    """Get the user's public profile."""
    user = await get_current_user(authorization)
    pub  = user.get("public_profile")
    if not pub:
        raise HTTPException(
            status_code=404,
            detail="Public profile not set - use PUT /profiles/me/public to create one"
        )
    return PublicProfile(**pub)


# ── Create / replace public profile ──────────────────────────────────────────

@router.put("/me/public", response_model=PublicProfile)
async def set_public_profile(
    profile:       PublicProfile,
    authorization: str = Header(...),
):
    """
    Create or fully replace the public profile.
    Used when user fills in their details for sweepstakes.
    """
    user    = await get_current_user(authorization)
    user_id = user["_id"]

    await col_users().update_one(
        {"_id": user_id},
        {"$set": {
            "public_profile": profile.model_dump(),
            "updated_at":     datetime.now(timezone.utc),
        }}
    )
    logger.info(f"Public profile set for user {user_id}")
    return profile


# ── Partially update public profile ──────────────────────────────────────────

@router.patch("/me/public", response_model=PublicProfile)
async def update_public_profile(
    updates:       PublicProfileUpdate,
    authorization: str = Header(...),
):
    """
    Partially update the public profile.
    Only provided fields are updated - others stay the same.
    """
    user    = await get_current_user(authorization)
    user_id = user["_id"]

    # Get existing profile
    existing = user.get("public_profile") or {}

    # Merge updates into existing
    update_data = {
        k: v for k, v in updates.model_dump().items()
        if v is not None
    }
    if not update_data:
        raise HTTPException(status_code=400, detail="No update fields provided")

    merged = {**existing, **update_data}

    # Validate merged result is a valid PublicProfile
    try:
        updated = PublicProfile(**merged)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

    await col_users().update_one(
        {"_id": user_id},
        {"$set": {
            "public_profile": updated.model_dump(),
            "updated_at":     datetime.now(timezone.utc),
        }}
    )
    logger.info(f"Public profile updated for user {user_id}")
    return updated


# ── Get professional profile ──────────────────────────────────────────────────

@router.get("/me/professional", response_model=ProfessionalProfile)
async def get_professional_profile(authorization: str = Header(...)):
    """
    Get the LinkedIn professional profile.
    access_token is stripped from the response.
    """
    user = await get_current_user(authorization)
    prof = user.get("professional_profile")

    if not prof or not prof.get("linkedin_id"):
        raise HTTPException(
            status_code=404,
            detail="LinkedIn not connected - use /auth/linkedin to connect"
        )

    prof = dict(prof)
    prof.pop("access_token", None)
    prof.pop("token_expires_at", None)
    return ProfessionalProfile(**prof)


# ── Disconnect LinkedIn ───────────────────────────────────────────────────────

@router.delete("/me/linkedin", status_code=204)
async def disconnect_linkedin(authorization: str = Header(...)):
    """
    Remove the LinkedIn professional profile.
    User will need to re-authenticate via /auth/linkedin to reconnect.
    """
    user    = await get_current_user(authorization)
    user_id = user["_id"]

    await col_users().update_one(
        {"_id": user_id},
        {"$set": {
            "professional_profile": None,
            "updated_at":           datetime.now(timezone.utc),
        }}
    )
    logger.info(f"LinkedIn disconnected for user {user_id}")


# ── Preview profile snapshot ──────────────────────────────────────────────────

@router.get("/me/snapshot/{profile_type}", response_model=ProfileSnapshot)
async def preview_snapshot(
    profile_type:  str,
    authorization: str = Header(...),
):
    """
    Preview exactly what profile data will be sent at registration.
    profile_type must be 'public' or 'professional'.

    Used on the mobile confirmation card so the user sees
    exactly what they are about to share before tapping confirm.
    """
    if profile_type not in ("public", "professional"):
        raise HTTPException(
            status_code=400,
            detail="profile_type must be 'public' or 'professional'"
        )

    user = await get_current_user(authorization)

    if profile_type == "professional":
        prof = user.get("professional_profile")
        if not prof or not prof.get("linkedin_id"):
            raise HTTPException(
                status_code=404,
                detail="LinkedIn not connected"
            )

    if profile_type == "public":
        pub = user.get("public_profile")
        if not pub or not pub.get("email"):
            raise HTTPException(
                status_code=404,
                detail="Public profile not set"
            )

    snapshot = build_profile_snapshot(user, profile_type)
    return snapshot
