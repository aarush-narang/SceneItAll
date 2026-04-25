"""Dry-run placement validation. Lets the agent ask 'would this fit?' without
writing to the database."""

from datetime import datetime, timezone
from uuid import uuid4

from pydantic import BaseModel, Field

from ....db import furniture_col
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


class CheckConstraintsInput(BaseModel):
    catalog_id: str = Field(description="Catalog item to test.")
    position: tuple[float, float, float] = Field(description="Hypothetical (x, y, z) in meters.")
    euler_angles: tuple[float, float, float] = Field(
        default=(0.0, 0.0, 0.0),
        description="Hypothetical (pitch, yaw, roll) in radians.",
    )


class CheckConstraintsOutput(BaseModel):
    ok: bool
    reason: str | None = None


@register(
    name="check_constraints",
    description=(
        "Test whether placing a given catalog item at a given pose would pass "
        "validation, WITHOUT actually placing it. Returns `ok=true` if all "
        "constraints (footprint inside floor, fits under ceiling, upright, no "
        "collision, doesn't block doors/openings) are satisfied; otherwise "
        "`ok=false` with a `reason`. Use this to plan placements before "
        "calling `place_item`."
    ),
    input=CheckConstraintsInput,
    output=CheckConstraintsOutput,
    mutates=False,
    tier=2,
)
async def check_constraints(
    ctx: AgentContext, inp: CheckConstraintsInput
) -> CheckConstraintsOutput:
    item_doc = await furniture_col().find_one({"_id": inp.catalog_id})
    if not item_doc:
        return CheckConstraintsOutput(
            ok=False, reason=f"catalog item {inp.catalog_id} not found"
        )
    bbox = item_doc.get("dimensions_bbox") or {}
    if not bbox:
        return CheckConstraintsOutput(
            ok=False, reason=f"catalog item {inp.catalog_id} has no dimensions_bbox"
        )

    candidate = PlacedObject(
        id=str(uuid4()),
        furniture=FurnitureSnapshot(
            id=inp.catalog_id,
            name=item_doc.get("name", ""),
            family_key=item_doc.get("family_key"),
            dimensions_bbox=FurnitureBoundingBox(**bbox),
            files=FurnitureFiles(usdz_url=(item_doc.get("files") or {}).get("usdz_url", "")),
        ),
        placement=Placement(position=inp.position, euler_angles=inp.euler_angles),
        added_at=datetime.now(timezone.utc),
        placed_by="agent",
        rationale=None,
    )
    design = await ctx.load_design()
    ok, reason = await validate_placement(candidate, design)
    return CheckConstraintsOutput(ok=ok, reason=None if ok else reason)
