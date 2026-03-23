"""
Signtone - FastAPI Application Entry Point
"""

from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import connect, disconnect
from app.api import signals, events, auth, registrations, profiles
import logging

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s - %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # ── Startup ───────────────────────────────────────────────────────────────
    logger.info("Starting Signtone API...")
    await connect()
    logger.info("Signtone API ready ✅")
    yield
    # ── Shutdown ──────────────────────────────────────────────────────────────
    logger.info("Shutting down Signtone API...")
    await disconnect()


app = FastAPI(
    title="Signtone API",
    description="Register by sound - audio-triggered identity registration platform",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(signals.router, prefix="/signals", tags=["signals"])
app.include_router(events.router,  prefix="/events",  tags=["events"])
app.include_router(auth.router,    prefix="/auth",    tags=["auth"])
app.include_router(registrations.router, prefix="/registrations", tags=["registrations"])
app.include_router(profiles.router,      prefix="/profiles",      tags=["profiles"])

@app.get("/health")
async def health():
    return {
        "status": "ok",
        "service": "Signtone API",
        "version": "1.0.0",
    }
