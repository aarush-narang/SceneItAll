from __future__ import annotations
import uuid
from fastapi import APIRouter, HTTPException, Body
from ..db import designs_col, preferences_col
from ..models.preferences import PreferenceProfilePublic, PreferenceProfileUpsert
from ..models.design import Design
from ..services.preference_extractor import extract_from_design

router = APIRouter(prefix="/preferences", tags=["preferences"])


@router.get("/{user_id}", response_model=PreferenceProfilePublic)
async def get_preferences(user_id: str):
    doc = await preferences_col().find_one({"user_id": user_id})
    if not doc:
        raise HTTPException(
            status_code=404, detail=f"No preference profile for user {user_id}")
    return PreferenceProfilePublic.from_doc(doc)


@router.put("/{user_id}", response_model=PreferenceProfilePublic)
async def upsert_preferences(user_id: str, body: PreferenceProfileUpsert):
    col = preferences_col()
    existing = await col.find_one({"user_id": user_id})
    if existing:
        await col.update_one({"_id": existing["_id"]}, {"$set": body.model_dump()})
        doc = await col.find_one({"_id": existing["_id"]})
    else:
        doc = {
            "_id": str(uuid.uuid4()),
            "user_id": user_id,
            "is_template": False,
            "template_name": None,
            **body.model_dump(),
        }
        await col.insert_one(doc)
    return PreferenceProfilePublic.from_doc(doc)


@router.post("/extract", response_model=PreferenceProfilePublic)
async def extract_preferences(
    design_id: str = Body(..., embed=True),
    user_id: str = Body(..., embed=True),
):
    design_doc = await designs_col().find_one({"_id": design_id, "deleted_at": None})
    if not design_doc:
        raise HTTPException(
            status_code=404, detail=f"Design {design_id} not found")

    design_doc_copy = dict(design_doc)
    design_doc_copy["id"] = design_doc_copy.pop("_id")
    design = Design.model_validate(design_doc_copy)

    extracted = await extract_from_design(design)
    if not extracted:
        raise HTTPException(
            status_code=422, detail="No placed items to extract preferences from")

    col = preferences_col()
    existing = await col.find_one({"user_id": user_id})

    if existing:
        await col.update_one({"_id": existing["_id"]}, {"$set": extracted})
        doc = await col.find_one({"_id": existing["_id"]})
    else:
        doc = {
            "_id": str(uuid.uuid4()),
            "user_id": user_id,
            "is_template": False,
            "template_name": None,
            "style_tags": extracted.get("style_tags", []),
            "color_palette": extracted.get("color_palette", []),
            "material_preferences": extracted.get("material_preferences", []),
            "spatial_density": "balanced",
            "philosophies": [],
            "hard_requirements": {},
            # "taste_vector": extracted.get("taste_vector"),
        }
        await col.insert_one(doc)

    return PreferenceProfilePublic.from_doc(doc)
