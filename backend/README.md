# Backend (Phase 2)

FastAPI + WebSocket 사설 방 오목 대전 서버.

## 실행

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## API

| Method | Path | 설명 |
|--------|------|------|
| GET | `/health` | 헬스체크 |
| POST | `/api/rooms` | 방 생성 → `{ room_id, join_url, ws_url }` |
| GET | `/api/rooms/{room_id}` | 방 상태 |
| WS | `/ws/{room_id}` | 실시간 대전 |
| WS | `/ws/quick` | 게스트 빠른 매칭 (로그인/Elo 없이 먼저 온 순으로 짝짓기) |

## WebSocket 메시지

**Client → Server**
- `{"type":"place","x":7,"y":7}`
- `{"type":"restart"}`
- `{"type":"ping"}`

**Server → Client**
- `queued` — (빠른 매칭 전용) 대기열 진입
- `matched` — (빠른 매칭 전용) 상대 매칭됨, `room_id` 포함
- `joined` — 색 배정, 방 정보
- `waiting` — 상대 대기
- `game_start` — 2인 입장, 게임 시작 (턴 30초)
- `move` — 착수 브로드캐스트
- `timeout` — 턴 시간 초과 (해당 색 패배)
- `opponent_left` — 상대 퇴장
- `error` — 오류
- `pong` — ping 응답

`/ws/quick`은 대기열에 먼저 있던 소켓과 즉시 짝지어 새 방을 만든다. 로그인·Elo가 없으므로
"랭크 매칭"이 아니라 순수 FIFO 매칭이며, Phase 3에서 점수 기반 매칭으로 확장할 예정.

서버가 보드 판정의 권위 소스입니다 (Python `GomokuBoard`, C++와 동일 규칙).
