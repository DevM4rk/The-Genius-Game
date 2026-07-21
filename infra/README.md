# Infra (Phase 4)

로컬에서 "실제 배포와 같은 구조"를 그대로 재현하는 Docker + Nginx 구성.
같은 이미지/설정을 나중에 AWS(EC2 등)에 그대로 옮겨서 씀.

## 구성

```
infra/
  docker-compose.yml   # backend + nginx 두 컨테이너
  nginx/nginx.conf      # 정적 서빙 + /api,/ws 프록시 + COOP/COEP 헤더
```

## 1. 로컬 실행

```powershell
cd infra
docker compose up --build
```

- `http://localhost:8080/health` → `{"status":"ok"}` 확인 (backend가 살아있는지)
- `http://localhost:8080/` → Godot Web Export 결과물 (아직 없으면 404 — 아래 3번 참고)

종료: `docker compose down`

## 2. 구조 설명

| 컨테이너 | 역할 | 외부 노출 |
|---|---|---|
| `backend` | FastAPI + WebSocket (오목 서버 로직) | 안 함 — nginx만 접근 가능 |
| `nginx` | 브라우저가 실제로 접속하는 창구 | `localhost:8080` |

브라우저 → `nginx` → (`/api/*`, `/ws/*`는) `backend`, (나머지는) 정적 파일.
COOP/COEP 헤더는 Godot Web Export가 스레드(SharedArrayBuffer)를 쓸 때 브라우저가 요구하는 보안 헤더라, nginx가 모든 응답에 붙여준다.

## 3. Godot Web Export 붙이기

### 3-1. GDExtension을 wasm으로 빌드 (emsdk 필요)

```powershell
# emsdk가 없다면: https://emscripten.org/docs/getting_started/downloads.html
cd core/gomoku_gdext
scons platform=web target=template_debug
scons platform=web target=template_release
```

`frontend/gomoku/bin/libgomoku.web.template_debug.wasm32.wasm` 등이 생성되면 성공.
(`gomoku.gdextension`에 이미 `web.debug.wasm32` / `web.release.wasm32` 항목 등록해둠.)

### 3-2. Godot 에디터에서 Web Export

1. Godot 4 에디터에서 `frontend/gomoku` 프로젝트 열기
2. **Project > Export** → **Web** 프리셋 추가 (Export Templates 설치 필요)
3. **Thread Support** 켜기 (위 GDExtension을 기본값(threads=yes)으로 빌드했다면 반드시 켜야 함)
4. Export Path: `export/web/index.html` 로 지정 후 Export
5. 결과물이 `frontend/gomoku/export/web/`에 생기면 `docker compose up`한 nginx가 그대로 서빙

### 3-3. 로컬 실행 환경 제한

이 저장소 작업 환경에는 `docker`, `godot`, `emcc`가 설치되어 있지 않아서 위 3단계는 실제로 실행/검증하지
못했음 (설정 파일 문법과 경로만 검토). 사용자 PC에서 위 명령을 그대로 실행해서 확인 필요.
