# backend/Dockerfile — FastAPI + WebSocket 서버용 이미지.
# 로컬/AWS 어디서든 "이 이미지 그대로 실행"이 목표라, 특별한 시스템 의존성이 없어 단일 스테이지로 충분함.

FROM python:3.12-slim

WORKDIR /app

# requirements만 먼저 복사해서 캐시 활용 (app 코드만 바뀌면 pip install 레이어는 재사용됨)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

EXPOSE 8000

# --reload는 개발용 자동 재시작 플래그라 컨테이너에선 불필요/부작용 있음 -> 프로덕션 실행에서는 제거
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
