"""Create the interior_design database and all collections with field indexes."""
from __future__ import annotations
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from motor.motor_asyncio import AsyncIOMotorClient
from app.config import settings


FIELD_INDEXES = {
    "furniture": [
        [("category", 1)],
        [("price_usd", 1)],
        [("style_tags", 1)],
        [("source", 1)],
    ],
    "designs": [
        [("user_id", 1)],
        [("user_id", 1), ("deleted_at", 1)],
        [("created_at", -1)],
    ],
    "preferences": [
        [("user_id", 1)],
        [("is_template", 1)],
    ],
    "chat_sessions": [
        [("user_id", 1)],
        [("design_id", 1)],
    ],
}

PREFERENCE_TEMPLATES = [
    {
        "_id": "tpl_minimalist",
        "user_id": None,
        "is_template": True,
        "template_name": "minimalist",
        "style_tags": ["minimalist", "clean", "modern"],
        "color_palette": ["#FFFFFF", "#F5F5F5", "#E0E0E0", "#9E9E9E", "#424242", "#000000"],
        "material_preferences": ["wood", "metal", "glass"],
        "spatial_density": "sparse",
        "philosophies": [
            "Less is more. Every piece must earn its place.",
            "Prefer neutral tones and clean lines.",
        ],
        "hard_requirements": {},
        # "taste_vector": None,
    },
    {
        "_id": "tpl_cozy",
        "user_id": None,
        "is_template": True,
        "template_name": "cozy",
        "style_tags": ["cozy", "warm", "rustic", "hygge"],
        "color_palette": ["#FFF8E1", "#FFECB3", "#FFE082", "#D7CCC8", "#A1887F", "#6D4C41"],
        "material_preferences": ["wood", "fabric", "wool", "leather"],
        "spatial_density": "dense",
        "philosophies": [
            "Create warmth with layered textiles and soft lighting.",
            "Prefer natural materials and earthy tones.",
        ],
        "hard_requirements": {},
        # "taste_vector": None,
    },
    {
        "_id": "tpl_midcentury",
        "user_id": None,
        "is_template": True,
        "template_name": "midcentury",
        "style_tags": ["midcentury", "retro", "organic", "modern"],
        "color_palette": ["#FFF9C4", "#F9A825", "#E65100", "#1B5E20", "#0D47A1", "#37474F"],
        "material_preferences": ["teak", "walnut", "fiberglass", "wool"],
        "spatial_density": "balanced",
        "philosophies": [
            "Form follows function with organic shapes.",
            "Mix wood tones with bold accent colors.",
        ],
        "hard_requirements": {},
        # "taste_vector": None,
    },
]


async def main() -> None:
    client = AsyncIOMotorClient(settings.mongodb_uri)
    db = client[settings.mongodb_db]

    for collection, index_specs in FIELD_INDEXES.items():
        col = db[collection]
        for spec in index_specs:
            await col.create_index(spec)
            print(f"  index {spec} on {collection}")

    col = db["preferences"]
    for tpl in PREFERENCE_TEMPLATES:
        await col.update_one({"_id": tpl["_id"]}, {"$setOnInsert": tpl}, upsert=True)
        print(f"  seeded template: {tpl['template_name']}")

    client.close()
    print("Done.")


if __name__ == "__main__":
    asyncio.run(main())
