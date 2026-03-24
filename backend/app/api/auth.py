"""
Signtone - Auth API
====================
LinkedIn OAuth 2.0 flow + JWT token management + Guest login.

Routes:
    POST /auth/guest                 guest login (name + email → JWT)
    GET  /auth/linkedin              redirect user to LinkedIn consent screen
    GET  /auth/linkedin/callback     handle LinkedIn redirect, issue JWT
    GET  /auth/me                    get current user profile
    POST /auth/logout                invalidate session
    POST /auth/refresh               refresh LinkedIn token
"""

import logging
import secrets
import urllib.parse
from datetime import datetime, timedelta, timezone
from typing import Optional

import httpx
from bson import ObjectId
from fastapi import APIRouter, HTTPException, Query, Header
from fastapi.responses import RedirectResponse
from jose import JWTError, jwt
from pydantic import BaseModel

from app.config import settings
from app.database import col_users
from app.models.user import (
    UserDocument, UserResponse, ProfessionalProfile,
    PublicProfile, user_from_doc
)

logger = logging.getLogger(__name__)
router = APIRouter()

# ── LinkedIn OAuth constants ──────────────────────────────────────────────────
LINKEDIN_AUTH_URL    = "https://www.linkedin.com/oauth/v2/authorization"
LINKEDIN_TOKEN_URL   = "https://www.linkedin.com/oauth/v2/accessToken"
LINKEDIN_PROFILE_URL = "https://api.linkedin.com/v2/userinfo"
LINKEDIN_SCOPES      = "openid profile email"

# In-memory state store for CSRF protection
_oauth_states: dict[str, datetime] = {}


# ── Helpers ───────────────────────────────────────────────────────────────────

def create_jwt(user_id: str) -> str:
    """Create a signed JWT token for a user."""
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.JWT_EXPIRE_MINUTES
    )
    payload = {
        "sub": user_id,
        "exp": expire,
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)


def decode_jwt(token: str) -> str:
    """Decode a JWT and return the user_id (sub claim)."""
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET,
            algorithms=[settings.JWT_ALGORITHM]
        )
        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token")
        return user_id
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")


async def get_current_user(authorization: str = Header(...)) -> dict:
    """
    Dependency - extract and verify JWT from Authorization header.
    Usage: user = Depends(get_current_user)
    """
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Bearer token required")
    token   = authorization.split(" ", 1)[1]
    user_id = decode_jwt(token)
    user    = await col_users().find_one({"_id": ObjectId(user_id)})
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return user


# ── Guest login ───────────────────────────────────────────────────────────────

class GuestLoginRequest(BaseModel):
    name:  str
    email: str
    phone: Optional[str] = None


@router.post("/guest")
async def guest_login(payload: GuestLoginRequest):
    """
    Create or retrieve a guest user and issue a JWT.
    Guest users have no LinkedIn profile - only a public profile.
    """
    email = payload.email.strip().lower()
    now   = datetime.now(timezone.utc)

    existing = await col_users().find_one({"email": email})

    if existing:
        user_id = str(existing["_id"])
        await col_users().update_one(
            {"_id": existing["_id"]},
            {"$set": {"display_name": payload.name, "updated_at": now}}
        )
        logger.info(f"Guest login for existing user: {email}")
    else:
        doc = {
            "email":        email,
            "display_name": payload.name,
            "phone":        payload.phone,
            "auth_type":    "guest",
            "is_active":    True,
            "professional_profile": None,
            "public_profile": {
                "display_name": payload.name,
                "email":        email,
                "phone":        payload.phone or "",
            },
            "created_at": now,
            "updated_at": now,
        }
        result  = await col_users().insert_one(doc)
        user_id = str(result.inserted_id)
        logger.info(f"Created guest user: {email}")

    jwt_token = create_jwt(user_id)
    return {
        "access_token": jwt_token,
        "user_id":      user_id,
        "name":         payload.name,
        "email":        email,
        "auth_type":    "guest",
    }


# ── Step 1 - redirect to LinkedIn ────────────────────────────────────────────

@router.get("/linkedin")
async def linkedin_login():
    """
    Redirect the user to LinkedIn's consent screen.
    Mobile app opens this URL in a web view.
    """
    if not settings.LINKEDIN_CLIENT_ID:
        raise HTTPException(
            status_code=503,
            detail="LinkedIn OAuth not configured - add LINKEDIN_CLIENT_ID to .env"
        )

    state = secrets.token_urlsafe(16)
    _oauth_states[state] = datetime.now(timezone.utc)

    cutoff  = datetime.now(timezone.utc) - timedelta(minutes=10)
    expired = [k for k, v in _oauth_states.items() if v < cutoff]
    for k in expired:
        del _oauth_states[k]

    params = {
        "response_type": "code",
        "client_id":     settings.LINKEDIN_CLIENT_ID,
        "redirect_uri":  settings.LINKEDIN_REDIRECT_URI,
        "scope":         LINKEDIN_SCOPES,
        "state":         state,
    }
    query = "&".join(f"{k}={v}" for k, v in params.items())
    url   = f"{LINKEDIN_AUTH_URL}?{query}"
    logger.info("Redirecting to LinkedIn OAuth")
    return {"auth_url": url}


# ── Step 2 - handle LinkedIn callback ────────────────────────────────────────

@router.get("/linkedin/callback")
async def linkedin_callback(
    code:  str = Query(...),
    state: str = Query(...),
    error: Optional[str] = Query(None),
):
    if error:
        raise HTTPException(status_code=400, detail=f"LinkedIn OAuth error: {error}")

    # Verify CSRF state - log warning but don't fail on duplicate callback
    # iOS FlutterWebAuth2 sometimes fires the callback twice
    if state in _oauth_states:
        del _oauth_states[state]
    else:
        logger.warning(f"OAuth state '{state}' not found - possible duplicate callback, proceeding")
 
    async with httpx.AsyncClient() as client:
        token_resp = await client.post(
            LINKEDIN_TOKEN_URL,
            data={
                "grant_type":    "authorization_code",
                "code":          code,
                "redirect_uri":  settings.LINKEDIN_REDIRECT_URI,
                "client_id":     settings.LINKEDIN_CLIENT_ID,
                "client_secret": settings.LINKEDIN_CLIENT_SECRET,
            },
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )

    if token_resp.status_code != 200:
        logger.error(f"LinkedIn token exchange failed: {token_resp.text}")
        raise HTTPException(status_code=400, detail="Failed to exchange LinkedIn code for token")

    token_data   = token_resp.json()
    access_token = token_data.get("access_token")
    expires_in   = token_data.get("expires_in", 3600)
    token_expiry = datetime.now(timezone.utc) + timedelta(seconds=expires_in)

    async with httpx.AsyncClient() as client:
        profile_resp = await client.get(
            LINKEDIN_PROFILE_URL,
            headers={"Authorization": f"Bearer {access_token}"},
        )

    if profile_resp.status_code != 200:
        logger.error(f"LinkedIn profile fetch failed: {profile_resp.text}")
        raise HTTPException(status_code=400, detail="Failed to fetch LinkedIn profile")

    profile_data = profile_resp.json()
    logger.info(f"LinkedIn profile fetched for: {profile_data.get('email')}")

    professional_profile = ProfessionalProfile(
        linkedin_id      = profile_data.get("sub"),
        full_name        = profile_data.get("name"),
        headline         = profile_data.get("headline", ""),
        company          = profile_data.get("company", ""),
        email            = profile_data.get("email"),
        profile_url      = profile_data.get("profile_url", ""),
        photo_url        = profile_data.get("picture", ""),
        access_token     = access_token,
        token_expires_at = token_expiry,
        synced_at        = datetime.now(timezone.utc),
    )

    email = profile_data.get("email")
    if not email:
        raise HTTPException(status_code=400, detail="LinkedIn did not return an email address")

    now      = datetime.now(timezone.utc)
    existing = await col_users().find_one({"email": email})

    if existing:
        await col_users().update_one(
            {"email": email},
            {"$set": {
                "professional_profile": professional_profile.model_dump(),
                "updated_at":           now,
            }}
        )
        user_id = str(existing["_id"])
        logger.info(f"Updated LinkedIn profile for existing user: {email}")
    else:
        doc = {
            "email":                email,
            "is_active":            True,
            "professional_profile": professional_profile.model_dump(),
            "public_profile":       None,
            "created_at":           now,
            "updated_at":           now,
        }
        result  = await col_users().insert_one(doc)
        user_id = str(result.inserted_id)
        logger.info(f"Created new user via LinkedIn: {email}")

    jwt_token = create_jwt(user_id)

    callback_params = urllib.parse.urlencode({
        "access_token": jwt_token,
        "user_id":      user_id,
        "email":        email,
        "name":         profile_data.get("name", ""),
        "picture":      profile_data.get("picture", ""),
        "headline":     profile_data.get("headline", ""),
    })
    logger.info(f"Redirecting to mobile app for user: {email}")
    return RedirectResponse(f"signtone://auth/callback?{callback_params}")


# ── Get current user ──────────────────────────────────────────────────────────

@router.get("/me", response_model=UserResponse)
async def get_me(authorization: str = Header(...)):
    user = await get_current_user(authorization)
    return user_from_doc(user)


# ── Logout ────────────────────────────────────────────────────────────────────

@router.post("/logout", status_code=204)
async def logout(authorization: str = Header(...)):
    user = await get_current_user(authorization)
    await col_users().update_one(
        {"_id": user["_id"]},
        {"$set": {
            "professional_profile.access_token":     None,
            "professional_profile.token_expires_at": None,
            "updated_at": datetime.now(timezone.utc),
        }}
    )
    logger.info(f"User logged out: {user['email']}")


# ── Refresh LinkedIn token ────────────────────────────────────────────────────

@router.post("/refresh")
async def refresh_token(authorization: str = Header(...)):
    await get_current_user(authorization)

    state = secrets.token_urlsafe(16)
    _oauth_states[state] = datetime.now(timezone.utc)

    params = {
        "response_type": "code",
        "client_id":     settings.LINKEDIN_CLIENT_ID,
        "redirect_uri":  settings.LINKEDIN_REDIRECT_URI,
        "scope":         LINKEDIN_SCOPES,
        "state":         state,
    }
    query = "&".join(f"{k}={v}" for k, v in params.items())
    return {"auth_url": f"{LINKEDIN_AUTH_URL}?{query}"}
