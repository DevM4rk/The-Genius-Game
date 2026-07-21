# The Genius Game - 종합 웹 보드게임 플랫폼

전체 아키텍처는 `docs/ARCHITECTURE.md` 참고.

## 현재 단계
**Phase 1 완료:** 로컬 자유오목 2인 대전 (C++ + Godot GDExtension + 승리 팝업)

다음: Phase 2 — FastAPI + WebSocket 온라인 대전

## 폴더 구조
```
The-Genius-Game/
  core/gomoku/          # C++ 오목 로직
  core/gomoku_gdext/    # GDExtension 래퍼
  frontend/gomoku/      # Godot 4 프로젝트
  backend/              # FastAPI (Phase 2)
  infra/                # Docker, Nginx (Phase 3)
  docs/                 # 설계 문서
```
