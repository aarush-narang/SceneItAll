import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query

from ..db import designs_col
from ..models.design import (
    DesignCreateRequest,
    DesignPatchRequest,
    DesignPublic,
    PlacedObject,
)
from ..services.placement import validate_placement

router = APIRouter(prefix="/designs", tags=["designs"])


async def _validate_placed_object(item: PlacedObject, design_doc: dict) -> None:
    is_valid, error_msg = await validate_placement(item, design_doc)
    if not is_valid:
        raise HTTPException(status_code=422, detail=error_msg)


@router.get("", response_model=list[DesignPublic])
async def list_designs(user_id: str = Query(...)):
    docs = await designs_col().find({"user_id": user_id, "deleted_at": None}).to_list(length=None)
    return [DesignPublic.from_doc(d) for d in docs]


@router.post("", response_model=DesignPublic, status_code=201)
async def create_design(body: DesignCreateRequest):
    now = datetime.now(timezone.utc)
    doc = {
        "_id": str(uuid.uuid4()),
        "user_id": body.user_id,
        "name": body.name,
        "preference_profile_id": body.preference_profile_id,
        "shell": body.shell.model_dump(),
        "objects": [item.model_dump() for item in body.objects],
        "created_at": now,
        "updated_at": now,
        "deleted_at": None,
    }
    await designs_col().insert_one(doc)
    return DesignPublic.from_doc(doc)


@router.get("/{id}", response_model=DesignPublic)
async def get_design(id: str):
    doc = await designs_col().find_one({"_id": id, "deleted_at": None})
    if not doc:
        raise HTTPException(status_code=404, detail=f"Design {id} not found")
    return DesignPublic.from_doc(doc)


@router.patch("/{id}", response_model=DesignPublic)
async def patch_design(id: str, body: DesignPatchRequest):
    col = designs_col()
    doc = await col.find_one({"_id": id, "deleted_at": None})
    if not doc:
        raise HTTPException(status_code=404, detail=f"Design {id} not found")

    for item in body.add_items:
        await _validate_placed_object(item, doc)
    for item in body.update_items:
        await _validate_placed_object(item, doc)

    update_set: dict = {"updated_at": datetime.now(timezone.utc)}
    if body.name is not None:
        update_set["name"] = body.name
    if body.preference_profile_id is not None:
        update_set["preference_profile_id"] = body.preference_profile_id

    ops: dict = {"$set": update_set}
    if body.add_items:
        ops["$push"] = {
            "objects": {"$each": [i.model_dump() for i in body.add_items]}
        }
    await col.update_one({"_id": id}, ops)

    if body.delete_instance_ids:
        await col.update_one(
            {"_id": id},
            {"$pull": {"objects": {"id": {"$in": body.delete_instance_ids}}}},
        )

    for item in body.update_items:
        await col.update_one(
            {"_id": id, "objects.id": item.id},
            {"$set": {"objects.$": item.model_dump()}},
        )

    updated = await col.find_one({"_id": id})
    return DesignPublic.from_doc(updated)


@router.delete("/{id}", status_code=204)
async def delete_design(id: str):
    now = datetime.now(timezone.utc)
    result = await designs_col().update_one(
        {"_id": id, "deleted_at": None},
        {"$set": {"deleted_at": now, "updated_at": now}},
    )
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail=f"Design {id} not found")
