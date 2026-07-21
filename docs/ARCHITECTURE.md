# The Genius Game — Architecture

종합 웹 보드게임 플랫폼. 1차 타이틀은 **오목(Omok / Gomoku)**, 이후 타이틀을 플러그인 형태로 확장한다.

## Stack

| Layer | Tech | Role |
|-------|------|------|
| Frontend | Godot 4 (Web Export) + GDScript | UI, 렌더링, 입력, 모드 분기 |
| Core Engine | C++ (GDExtension) | 보드 상태, 승패/반칙, 오프라인 AI |
| Backend | FastAPI + WebSocket | 매칭, 방, 턴 타이머(30s), 관전 |
| Auth / DB | Google OAuth 2.0, PostgreSQL, Redis | JWT, Elo, 매칭 큐/세션 |
| Infra | Docker Compose, Nginx | 정적 서빙, WSS, COOP/COEP |

## Game Modes

```
┌─────────────┐     JWT      ┌──────────────┐     Redis     ┌─────────────┐
│ Google OAuth│ ───────────► │ FastAPI Rank │ ────────────► │ Match Queue │
└─────────────┘              │   Matching   │               └─────────────┘
                             └──────┬───────┘
                                    │ WebSocket Room
                                    ▼
                             ┌──────────────┐
                             │  Rank Game   │
                             └──────────────┘

┌─────────────┐  /play/{code}  ┌──────────────┐
│ Private URL │ ─────────────► │ Private Room │
└─────────────┘                └──────────────┘

┌─────────────┐  no network    ┌──────────────┐
│ Single (AI) │ ─────────────► │ C++ GDExt AI │
└─────────────┘                └──────────────┘
```

## Repo Layout

```
backend/          # FastAPI app
core/omok/        # C++ Omok engine (GDExtension target)
frontend/         # Godot 4 project
shared/protocol/  # Cross-layer message contracts (JSON Schema + Python models)
infra/            # Nginx, docker-compose
docs/             # Architecture & roadmap
```

## Extension Point (future games)

새 보드게임 추가 시:

1. `core/<game>/` — C++ 규칙/AI 모듈
2. `frontend/games/<game>/` — Godot 씬/스크립트
3. `shared/protocol/games/<game>.json` — 메시지 스키마
4. `backend/app/games/<game>/` — 서버 측 검증/방 핸들러 (온라인 모드만)

공통 인프라(인증, 매칭, 방, 관전, 타이머)는 재사용한다.

## Security Headers (Godot Web)

Godot HTML5 + SharedArrayBuffer 를 위해 Nginx에 다음 헤더가 필요하다.

- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp`
