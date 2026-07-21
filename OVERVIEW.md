# The Genius Game - 종합 웹 보드게임 플랫폼

전체 아키텍처는 `docs/ARCHITECTURE.md` 참고.

## 현재 단계
**Phase 4 진행 중:** AI 싱글플레이 + Docker/Nginx 배포

완료:
- Phase 1: 로컬 자유오목 2인 대전 (C++ + Godot GDExtension + 승리 팝업)
- Phase 2: 방 생성/참가, 서버 권위 착수, 30초 턴 타이머, Godot 로비
- Phase 4-1: 로비에서 "혼자 두기 / AI와 대전" 선택, C++ 규칙 기반 AI(`suggest_move`)
- Phase 4-2: `backend/Dockerfile`, `infra/docker-compose.yml`, `infra/nginx/nginx.conf` (정적 서빙 + `/api`,`/ws` 프록시 + COOP/COEP)

남음: Godot Web Export + wasm GDExtension 빌드 (emsdk 필요, `infra/README.md` 3번 참고)

다음 Phase: Phase 3 — Google OAuth, PostgreSQL, Redis, 랭크 매칭 (Phase 4 마무리 후)

## 폴더 구조
```
The-Genius-Game/
  core/gomoku/          # C++ 오목 로직 + 규칙 기반 AI(suggest_move)
  core/gomoku_gdext/    # GDExtension 래퍼
  frontend/gomoku/      # Godot 4 프로젝트 (로비 + 보드)
  backend/              # FastAPI + WebSocket (Phase 2), Dockerfile (Phase 4)
  infra/                # docker-compose, Nginx (Phase 4)
  docs/                 # 설계 문서
```

## 빠른 실행
1. 서버: `backend/README.md` 참고 (`uvicorn` on `:8000`, 또는 Docker)
2. Godot: `frontend/gomoku` 열고 실행 → 로비에서 "싱글플레이"(AI/혼자) 또는 "온라인 방 만들기"
3. 전체(Nginx 포함) 로컬 배포 재현: `infra/README.md` 참고
