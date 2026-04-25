"""Move or rotate an existing placed furniture instance."""

from datetime import datetime, timezone

from pydantic import BaseModel, Field

from ....db import designs_col
from ....models.design import PlacedObject
from ....services.placement import validate_placement
from ..context import AgentContext
from ..registry import register


class MoveItemInput(BaseModel):
    instance_id: str = Field(
        description="The PlacedObject.id (instance UUID) of the item to move."
    )
    position: tuple[float, float, float] | None = Field(
        default=None,
        description="New (x, y, z) in meters. Omit to keep the current position.",
    )
    euler_angles: tuple[float, float, float] | None = Field(
        default=None,
        description="New (pitch, yaw, roll) in radians. Omit to keep current rotation.",
    )


class MoveItemOutput(BaseModel):
    instance_id: str
    placed: PlacedObject


@register(
    name="move_item",
    description=(
        "Move or rotate an existing placed item. Provide `instance_id` and the "
        "new `position` and/or `euler_angles`. The validator runs against the "
        "new pose (excluding the item itself from collision checks)."
    ),
    input=MoveItemInput,
    output=MoveItemOutput,
    mutates=True,
    tier=1,
)
async def move_item(ctx: AgentContext, inp: MoveItemInput) -> MoveItemOutput:
    if inp.position is None and inp.euler_angles is None:
        raise ValueError("provide at least one of 'position' or 'euler_angles'")

    design = await ctx.load_design()
    existing = next(
        (p for p in design.get("placed_items", []) if p.get("id") == inp.instance_id),
        None,
    )
    if existing is None:
        raise ValueError(f"placed item {inp.instance_id} not found in design")

    updated = PlacedObject.model_validate(existing)
    if inp.position is not None:
        updated.placement.position = inp.position
    if inp.euler_angles is not None:
        updated.placement.euler_angles = inp.euler_angles

    is_valid, err = await validate_placement(updated, design)
    if not is_valid:
        raise ValueError(err)

    await designs_col().update_one(
        {"_id": ctx.design_id, "placed_items.id": inp.instance_id},
        {
            "$set": {
                "placed_items.$": updated.model_dump(),
                "updated_at": datetime.now(timezone.utc),
            }
        },
    )
    ctx.invalidate_design()
    return MoveItemOutput(instance_id=updated.id, placed=updated)
