"""Create Atlas Vector Search indexes for the furniture collection.

Run this once after creating the database. Atlas vector search indexes
are created via the Atlas Data API or the pymongo SearchIndexModel helper.
Requires pymongo >= 4.6.
"""
from __future__ import annotations
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from motor.motor_asyncio import AsyncIOMotorClient
from pymongo.operations import SearchIndexModel
from app.config import settings

VECTOR_INDEXES = [
    SearchIndexModel(
        definition={
            "fields": [
                {
                    "type": "vector",
                    "path": "visual_embedding",
                    "numDimensions": 512,
                    "similarity": "cosine",
                }
            ]
        },
        name="visual_index",
        type="vectorSearch",
    ),
    SearchIndexModel(
        definition={
            "fields": [
                {
                    "type": "vector",
                    "path": "text_embedding",
                    "numDimensions": 512,
                    "similarity": "cosine",
                }
            ]
        },
        name="text_index",
        type="vectorSearch",
    ),
]


async def main() -> None:
    client = AsyncIOMotorClient(settings.mongodb_uri)
    col = client[settings.mongodb_db]["furniture"]

    existing = {idx["name"] async for idx in col.list_search_indexes()}
    for model in VECTOR_INDEXES:
        if model.document["name"] in existing:
            print(f"  index {model.document['name']} already exists, skipping")
        else:
            await col.create_search_index(model)
            print(f"  created {model.document['name']}")

    client.close()
    print("Done. Note: Atlas vector search indexes take ~1 minute to become READY.")


if __name__ == "__main__":
    asyncio.run(main())
