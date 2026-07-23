"""FastAPI 진입점 — REST(방 생성) + WebSocket(대전)."""

from __future__ import annotations

import asyncio
from typing import Callable

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from .blackwhite import BWRoom, bw_manager
from .room import MatchQueue, Room, manager

app = FastAPI(title="The Genius Game - Gomoku", version="0.2.0")

# game_id -> 해당 게임의 방 생성 함수. 목록에 없는 game_id는 오목 방으로 처리된다.
GAME_ROOM_FACTORIES: dict[str, Callable[[], str]] = {
    "black_white": bw_manager.create_room,
}
quick_queue = MatchQueue(GAME_ROOM_FACTORIES, default_factory=manager.create_room)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/api/rooms")
async def create_room() -> dict[str, str]:
    room_id = manager.create_room()
    return {
        "room_id": room_id,
        "join_url": f"/play/{room_id}",
        "ws_url": f"/ws/{room_id}",
    }


@app.get("/api/rooms/{room_id}")
async def get_room(room_id: str) -> dict:
    room = manager.get(room_id)
    if room is None:
        return {"room_id": room_id, "exists": False, "players": 0}
    public = manager.room_public(room)
    public["exists"] = True
    return public


async def _run_room_message_loop(room: Room, websocket: WebSocket) -> None:
    """place/restart/ping 메시지 루프 — 방/빠른매칭 양쪽에서 공유."""
    try:
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type")

            if msg_type == "place":
                x = int(data.get("x", -1))
                y = int(data.get("y", -1))
                await manager.handle_place(room, websocket, x, y)
            elif msg_type == "restart":
                await manager.handle_restart(room, websocket)
            elif msg_type == "ping":
                await websocket.send_json({"type": "pong"})
            else:
                await websocket.send_json(
                    {"type": "error", "message": f"unknown_type:{msg_type}"},
                )
    except WebSocketDisconnect:
        pass
    finally:
        await manager.disconnect(room.room_id, websocket)


async def _run_bw_message_loop(room: BWRoom, websocket: WebSocket) -> None:
    """흑과백 전용 메시지 루프 — bw_arrange/bw_play/bw_rematch."""
    try:
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type")

            if msg_type == "bw_arrange":
                arrangement = [int(v) for v in data.get("arrangement", [])]
                await bw_manager.handle_arrange(room, websocket, arrangement)
            elif msg_type == "bw_play":
                slot = int(data.get("slot", -1))
                await bw_manager.handle_play(room, websocket, slot)
            elif msg_type == "bw_rematch":
                await bw_manager.handle_rematch(room, websocket)
            elif msg_type == "ping":
                await websocket.send_json({"type": "pong"})
            else:
                await websocket.send_json(
                    {"type": "error", "message": f"unknown_type:{msg_type}"},
                )
    except WebSocketDisconnect:
        pass
    finally:
        await bw_manager.disconnect(room.room_id, websocket)


@app.websocket("/ws/quick")
async def websocket_quick_match(
    websocket: WebSocket,
    game: str | None = None,
) -> None:
    """게스트 빠른 매칭.

    query `game`:
      - 없거나 `any` → B(완전 랜덤)
      - 그 외 → A(해당 게임 대기)
    """
    preferred: str | None = None
    if game and game.strip() and game.strip().lower() != "any":
        preferred = game.strip().lower()

    await websocket.accept()
    await websocket.send_json({"type": "queued", "game": preferred or "any"})

    enqueue_task = asyncio.create_task(quick_queue.enqueue(websocket, preferred))
    watch_task = asyncio.create_task(websocket.receive_json())

    done, pending = await asyncio.wait(
        {enqueue_task, watch_task}, return_when=asyncio.FIRST_COMPLETED
    )

    if enqueue_task not in done:
        enqueue_task.cancel()
        if watch_task.done():
            watch_task.exception()
        await quick_queue.cancel(websocket)
        return

    if watch_task in pending:
        watch_task.cancel()

    room_id, game_id = enqueue_task.result()

    if game_id == "black_white":
        bw_room = await bw_manager.connect(room_id, websocket)
        if bw_room is None:
            await websocket.send_json({"type": "error", "message": "room_full"})
            await websocket.close(code=4000)
            return
        await websocket.send_json(
            {"type": "matched", "room_id": room_id, "game_id": game_id},
        )
        await bw_manager.on_joined(bw_room, websocket)
        await _run_bw_message_loop(bw_room, websocket)
        return

    room = await manager.connect(room_id, websocket)
    if room is None:
        await websocket.send_json({"type": "error", "message": "room_full"})
        await websocket.close(code=4000)
        return

    await websocket.send_json(
        {"type": "matched", "room_id": room_id, "game_id": game_id},
    )
    await manager.on_joined(room, websocket)
    await _run_room_message_loop(room, websocket)


@app.websocket("/ws/{room_id}")
async def websocket_room(websocket: WebSocket, room_id: str) -> None:
    await websocket.accept()

    room = await manager.connect(room_id, websocket)
    if room is None:
        await websocket.send_json(
            {"type": "error", "message": "room_full"},
        )
        await websocket.close(code=4000)
        return

    await manager.on_joined(room, websocket)
    await _run_room_message_loop(room, websocket)
