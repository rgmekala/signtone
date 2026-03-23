"""
Signtone - MongoDB Database Connection
=======================================
Async MongoDB connection using Motor.
Provides a single shared client and typed collection accessors
used by all services and API routes.
"""

import logging
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase
from pymongo import IndexModel, ASCENDING
from pymongo.errors import ServerSelectionTimeoutError
from app.config import settings

logger = logging.getLogger(__name__)

# ── Single shared client instance ────────────────────────────────────────────
_client: AsyncIOMotorClient | None = None
_db: AsyncIOMotorDatabase | None = None


def get_client() -> AsyncIOMotorClient:
    if _client is None:
        raise RuntimeError("Database not initialised - call connect() first")
    return _client


def get_db() -> AsyncIOMotorDatabase:
    if _db is None:
        raise RuntimeError("Database not initialised - call connect() first")
    return _db


# ── Collection accessors ──────────────────────────────────────────────────────
# Each function returns a typed Motor collection.
# Import and call these in your services and API routes.

def col_events():
    """Events collection - stores event metadata."""
    return get_db()["events"]

def col_signals():
    """Signals collection - stores beacon payloads linked to events."""
    return get_db()["signals"]

def col_users():
    """Users collection - stores user profiles (public + LinkedIn)."""
    return get_db()["users"]

def col_registrations():
    """Registrations collection - records who registered for what event."""
    return get_db()["registrations"]

def col_sweepstakes():
    """Sweepstakes collection - stores draw configs and entries."""
    return get_db()["sweepstakes"]


# ── Lifecycle ─────────────────────────────────────────────────────────────────

async def connect():
    """
    Open the MongoDB connection and create all indexes.
    Called once at FastAPI startup.
    """
    global _client, _db

    logger.info(f"Connecting to MongoDB at {settings.MONGODB_URL} ...")

    _client = AsyncIOMotorClient(
        settings.MONGODB_URL,
        serverSelectionTimeoutMS=5000,
    )
    _db = _client[settings.MONGODB_DB]

    # Verify connection
    try:
        await _client.admin.command("ping")
        logger.info(f"MongoDB connected - database: '{settings.MONGODB_DB}'")
    except ServerSelectionTimeoutError as e:
        logger.error(f"MongoDB connection failed: {e}")
        raise

    await _create_indexes()


async def disconnect():
    """
    Close the MongoDB connection.
    Called once at FastAPI shutdown.
    """
    global _client, _db
    if _client:
        _client.close()
        _client = None
        _db = None
        logger.info("MongoDB disconnected")


async def _create_indexes():
    """
    Create all required indexes on first startup.
    Safe to call repeatedly - MongoDB ignores existing indexes.
    """
    logger.info("Creating MongoDB indexes...")

    # ── events ────────────────────────────────────────────────────────────────
    await col_events().create_indexes([
        IndexModel([("organizer_id", ASCENDING)]),
        IndexModel([("status", ASCENDING)]),
        IndexModel([("event_type", ASCENDING)]),
        IndexModel([("created_at", ASCENDING)]),
    ])

    # ── signals ───────────────────────────────────────────────────────────────
    # beacon_payload must be unique - no two events can share the same payload
    await col_signals().create_indexes([
        IndexModel([("beacon_payload", ASCENDING)], unique=True),
        IndexModel([("event_id", ASCENDING)]),
        IndexModel([("active", ASCENDING)]),
        IndexModel([("expires_at", ASCENDING)]),
    ])

    # ── users ─────────────────────────────────────────────────────────────────
    await col_users().create_indexes([
        IndexModel([("email", ASCENDING)], unique=True),
        IndexModel([("linkedin_id", ASCENDING)], sparse=True),
    ])

    # ── registrations ─────────────────────────────────────────────────────────
    # Compound unique index - one registration per user per event
    await col_registrations().create_indexes([
        IndexModel(
            [("user_id", ASCENDING), ("event_id", ASCENDING)],
            unique=True,
            name="unique_user_event"
        ),
        IndexModel([("event_id", ASCENDING)]),
        IndexModel([("user_id", ASCENDING)]),
        IndexModel([("registered_at", ASCENDING)]),
    ])

    # ── sweepstakes ───────────────────────────────────────────────────────────
    await col_sweepstakes().create_indexes([
        IndexModel([("event_id", ASCENDING)], unique=True),
        IndexModel([("status", ASCENDING)]),
        IndexModel([("draw_date", ASCENDING)]),
    ])

    logger.info("All indexes created successfully")
