from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict

_ENV_FILE = Path(__file__).parent.parent / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=_ENV_FILE, extra="ignore")

    mongodb_uri: str
    mongodb_db: str = "interior_design"

    gemini_api_key: str = ""

    clip_model: str = "ViT-B-32"
    clip_pretrained: str = "openai"


settings = Settings()
