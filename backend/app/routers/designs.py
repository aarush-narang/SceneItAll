from __future__ import annotations
import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, HTTPException, Query
from ..db import designs_col, furniture_col
from ..models.design import Design, DesignPublic, DesignCreateRequest, DesignPatchRequest, PlacedItem

router = APIRouter(prefix="/designs", tags=["designs"])


def _point_in_polygon(px: float, pz: float, polygon: list) -> bool:
    n = len(polygon)
    inside = False
    j = n - 1
    for i in range(n):
        xi, zi = polygon[i]["x"], polygon[i]["z"]
        xj, zj = polygon[j]["x"], polygon[j]["z"]
        if ((zi > pz) != (zj > pz)) and (px < (xj - xi) * (pz - zi) / (zj - zi + 1e-12) + xi):
            inside = not inside
        j = i
    return inside


async def _validate_placed_item(item: PlacedItem, design_doc: dict) -> None:
    item_doc = await furniture_col().find_one({"_id": item.item_id})
    if not item_doc:
        raise HTTPException(status_code=422, detail=f"Furniture item {item.item_id} not found")

    floor_polygon = design_doc["shell"]["floor_polygon"]
    if not _point_in_polygon(item.position.x, item.position.z, floor_polygon):
        raise HTTPException(
            status_code=422,
            detail=f"Position ({item.position.x}, {item.position.z}) is outside the room floor polygon",
        )

    bbox_max_y = design_doc["shell"]["bbox_max"]["y"]
    item_h = item_doc["dimensions"]["height_m"]
    if item.position.y + item_h > bbox_max_y:
        raise HTTPException(
            status_code=422,
            detail=f"Item height {item_h}m at y={item.position.y} exceeds ceiling at y={bbox_max_y}",
        )


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
