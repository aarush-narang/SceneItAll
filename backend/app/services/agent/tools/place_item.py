"""Place a new furniture instance in the design after validation."""

from datetime import datetime, timezone
from uuid import uuid4

from pydantic import BaseModel, Field

from ....db import designs_col, furniture_col
from ....models.design import (
    FurnitureBoundingBox,
    FurnitureFiles,
    FurnitureSnapshot,
    PlacedObject,
    Placement,
)
from ....services.placement import validate_placement
from ..context import AgentContext
from ..registry import register


class PlaceItemInput(BaseModel):
    catalog_id: str = Field(
        description="Furniture item id (from search_catalog results)."
    )
    position: tuple[float, float, float] = Field(
        description="Placement (x, y, z) in meters, room-local. y is the item's base."
    )
    euler_angles: tuple[float, float, float] = Field(
        default=(0.0, 0.0, 0.0),
        description=(
            "Rotation as (pitch, yaw, roll) in radians. Pitch and roll must be "
            "near 0 (item upright); only yaw should differ."
        ),
    )
    rationale: str = Field(
        description="One short sentence explaining why this item belongs here."
    )


class PlaceItemOutput(BaseModel):
    instance_id: str
    placed: PlacedObject


@register(
    name="place_item",
    description=(
        "Place a new piece of furniture in the design. Looks up the catalog "
        "item, runs the placement validator (orientation, footprint inside "
        "floor polygon, fits under ceiling, no collision with existing items, "
        "doesn't block any door/opening clearance zone), and persists on "
        "success. Returns the new PlacedObject with its instance id."
    ),
    input=PlaceItemInput,
    output=PlaceItemOutput,
    mutates=True,
    tier=1,
)
async def place_item(ctx: AgentContext, inp: PlaceItemInput) -> PlaceItemOutput:
    item_doc = await furniture_col().find_one({"_id": inp.catalog_id})
    if not item_doc:
        raise ValueError(f"catalog item {inp.catalog_id} not found")

    bbox = item_doc.get("dimensions_bbox") or {}
    if not bbox:
        raise ValueError(f"catalog item {inp.catalog_id} has no dimensions_bbox")
    files = item_doc.get("files") or {}

    snapshot = FurnitureSnapshot(
        id=inp.catalog_id,
        name=item_doc.get("name", ""),
        family_key=item_doc.get("family_key"),
        dimensions_bbox=FurnitureBoundingBox(**bbox),
        files=FurnitureFiles(usdz_url=files.get("usdz_url", "")),
    )

    placed = PlacedObject(
        id=str(uuid4()),
        furniture=snapshot,
        placement=Placement(
            position=inp.position,
            euler_angles=inp.euler_angles,
        ),
        added_at=datetime.now(timezone.utc),
        placed_by="agent",
        rationale=inp.rationale,
    )

    design = await ctx.load_design()
    is_valid, err = await validate_placement(placed, design)
    if not is_valid:
        raise ValueError(err)

    await designs_col().update_one(
        {"_id": ctx.design_id},
        {
            "$push": {"objects": placed.model_dump()},
            "$set": {"updated_at": datetime.now(timezone.utc)},
        },
    )
    ctx.invalidate_design()
    return PlaceItemOutput(instance_id=placed.id, placed=placed)
