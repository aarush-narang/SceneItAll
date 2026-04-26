"""Replace placed items above a price ceiling with cheaper, visually similar
alternatives. Position and rotation are preserved."""

from datetime import datetime, timezone
from typing import Any

from pydantic import BaseModel, Field

from ....db import designs_col, furniture_col
from ....models.design import PlacedObject
from ....services.placement import validate_placement
from ..context import AgentContext
from ..registry import register


class BalanceBudgetInput(BaseModel):
    max_price_per_item: float = Field(
        gt=0,
        description="Max price per item in catalog currency. Items already at or below this stay put.",
    )
    instance_ids: list[str] = Field(
        default_factory=list,
        description=(
            "Optional subset of objects.id to consider. Empty = consider "
            "every placed item that's currently over the cap."
        ),
    )


class BalanceBudgetOutput(BaseModel):
    swapped: list[PlacedObject] = Field(default_factory=list)
    skipped: list[str] = Field(default_factory=list)
    untouched: list[str] = Field(default_factory=list)


async def _cheaper_visual_match(
    source_doc: dict[str, Any], max_price: float
) -> dict[str, Any] | None:
    visual_vec = (
        (source_doc.get("embeddings") or {}).get("visual") or {}
    ).get("vec")
    if not visual_vec:
        return None
    category = (source_doc.get("taxonomy_inferred") or {}).get("category")

    match: dict[str, Any] = {
        "_id": {"$ne": source_doc["_id"]},
        "price.value": {"$lte": max_price},
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
                "limit": 30,
            }
        },
        {"$match": match},
        {"$sort": {"price.value": 1}},
        {"$limit": 1},
    ]
    candidates = await furniture_col().aggregate(pipeline).to_list(length=1)
    return candidates[0] if candidates else None


@register(
    name="balance_budget",
    description=(
        "Replace any placed item whose catalog price exceeds `max_price_per_item` "
        "with the cheapest visually similar catalog item that fits the budget "
        "(same category, similar visual embedding). Placement is preserved; "
        "items whose replacement would no longer fit the room are skipped and "
        "reported."
    ),
    input=BalanceBudgetInput,
    output=BalanceBudgetOutput,
    mutates=True,
    tier=3,
)
async def balance_budget(
    ctx: AgentContext, inp: BalanceBudgetInput
) -> BalanceBudgetOutput:
    design = await ctx.load_design()
    placed = design.get("objects", []) or []
    candidates = (
        set(inp.instance_ids) if inp.instance_ids else {p["id"] for p in placed}
    )

    swapped: list[PlacedObject] = []
    skipped: list[str] = []
    untouched: list[str] = []

    for item in placed:
        if item["id"] not in candidates:
            continue
        cat_id = (item.get("furniture") or {}).get("id")
        if not cat_id:
            skipped.append(item["id"])
            continue

        source = await furniture_col().find_one({"_id": cat_id})
        if not source:
            skipped.append(item["id"])
            continue
        current_price = (source.get("price") or {}).get("value")
        if current_price is not None and current_price <= inp.max_price_per_item:
            untouched.append(item["id"])
            continue

        replacement = await _cheaper_visual_match(source, inp.max_price_per_item)
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
            "rationale": f"Budget swap (≤{inp.max_price_per_item})",
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
                    "objects.$.rationale": f"Budget swap (≤{inp.max_price_per_item})",
                    "updated_at": datetime.now(timezone.utc),
                }
            },
        )
        swapped.append(updated)

    if swapped:
        ctx.invalidate_design()
    return BalanceBudgetOutput(
        swapped=swapped, skipped=skipped, untouched=untouched
    )
