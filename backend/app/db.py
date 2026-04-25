from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase
from .config import settings

_client: AsyncIOMotorClient | None = None


def get_client() -> AsyncIOMotorClient:
    global _client
    if _client is None:
        _client = AsyncIOMotorClient(settings.mongodb_uri)
    return _client


def get_db() -> AsyncIOMotorDatabase:
    return get_client()[settings.mongodb_db]


def furniture_col():
    return get_db()["furniture"]


def designs_col():
    return get_db()["designs"]


def preferences_col():
    return get_db()["preferences"]


def chat_sessions_col():
    return get_db()["chat_sessions"]


def match_decisions_col():
    return get_db()["match_decisions"]


async def check_connection() -> dict:
    try:
        await get_client().admin.command("ping")
        collections = await get_db().list_collection_names()
        return {"status": "ok", "collections": sorted(collections)}
    except Exception as exc:
        return {"status": "error", "detail": str(exc)}


async def close_client() -> None:
    global _client
    if _client is not None:
        _client.close()
        _client = None
