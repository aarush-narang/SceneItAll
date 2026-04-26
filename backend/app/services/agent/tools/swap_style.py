"""Replace each placed item's catalog snapshot with a visually similar item
that matches a target style. Position and rotation are preserved."""

from datetime import datetime, timezone
from typing import Any

from pydantic import BaseModel, Field

from ....db import designs_col, furniture_col
from ....models.design import PlacedObject
from ....services.placement import validate_placement
from ..context import AgentContext
from ..registry import register


class SwapStyleInput(BaseModel):
    target_style: str = Field(
        description=(
            "Style tag to swap towards (e.g. 'modern', 'mid-century', 'industrial'). "
            "Replacements must include this in their attributes.style_tags."
        )
    )
    instance_ids: list[str] = Field(
        default_factory=list,
        description=(
            "Optional subset of objects.id to swap. Empty = swap every "
            "placed item in the design."
        ),
    )


class SwapStyleOutput(BaseModel):
    swapped: list[PlacedObject] = Field(default_factory=list)
    skipped: list[str] = Field(default_factory=list)


async def _find_replacement(
    source_doc: dict[str, Any], target_style: str
) -> dict[str, Any] | None:
    visual_vec = (
        (source_doc.get("embeddings") or {}).get("visual") or {}
    ).get("vec")
    if not visual_vec:
        return None
    category = (source_doc.get("taxonomy_inferred") or {}).get("category")

    match: dict[str, Any] = {
        "_id": {"$ne": source_doc["_id"]},
        "attributes.style_tags": {"$in": [target_style]},
    }
    if category:
        match["taxonomy_inferred.category"] = category

    pipeline = [
        {
            "$vectorSearch": {
                "index": "text_embedding",
                "path": "embeddings.visual.vec",
                "queryVector": visual_vec,
                "numCandidates": 200,
                "limit": 50,
            }
        },
        {"$match": match},
        {"$limit": 1},
    ]
    candidates = await furniture_col().aggregate(pipeline).to_list(length=1)
    return candidates[0] if candidates else None


@register(
    name="swap_style",
    description=(
        "For every placed item (or a subset by `instance_ids`), find a visually "
        "similar catalog item that carries `target_style` and replace the "
        "snapshot in-place. Placement (position/rotation) is preserved. The "
        "new size is revalidated against the room and other items; items that "
        "would no longer fit are skipped and reported."
    ),
    input=SwapStyleInput,
    output=SwapStyleOutput,
    mutates=True,
    tier=3,
)
async def swap_style(ctx: AgentContext, inp: SwapStyleInput) -> SwapStyleOutput:
    design = await ctx.load_design()
    placed = design.get("objects", []) or []
    targets = (
        set(inp.instance_ids) if inp.instance_ids else {p["id"] for p in placed}
    )

    swapped: list[PlacedObject] = []
    skipped: list[str] = []

    for item in placed:
        if item["id"] not in targets:
            continue
        cat_id = (item.get("furniture") or {}).get("id")
        if not cat_id:
            skipped.append(item["id"])
            continue

        source = await furniture_col().find_one({"_id": cat_id})
        if not source:
            skipped.append(item["id"])
            continue

        replacement = await _find_replacement(source, inp.target_style)
        if not replacement:
            skipped.append(item["id"])
            continue

        new_bbox = replacement.get("dimensions_bbox") or {}
        if not new_bbox:
            skipped.append(item["id"])
            continue

        new_snapshot = {
            "id": replacement["_id"],
            "name": replacement.get("name", ""),
            "family_key": replacement.get("family_key"),
            "dimensions_bbox": new_bbox,
            "files": {
                "usdz_url": (replacement.get("files") or {}).get("usdz_url", "")
            },
        }
        updated = PlacedObject.model_validate({
            **item,
            "furniture": new_snapshot,
            "placed_by": "agent",
            "rationale": f"Style-swapped to {inp.target_style}",
        })

        is_valid, _ = await validate_placement(updated, design)
        if not is_valid:
            skipped.append(item["id"])
            continue

        await designs_col().update_one(
            {"_id": ctx.design_id, "objects.id": item["id"]},
            {
                "$set": {
                    "objects.$.furniture": new_snapshot,
                    "objects.$.placed_by": "agent",
                    "objects.$.rationale": f"Style-swapped to {inp.target_style}",
                    "updated_at": datetime.now(timezone.utc),
                }
            },
        )
        swapped.append(updated)

    if swapped:
        ctx.invalidate_design()
    return SwapStyleOutput(swapped=swapped, skipped=skipped)
