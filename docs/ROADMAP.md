# Roadmap — 어디서부터 시작할 것인가

권장 순서. **의존성이 낮은 쪽 → 계약(contract) → 수직 슬라이스** 순이다.

## Phase 0 — 뼈대 (이번 PR)

- [x] 모노레포 디렉터리 구조
- [x] 공유 WebSocket 프로토콜 초안
- [x] FastAPI 스켈레톤 (health / auth stub / WS stub)
- [x] C++ Omok 코어 스텁 (보드·승패 인터페이스)
- [x] Godot 프로젝트 스텁 (로비 → 모드 분기)
- [x] docker-compose + Nginx COOP/COEP

## Phase 1 — 오프라인 오목 (서버 비용 0)

목표: Godot + C++ GDExtension만으로 AI 싱글플레이가 돌아간다.

1. C++ 보드 2D 배열, 착수, 5목/금수(렌주 옵션) 판정
2. 단순 AI (minimax / pattern heuristic)
3. GDExtension 바인딩 → Godot에서 `place_stone` / `ai_move` 호출
4. Godot 보드 UI + 싱글플레이 씬

이 단계가 끝나면 **규칙·AI가 검증된 상태**가 되어 온라인 모드의 서버 검증 로직과 정렬하기 쉽다.

## Phase 2 — 사설 방 (온라인 최소 경로)

1. FastAPI Room 생성 → `/play/{code}` URL
2. WebSocket join / move / resign / spectator
3. 서버 측 착수 검증 (Phase 1 규칙과 동일 스펙)
4. 턴 타이머 30초

## Phase 3 — 랭크 매칭

1. Google OAuth → JWT
2. Redis Elo 기반 매칭 큐
3. 매칭 성공 시 Room 자동 생성
4. PostgreSQL 회원/Elo 반영

## Phase 4 — 배포 다듬기

1. Godot Web Export 파이프라인
2. WSS + TLS
3. 관전 UI, 재접속, 레이팅 히스토리

---

**지금 당장 할 일:** Phase 0 머지 후 **Phase 1 (오프라인 오목)** 부터 구현한다.
프로토콜과 백엔드 스텁은 Phase 2에서 살을 붙인다.
