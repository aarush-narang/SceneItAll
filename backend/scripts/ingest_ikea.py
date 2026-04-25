"""Ingest IKEA catalog items: render → CLIP embed → upload → insert into MongoDB.

Usage:
    python scripts/ingest_ikea.py --catalog path/to/catalog.json

The catalog JSON should be a list of objects with at minimum:
    id, source_url, name, description, category, price_usd,
    dimensions (width_m, height_m, depth_m), usdz_local_path, thumbnail_local_path
    color_tags, material_tags, style_tags  (optional lists)
"""
from __future__ import annotations
import argparse
import asyncio
import json
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from motor.motor_asyncio import AsyncIOMotorClient
from app.config import settings
from app.services.embeddings import embed_text, embed_images_mean
from app.services.render import render_usdz_4angles
from app.services.storage import upload_file
import shutil


async def ingest_item(col, item: dict) -> None:
    item_id = item.get("id") or str(uuid.uuid4())

    if await col.find_one({"_id": item_id}):
        print(f"  skip {item_id} (already exists)")
        return

    usdz_local = Path(item["usdz_local_path"])
    thumb_local = Path(item["thumbnail_local_path"])

    renders = render_usdz_4angles(usdz_local)
    visual_embedding = embed_images_mean(renders)
    for r in renders:
        r.unlink(missing_ok=True)
    shutil.rmtree(renders[0].parent, ignore_errors=True)

    text_embedding = embed_text(item["description"])

    dims = item["dimensions"]
    w, h, d = dims["width_m"], dims["height_m"], dims["depth_m"]
    max_dim = max(w, h, d) or 1.0
    dimension_vector = [w / max_dim, h / max_dim, d / max_dim]

    usdz_key = f"furniture/{item_id}/model.usdz"
    thumb_key = f"furniture/{item_id}/thumbnail.png"
    usdz_url = upload_file(usdz_local, usdz_key, "model/vnd.usdz+zip")
    thumbnail_url = upload_file(thumb_local, thumb_key, "image/png")

    doc = {
        "_id": item_id,
        "source": "ikea",
        "source_url": item["source_url"],
        "name": item["name"],
        "description": item["description"],
        "category": item["category"],
        "price_usd": float(item["price_usd"]),
        "dimensions": {"width_m": w, "height_m": h, "depth_m": d},
        "usdz_url": usdz_url,
        "thumbnail_url": thumbnail_url,
        "visual_embedding": visual_embedding,
        "text_embedding": text_embedding,
        "dimension_vector": dimension_vector,
        "color_tags": item.get("color_tags", []),
        "material_tags": item.get("material_tags", []),
        "style_tags": item.get("style_tags", []),
        "created_at": datetime.now(timezone.utc),
    }
    await col.insert_one(doc)
    print(f"  inserted {item_id}: {item['name']}")


async def main(catalog_path: str) -> None:
    items = json.loads(Path(catalog_path).read_text())
    client = AsyncIOMotorClient(settings.mongodb_uri)
    col = client[settings.mongodb_db]["furniture"]

    for item in items:
        try:
            await ingest_item(col, item)
        except Exception as exc:
            print(f"  ERROR on {item.get('id', '?')}: {exc}", file=sys.stderr)

    client.close()
    print(f"Ingested {len(items)} items.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", required=True, help="Path to catalog JSON file")
    args = parser.parse_args()
    asyncio.run(main(args.catalog))
