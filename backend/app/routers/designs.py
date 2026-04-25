from __future__ import annotations
import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, HTTPException, Query
from ..db import designs_col, furniture_col
from ..models.design import Design, DesignPublic, DesignCreateRequest, DesignPatchRequest, PlacedItem
from ..utils.geometry import point_in_polygon, check_item_fits_in_room

router = APIRouter(prefix="/designs", tags=["designs"])


async def _validate_placed_item(item: PlacedItem, design_doc: dict) -> None:
    item_doc = await furniture_col().find_one({"_id": item.item_id})
    if not item_doc:
        raise HTTPException(status_code=422, detail=f"Furniture item {item.item_id} not found")

    floor_polygon = design_doc["shell"]["floor_polygon"]
    bbox_max = design_doc["shell"]["bbox_max"]

    is_valid, error_msg = check_item_fits_in_room(
        position={"x": item.position.x, "y": item.position.y, "z": item.position.z},
        dimensions=item_doc["dimensions"],
        floor_polygon=floor_polygon,
        bbox_max=bbox_max,
    )
    if not is_valid:
        raise HTTPException(status_code=422, detail=error_msg)


@router.get("", response_model=list[DesignPublic])
async def list_designs(user_id: str = Query(...)):
    col = designs_col()
    docs = await col.find({"user_id": user_id, "deleted_at": None}).to_list(length=None)
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
        "placed_items": [],
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

    update_set: dict = {"updated_at": datetime.now(timezone.utc)}
    if body.name is not None:
        update_set["name"] = body.name
    if body.preference_profile_id is not None:
        update_set["preference_profile_id"] = body.preference_profile_id

    for item in body.add_items:
        if not item.instance_id:
            item = item.model_copy(update={"instance_id": str(uuid.uuid4())})
        await _validate_placed_item(item, doc)

    for item in body.update_items:
        await _validate_placed_item(item, doc)

    ops: dict = {"$set": update_set}
    if body.add_items:
        ops["$push"] = {"placed_items": {"$each": [i.model_dump() for i in body.add_items]}}

    await col.update_one({"_id": id}, ops)

    if body.delete_instance_ids:
        await col.update_one(
            {"_id": id},
            {"$pull": {"placed_items": {"instance_id": {"$in": body.delete_instance_ids}}}},
        )

    if body.update_items:
        for item in body.update_items:
            await col.update_one(
                {"_id": id, "placed_items.instance_id": item.instance_id},
                {"$set": {"placed_items.$": item.model_dump()}},
            )

    updated = await col.find_one({"_id": id})
    return DesignPublic.from_doc(updated)


@router.delete("/{id}", status_code=204)
async def delete_design(id: str):
    col = designs_col()
    result = await col.update_one(
        {"_id": id, "deleted_at": None},
        {"$set": {"deleted_at": datetime.now(timezone.utc), "updated_at": datetime.now(timezone.utc)}},
    )
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail=f"Design {id} not found")