"""Search the furniture catalog by free-text intent or visual similarity."""

from typing import Any

from pydantic import BaseModel, Field

from ....db import furniture_col
from ....services.embeddings import embed_text_gemini
from ..context import AgentContext
from ..registry import register


class FurnitureSummary(BaseModel):
    id: str
    name: str
    category: str | None = None
    price: float | None = None
    currency: str | None = None
    width_m: float | None = None
    height_m: float | None = None
    depth_m: float | None = None
    style_tags: list[str] = Field(default_factory=list)
    color_primary: str | None = None
    material_primary: str | None = None
    room_role: str | None = None
    placement_hints: list[str] = Field(default_factory=list)
    pairs_well_with: list[str] = Field(default_factory=list)
    design_summary: str | None = None
    usdz_url: str | None = None
    score: float | None = None


class SearchCatalogInput(BaseModel):
    query: str = Field(
        default="",
        description=(
            "Free-text design intent (e.g. 'small white reading chair'). "
            "Required unless `similar_to_item_id` is provided."
        ),
    )
    category: str | None = Field(
        default=None,
        description="Filter by `taxonomy_inferred.category` (e.g. 'sofa', 'chair', 'table').",
    )
    max_price: float | None = Field(
        default=None, description="Max price in the catalog currency."
    )
    style_tags: list[str] = Field(
        default_factory=list,
        description="Restrict to items whose attributes.style_tags overlap any of these.",
    )
    similar_to_item_id: str | None = Field(
        default=None,
        description=(
            "If set, search by visual similarity to this catalog item rather than by "
            "the text query. Use to find substitutes / alternatives."
        ),
    )
    limit: int = Field(default=8, ge=1, le=30)


class SearchCatalogOutput(BaseModel):
    results: list[FurnitureSummary]


def _summarise(doc: dict[str, Any], score: float | None = None) -> FurnitureSummary:
    bbox = doc.get("dimensions_bbox") or {}
    price = doc.get("price") or {}
    attrs = doc.get("attributes") or {}
    files = doc.get("files") or {}
    taxonomy = doc.get("taxonomy_inferred") or {}
    return FurnitureSummary(
        id=str(doc.get("_id") or doc.get("id") or ""),
        name=doc.get("name", ""),
        category=taxonomy.get("category"),
        price=price.get("value"),
        currency=price.get("currency"),
        width_m=bbox.get("width_m"),
        height_m=bbox.get("height_m"),
        depth_m=bbox.get("depth_m"),
        style_tags=attrs.get("style_tags", []) or [],
        color_primary=attrs.get("color_primary"),
        material_primary=attrs.get("material_primary"),
        room_role=attrs.get("room_role"),
        placement_hints=attrs.get("placement_hints", []) or [],
        pairs_well_with=attrs.get("pairs_well_with", []) or [],
        design_summary=doc.get("design_summary"),
        usdz_url=files.get("usdz_url"),
        score=score if score is not None else doc.get("score"),
    )


def _build_filter_match(inp: SearchCatalogInput) -> dict[str, Any]:
    match: dict[str, Any] = {}
    if inp.category:
        match["taxonomy_inferred.category"] = inp.category
    if inp.max_price is not None:
        match["price.value"] = {"$lte": inp.max_price}
    if inp.style_tags:
        match["attributes.style_tags"] = {"$in": inp.style_tags}
    return match


@register(
    name="search_catalog",
    description=(
        "Search the furniture catalog. Use free-text `query` for design intent "
        "(\"small white reading chair\", \"warm-toned wooden side table\"), or "
        "`similar_to_item_id` to find visual alternatives to an existing item. "
        "Optional filters narrow by category, max_price, and style_tags. Returns "
        "FurnitureSummary objects with dimensions, semantic attributes, and a "
        "similarity score."
    ),
    input=SearchCatalogInput,
    output=SearchCatalogOutput,
    mutates=False,
    tier=1,
)
async def search_catalog(ctx: AgentContext, inp: SearchCatalogInput) -> SearchCatalogOutput:
    if not inp.query and not inp.similar_to_item_id:
        raise ValueError("provide either 'query' or 'similar_to_item_id'")

    col = furniture_col()
    pipeline: list[dict[str, Any]] = []

    if inp.similar_to_item_id:
        source = await col.find_one(
            {"_id": inp.similar_to_item_id},
            {"embeddings.visual.vec": 1},
        )
        if not source:
            raise ValueError(f"source item {inp.similar_to_item_id} not found")
        visual_vec = (
            (source.get("embeddings") or {}).get("visual") or {}
        ).get("vec")
        if not visual_vec:
            raise ValueError(
                f"source item {inp.similar_to_item_id} has no visual embedding"
            )
        pipeline.append({
            "$vectorSearch": {
                "index": "text_embedding",
                "path": "embeddings.visual.vec",
                "queryVector": visual_vec,
                "numCandidates": (inp.limit + 1) * 10,
                "limit": (inp.limit + 1) * 4,
            }
        })
        pipeline.append({"$match": {"_id": {"$ne": inp.similar_to_item_id}}})
    else:
        text_vec = embed_text_gemini(inp.query)
        pipeline.append({
            "$vectorSearch": {
                "index": "text_embedding",
                "path": "embeddings.text.vec",
                "queryVector": text_vec,
                "numCandidates": inp.limit * 10,
                "limit": inp.limit * 4,
            }
        })

    filter_match = _build_filter_match(inp)
    if filter_match:
        pipeline.append({"$match": filter_match})

    pipeline.append({"$limit": inp.limit})
    pipeline.append({
        "$project": {"embeddings": 0, "score": {"$meta": "vectorSearchScore"}}
    })

    docs = await col.aggregate(pipeline).to_list(length=inp.limit)
    return SearchCatalogOutput(
        results=[_summarise(d, score=d.get("score")) for d in docs]
    )
