"""FastAPI application entrypoint for The Genius Game backend."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import auth, health, rooms
from app.core.config import settings
from app.core.logging import setup_logging
from app.ws.router import websocket_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    setup_logging()
    # TODO Phase 3: init Redis / DB connection pools
    yield
    # TODO: graceful shutdown of pools


def create_app() -> FastAPI:
    app = FastAPI(
        title="The Genius Game API",
        version="0.1.0",
        description="Realtime board-game platform — Omok first, more games later.",
        lifespan=lifespan,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(health.router, tags=["health"])
    app.include_router(auth.router, prefix="/auth", tags=["auth"])
    app.include_router(rooms.router, prefix="/rooms", tags=["rooms"])
    app.include_router(websocket_router)

    return app


app = create_app()
