"""FastAPI 진입점 — REST(방 생성) + WebSocket(대전)."""

from __future__ import annotations

import asyncio
from typing import Callable

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from .betting_rps import BettingRPSRules
from .blackwhite import BWRoom, bw_manager
from .blackwhite2 import BW2Room, bw2_manager
from .duel import DuelRoom, DuelRoomManager
from .number_janggi import NJRoom, nj_manager
from .poker_duel import IndianPokerRules
from .room import MatchQueue, Room, manager

app = FastAPI(title="The Genius Game - Gomoku", version="0.2.0")

# 공용 1:1 방(duel_*)을 쓰는 게임들. game_id -> 방 관리자.
DUEL_MANAGERS: dict[str, DuelRoomManager] = {
    rules.game_id: DuelRoomManager(rules)
    for rules in (BettingRPSRules(), IndianPokerRules())
}

# game_id -> 해당 게임의 방 생성 함수. 목록에 없는 game_id는 오목 방으로 처리된다.
GAME_ROOM_FACTORIES: dict[str, Callable[[], str]] = {
    "black_white": bw_manager.create_room,
    "black_white2": bw2_manager.create_room,
    "number_janggi": nj_manager.create_room,
    **{game_id: m.create_room for game_id, m in DUEL_MANAGERS.items()},
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


async def _run_bw2_message_loop(room: BW2Room, websocket: WebSocket) -> None:
    """흑과백2 전용 메시지 루프 — bw2_bid/bw2_rematch."""
    try:
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type")

            if msg_type == "bw2_bid":
                try:
                    amount = int(data.get("amount", -1))
                except (TypeError, ValueError):
                    amount = -1
                await bw2_manager.handle_bid(room, websocket, amount)
            elif msg_type == "bw2_rematch":
                await bw2_manager.handle_rematch(room, websocket)
            elif msg_type == "ping":
                await websocket.send_json({"type": "pong"})
            else:
                await websocket.send_json(
                    {"type": "error", "message": f"unknown_type:{msg_type}"},
                )
    except WebSocketDisconnect:
        pass
    finally:
        await bw2_manager.disconnect(room.room_id, websocket)


async def _run_duel_message_loop(
    duel_manager: DuelRoomManager, room: DuelRoom, websocket: WebSocket
) -> None:
    """공용 1:1 방 메시지 루프 — duel_action/duel_rematch."""
    try:
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type")

            if msg_type == "duel_action":
                await duel_manager.handle_action(room, websocket, data)
            elif msg_type == "duel_rematch":
                await duel_manager.handle_rematch(room, websocket)
            elif msg_type == "ping":
                await websocket.send_json({"type": "pong"})
            else:
                await websocket.send_json(
                    {"type": "error", "message": f"unknown_type:{msg_type}"},
                )
    except WebSocketDisconnect:
        pass
    finally:
        await duel_manager.disconnect(room.room_id, websocket)


async def _run_nj_message_loop(room: NJRoom, websocket: WebSocket) -> None:
    """숫자장기 전용 메시지 루프 — nj_arrange_*/nj_ready/nj_move/nj_item*/nj_revive 등."""
    try:
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type")

            if msg_type == "nj_arrange_move":
                await nj_manager.handle_arrange_move(
                    room,
                    websocket,
                    int(data.get("piece_id", -1)),
                    int(data.get("col", -1)),
                    int(data.get("row", -1)),
                )
            elif msg_type == "nj_arrange_swap":
                await nj_manager.handle_arrange_swap(
                    room,
                    websocket,
                    int(data.get("piece_id_a", -1)),
                    int(data.get("piece_id_b", -1)),
                )
            elif msg_type == "nj_arrange_reset":
                await nj_manager.handle_arrange_reset(room, websocket)
            elif msg_type == "nj_ready":
                await nj_manager.handle_ready(room, websocket)
            elif msg_type == "nj_move":
                await nj_manager.handle_move(
                    room,
                    websocket,
                    int(data.get("piece_id", -1)),
                    int(data.get("col", -1)),
                    int(data.get("row", -1)),
                )
            elif msg_type == "nj_item":
                await nj_manager.handle_item(room, websocket, int(data.get("item_type", -1)))
            elif msg_type == "nj_item_decline":
                await nj_manager.handle_item_decline(room, websocket)
            elif msg_type == "nj_revive":
                await nj_manager.handle_revive(room, websocket, int(data.get("piece_id", -1)))
            elif msg_type == "nj_decline_reward":
                await nj_manager.handle_decline_reward(room, websocket)
            elif msg_type == "nj_rematch":
                await nj_manager.handle_rematch(room, websocket)
            elif msg_type == "ping":
                await websocket.send_json({"type": "pong"})
            else:
                await websocket.send_json(
                    {"type": "error", "message": f"unknown_type:{msg_type}"},
                )
    except WebSocketDisconnect:
        pass
    finally:
        await nj_manager.disconnect(room.room_id, websocket)


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

    duel_manager = DUEL_MANAGERS.get(game_id)
    if duel_manager is not None:
        duel_room = await duel_manager.connect(room_id, websocket)
        if duel_room is None:
            await websocket.send_json({"type": "error", "message": "room_full"})
            await websocket.close(code=4000)
            return
        await websocket.send_json(
            {"type": "matched", "room_id": room_id, "game_id": game_id},
        )
        await duel_manager.on_joined(duel_room, websocket)
        await _run_duel_message_loop(duel_manager, duel_room, websocket)
        return

    if game_id == "black_white2":
        bw2_room = await bw2_manager.connect(room_id, websocket)
        if bw2_room is None:
            await websocket.send_json({"type": "error", "message": "room_full"})
            await websocket.close(code=4000)
            return
        await websocket.send_json(
            {"type": "matched", "room_id": room_id, "game_id": game_id},
        )
        await bw2_manager.on_joined(bw2_room, websocket)
        await _run_bw2_message_loop(bw2_room, websocket)
        return

    if game_id == "number_janggi":
        nj_room = await nj_manager.connect(room_id, websocket)
        if nj_room is None:
            await websocket.send_json({"type": "error", "message": "room_full"})
            await websocket.close(code=4000)
            return
        await websocket.send_json(
            {"type": "matched", "room_id": room_id, "game_id": game_id},
        )
        await nj_manager.on_joined(nj_room, websocket)
        await _run_nj_message_loop(nj_room, websocket)
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
