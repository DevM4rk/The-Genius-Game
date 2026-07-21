"""FastAPI 진입점 — REST(방 생성) + WebSocket(대전)."""

from __future__ import annotations

import asyncio

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from .room import Room, manager, quick_queue

app = FastAPI(title="The Genius Game - Gomoku", version="0.2.0")

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


@app.websocket("/ws/quick")
async def websocket_quick_match(websocket: WebSocket) -> None:
    """게스트 빠른 매칭 — 로그인/Elo 없이 먼저 온 두 명을 그대로 짝지음."""
    await websocket.accept()
    await websocket.send_json({"type": "queued"})

    # 대기 중 상대를 기다리는 동시에, 그 사이 연결이 끊기는지도 감시한다
    # (receive_json이 끊김을 감지하는 유일한 방법이라 두 태스크를 경쟁시킴).
    enqueue_task = asyncio.create_task(quick_queue.enqueue(websocket))
    watch_task = asyncio.create_task(websocket.receive_json())

    done, pending = await asyncio.wait(
        {enqueue_task, watch_task}, return_when=asyncio.FIRST_COMPLETED
    )

    if enqueue_task not in done:
        enqueue_task.cancel()
        if watch_task.done():
            watch_task.exception()  # 예외를 소비해 경고 방지
        await quick_queue.cancel(websocket)
        return

    if watch_task in pending:
        watch_task.cancel()

    room_id = enqueue_task.result()
    room = await manager.connect(room_id, websocket)
    if room is None:
        await websocket.send_json({"type": "error", "message": "room_full"})
        await websocket.close(code=4000)
        return

    await websocket.send_json({"type": "matched", "room_id": room_id})
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
