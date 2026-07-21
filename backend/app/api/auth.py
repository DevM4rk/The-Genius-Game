"""Auth endpoints.

Phase 0: local/dev token minting for Godot WebSocket testing.
Phase 3: replace with Google OAuth 2.0 authorization code flow.
"""

from pydantic import BaseModel, Field

from fastapi import APIRouter, HTTPException

from app.core.security import create_access_token

router = APIRouter()


class DevLoginRequest(BaseModel):
    display_name: str = Field(min_length=1, max_length=32)
    user_id: str = Field(default="dev-user", min_length=1, max_length=64)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str
    display_name: str


class GoogleOAuthStubResponse(BaseModel):
    message: str
    authorize_url: str


@router.post("/dev/login", response_model=TokenResponse)
async def dev_login(body: DevLoginRequest) -> TokenResponse:
    """Mint a JWT without Google — development only."""
    if body.user_id.startswith("banned"):
        raise HTTPException(status_code=403, detail="user banned")
    token = create_access_token(
        subject=body.user_id,
        extra={"name": body.display_name, "elo": 1000},
    )
    return TokenResponse(
        access_token=token,
        user_id=body.user_id,
        display_name=body.display_name,
    )


@router.get("/google/start", response_model=GoogleOAuthStubResponse)
async def google_oauth_start() -> GoogleOAuthStubResponse:
    return GoogleOAuthStubResponse(
        message="Google OAuth not wired yet (Phase 3). Use POST /auth/dev/login for now.",
        authorize_url="/auth/google/callback",
    )
