# The Genius Game - 종합 웹 보드게임 플랫폼

전체 아키텍처는 `docs/ARCHITECTURE.md` 참고.

## 현재 단계
**Phase 2 진행 중:** FastAPI + WebSocket 사설 방 온라인 대전

완료:
- Phase 1: 로컬 자유오목 2인 대전 (C++ + Godot GDExtension + 승리 팝업)
- Phase 2 MVP: 방 생성/참가, 서버 권위 착수, 30초 턴 타이머, Godot 로비

다음: Phase 3 — Google OAuth, PostgreSQL, Redis, 랭크 매칭

## 폴더 구조
```
The-Genius-Game/
  core/gomoku/          # C++ 오목 로직
  core/gomoku_gdext/    # GDExtension 래퍼
  frontend/gomoku/      # Godot 4 프로젝트 (로비 + 보드)
  backend/              # FastAPI + WebSocket (Phase 2)
  infra/                # Docker, Nginx (Phase 3+)
  docs/                 # 설계 문서
```

## Phase 2 빠른 실행
1. 서버: `backend/README.md` 참고 (`uvicorn` on `:8000`)
2. Godot: `frontend/gomoku` 열고 실행 → 로비에서 "온라인 방 만들기"
3. 다른 Godot/클라이언트에서 같은 방 코드로 참가
