# 아키텍처 청사진

## 계층 구조
1. **Frontend**: Godot Engine 4 (Web Export) + GDScript
   - UI, 렌더링, 이벤트 처리
2. **Core Engine**: C++ (GDExtension)
   - 보드 2차원 배열 상태 관리, 5목 승패/반칙 판정
   - AI 싱글플레이는 클라이언트(브라우저) 자원으로 오프라인 연산
3. **Backend**: Python (FastAPI + WebSocket)
   - 실시간 통신, 턴 시간 관리(30초 룰), 관전(Spectator) 권한 분리
4. **DB/Auth**: Google OAuth 2.0, PostgreSQL(회원/Elo), Redis(매칭 대기열/세션)
5. **Infra**: Docker & docker-compose, Nginx(정적 서빙/리버스 프록시/COOP·COEP/WSS)

## 데이터 파이프라인
- **랭크 게임**: 구글 로그인 -> FastAPI가 JWT 발급 -> Godot가 토큰 들고 WS 랭크 매칭 요청 -> Redis로 유사 점수대 매칭
- **사설 방 게임**: 방 생성 시 고유 URL(`/play/abc12`) 발급 -> 해당 링크 접속 시 URL 파라미터 파싱 -> 파이썬 소켓 Room으로 묶음
- **AI 싱글플레이**: Godot가 서버 WS 통신을 차단하고 내장 C++ AI 모듈 호출 -> 서버 비용 없이 단독 구동

## 진행 단계 (Phase)
- **Phase 1 (현재)**: 로컬 자유오목 2인 대전 (core + frontend, 서버/로그인/AI 없음)
- **Phase 2**: FastAPI + WebSocket 실시간 2인 대전 (사설 방 URL 방식부터)
- **Phase 3**: Google OAuth, PostgreSQL, Redis, 랭크 매칭
- **Phase 4**: Docker/Nginx 배포, AI 싱글플레이
- **Phase 5+**: 오목 외 다른 보드게임 추가
