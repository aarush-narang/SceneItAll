import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query

from ..db import designs_col, furniture_col
from ..models.design import (
    DesignCreateRequest,
    DesignPatchRequest,
    DesignPublic,
    PlacedObject,
)
from ..utils.geometry import PlacementBox, check_item_placement, derive_floor_y

router = APIRouter(prefix="/designs", tags=["designs"])


def _placement_box_from_model(item: PlacedObject) -> PlacementBox:
    bbox = item.furniture.dimensions_bbox
    return PlacementBox(
        position=tuple(item.placement.position),
        euler_angles=tuple(item.placement.euler_angles),
        width_m=bbox.width_m,
        height_m=bbox.height_m,
        depth_m=bbox.depth_m,
    )


def _placement_box_from_doc(doc: dict) -> PlacementBox | None:
    placement = doc.get("placement") or {}
    bbox = (doc.get("furniture") or {}).get("dimensions_bbox") or {}
    pos = placement.get("position")
    if not pos or not bbox:
        return None
    return PlacementBox(
        position=tuple(pos),
        euler_angles=tuple(placement.get("euler_angles", (0.0, 0.0, 0.0))),
        width_m=bbox["width_m"],
        height_m=bbox["height_m"],
        depth_m=bbox["depth_m"],
    )


async def _validate_placed_object(item: PlacedObject, design_doc: dict) -> None:
    catalog_id = item.furniture.id
    if not await furniture_col().count_documents({"_id": catalog_id}, limit=1):
        raise HTTPException(status_code=422, detail=f"Furniture item {catalog_id} not found")

    shell = design_doc["shell"]
    room = shell["room"]
    floor_y = derive_floor_y(shell.get("walls") or [])

    others: list[PlacementBox] = []
    for o in design_doc.get("placed_items", []):
        if o.get("id") == item.id:
            continue
        box = _placement_box_from_doc(o)
        if box is not None:
            others.append(box)

    is_valid, error_msg = check_item_placement(
        _placement_box_from_model(item),
        floor_polygon=room["floor_polygon"],
        ceiling_height=room["ceiling_height"],
        floor_y=floor_y,
        other_items=others,
    )
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
        "placed_items": [item.model_dump() for item in body.placed_items],
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
            "placed_items": {"$each": [i.model_dump() for i in body.add_items]}
        }
    await col.update_one({"_id": id}, ops)

    if body.delete_instance_ids:
        await col.update_one(
            {"_id": id},
            {"$pull": {"placed_items": {"id": {"$in": body.delete_instance_ids}}}},
        )

    for item in body.update_items:
        await col.update_one(
            {"_id": id, "placed_items.id": item.id},
            {"$set": {"placed_items.$": item.model_dump()}},
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
