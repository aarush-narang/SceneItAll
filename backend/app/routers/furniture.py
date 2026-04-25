from __future__ import annotations
from fastapi import APIRouter, HTTPException, Query
from ..db import furniture_col
from ..models.furniture import FurnitureItemPublic
from ..services.embeddings import embed_text

router = APIRouter(prefix="/furniture", tags=["furniture"])


@router.get("/search", response_model=list[FurnitureItemPublic])
async def search_furniture(
    q: str = Query(..., description="Free-text search query"),
    category: str | None = Query(None),
    max_price: float | None = Query(None),
    limit: int = Query(10, ge=1, le=100),
):
    text_vec = embed_text(q)
    pipeline = [
        {
            "$vectorSearch": {
                "index": "text_index",
                "path": "text_embedding",
                "queryVector": text_vec,
                "numCandidates": limit * 10,
                "limit": limit * 4,
            }
        }
    ]

    match: dict = {}
    if category:
        match["taxonomy_inferred.category"] = category
    if max_price is not None:
        match["price.value"] = {"$lte": max_price}
    if match:
        pipeline.append({"$match": match})

    pipeline.append({"$limit": limit})
    pipeline.append({"$project": {"visual_embedding": 0, "text_embedding": 0}})

    col = furniture_col()
    docs = await col.aggregate(pipeline).to_list(length=limit)
    return [FurnitureItemPublic.from_doc(d) for d in docs]


@router.get("/similar", response_model=list[FurnitureItemPublic])
async def similar_furniture(
    id: str = Query(...),
    max_price: float | None = Query(None),
    limit: int = Query(10, ge=1, le=100),
):
    col = furniture_col()
    source = await col.find_one({"_id": id})
    if not source:
        raise HTTPException(status_code=404, detail=f"Item {id} not found")

    visual_vec = source.get("visual_embedding")
    if not visual_vec:
        raise HTTPException(status_code=422, detail="Item has no visual embedding")

    pipeline = [
        {
            "$vectorSearch": {
                "index": "visual_index",
                "path": "visual_embedding",
                "queryVector": visual_vec,
                "numCandidates": (limit + 1) * 10,
                "limit": (limit + 1) * 4,
            }
        },
        {"$match": {"_id": {"$ne": id}}},
    ]
    if max_price is not None:
        pipeline.append({"$match": {"price.value": {"$lte": max_price}}})
    pipeline.append({"$limit": limit})
    pipeline.append({"$project": {"visual_embedding": 0, "text_embedding": 0}})

    docs = await col.aggregate(pipeline).to_list(length=limit)
    return [FurnitureItemPublic.from_doc(d) for d in docs]


@router.get("/{id}", response_model=FurnitureItemPublic)
async def get_furniture(id: str):
    col = furniture_col()
    doc = await col.find_one({"_id": id}, {"visual_embedding": 0, "text_embedding": 0})
    if not doc:
        raise HTTPException(status_code=404, detail=f"Item {id} not found")
    return FurnitureItemPublic.from_doc(doc)
