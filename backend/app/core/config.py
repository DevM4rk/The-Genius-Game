from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "the-genius-game"
    environment: str = "development"
    debug: bool = True

    # Auth (stubs until Phase 3)
    jwt_secret: str = "dev-only-change-me"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24 * 7
    google_client_id: str = ""
    google_client_secret: str = ""

    # Data stores
    database_url: str = "postgresql+asyncpg://genius:genius@postgres:5432/genius"
    redis_url: str = "redis://redis:6379/0"

    # Game rules
    turn_seconds: int = 30
    match_elo_window: int = 150

    cors_origins: list[str] = ["http://localhost:8080", "http://127.0.0.1:8080"]


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
