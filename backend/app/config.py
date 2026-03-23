"""
Signtone - Application Configuration
======================================
All settings loaded from environment variables via .env file.
Access anywhere with: from app.config import settings
"""

from pydantic_settings import BaseSettings
from pydantic import Field
from pathlib import Path


class Settings(BaseSettings):

    # ── App ───────────────────────────────────────────────────────────────────
    APP_NAME: str    = "Signtone"
    APP_VERSION: str = "1.0.0"

    # ── MongoDB ───────────────────────────────────────────────────────────────
    MONGODB_URL: str = "mongodb://localhost:27017"
    MONGODB_DB: str  = "signtone"

    # ── Redis ─────────────────────────────────────────────────────────────────
    REDIS_URL: str = "redis://localhost:6379"

    # ── LinkedIn OAuth ────────────────────────────────────────────────────────
    LINKEDIN_CLIENT_ID: str     = ""
    LINKEDIN_CLIENT_SECRET: str = ""
    LINKEDIN_REDIRECT_URI: str  = "http://localhost:8000/auth/linkedin/callback"

    # ── JWT ───────────────────────────────────────────────────────────────────
    JWT_SECRET: str         = "signtone_dev_secret_change_in_production"
    JWT_ALGORITHM: str      = "HS256"
    JWT_EXPIRE_MINUTES: int = 10080   # 7 days

    # ── Beacon ────────────────────────────────────────────────────────────────
    VECTOR_DIMENSIONS: int  = 512
    VECTOR_CONTENT_TYPE: str = "env"

    class Config:
        # Always look for .env in the backend/ folder
        env_file = Path(__file__).parent.parent / ".env"
        env_file_encoding = "utf-8"
        extra = "ignore"


# Single shared instance - import this everywhere
settings = Settings()
