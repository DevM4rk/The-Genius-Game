"""HTTP helpers for private rooms (URL share flow)."""

from pydantic import BaseModel, Field

from fastapi import APIRouter, HTTPException

from app.services.room_manager import room_manager

router = APIRouter()


class CreateRoomRequest(BaseModel):
    game: str = Field(default="omok")
    ruleset: str = Field(default="freestyle")


class CreateRoomResponse(BaseModel):
    room_id: str
    join_path: str
    game: str
    mode: str = "private"


class RoomInfoResponse(BaseModel):
    room_id: str
    game: str
    mode: str
    player_count: int
    spectator_count: int
    status: str


@router.post("", response_model=CreateRoomResponse)
async def create_private_room(body: CreateRoomRequest) -> CreateRoomResponse:
    if body.game != "omok":
        raise HTTPException(status_code=400, detail=f"unsupported game: {body.game}")
    room = await room_manager.create_room(game=body.game, mode="private", ruleset=body.ruleset)
    return CreateRoomResponse(
        room_id=room.room_id,
        join_path=f"/play/{room.room_id}",
        game=room.game,
    )


@router.get("/{room_id}", response_model=RoomInfoResponse)
async def get_room(room_id: str) -> RoomInfoResponse:
    room = room_manager.get_room(room_id)
    if room is None:
        raise HTTPException(status_code=404, detail="room not found")
    return RoomInfoResponse(
        room_id=room.room_id,
        game=room.game,
        mode=room.mode,
        player_count=len(room.players),
        spectator_count=len(room.spectators),
        status=room.status,
    )
