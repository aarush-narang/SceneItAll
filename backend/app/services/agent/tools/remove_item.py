"""Remove a placed furniture instance from the design."""

from datetime import datetime, timezone

from pydantic import BaseModel, Field

from ....db import designs_col
from ..context import AgentContext
from ..registry import register


class RemoveItemInput(BaseModel):
    instance_id: str = Field(
        description="The PlacedObject.id (instance UUID) of the item to remove."
    )


class RemoveItemOutput(BaseModel):
    instance_id: str
    removed: bool


@register(
    name="remove_item",
    description=(
        "Remove a placed item from the design by its instance id (NOT its "
        "catalog id — the same SKU can exist multiple times in one room)."
    ),
    input=RemoveItemInput,
    output=RemoveItemOutput,
    mutates=True,
    tier=1,
)
async def remove_item(ctx: AgentContext, inp: RemoveItemInput) -> RemoveItemOutput:
    design = await ctx.load_design()
    if not any(p.get("id") == inp.instance_id for p in design.get("placed_items", [])):
        raise ValueError(f"placed item {inp.instance_id} not found in design")

    await designs_col().update_one(
        {"_id": ctx.design_id},
        {
            "$pull": {"placed_items": {"id": inp.instance_id}},
            "$set": {"updated_at": datetime.now(timezone.utc)},
        },
    )
    ctx.invalidate_design()
    return RemoveItemOutput(instance_id=inp.instance_id, removed=True)
