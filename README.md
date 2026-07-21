# The Genius Game

종합 웹 보드게임 플랫폼. 설계는 `docs/ARCHITECTURE.md`, 현황은 `OVERVIEW.md`.

## Phase 2 (현재)

사설 방 코드 기반 FastAPI + WebSocket 온라인 오목 대전.

### 서버

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

자세한 API는 `backend/README.md`.

### Godot

1. `frontend/gomoku` 프로젝트를 Godot 4.7+로 연다.
2. GDExtension DLL이 빌드되어 있어야 한다 (`core/gomoku_gdext` scons).
3. 실행 → 로비에서 **로컬 2인** 또는 **온라인 방 만들기/참가**.

## 폴더 구조

```
core/gomoku/          # C++ 오목 로직
core/gomoku_gdext/    # Godot GDExtension 바인딩
frontend/gomoku/      # Godot 4 UI
backend/              # FastAPI (Phase 2)
infra/                # Docker/Nginx (Phase 3+)
docs/                 # 설계 문서
```

## GDExtension 빌드 (Windows)

```powershell
# 1회: godot-cpp
git clone --depth 1 --branch master https://github.com/godotengine/godot-cpp.git core/godot-cpp

cd core/gomoku_gdext
scons platform=windows target=template_debug
```

## C++ 로직 테스트

```powershell
g++ -std=c++17 core/gomoku/gomoku_board.cpp core/gomoku/tests/test_gomoku_board.cpp -o test_gomoku.exe
.\test_gomoku.exe
```
