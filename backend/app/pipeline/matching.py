"""Vector search + dimension-aware re-ranking against the IKEA catalog.

Per object: run an Atlas `$vectorSearch` against the visual-embedding index,
pre-filtered to plausible candidates, then re-rank the top K with a combined
score that mixes CLIP similarity and dimensional fit. Returns the ranked list
and the top-1 match.

The visual index name (`VISUAL_INDEX_NAME`) is the open question flagged in the
plan — `scripts/create_indexes.py` defines `visual_index`, but the existing
`furniture.py` router uses `text_embedding` for the visual path. Update this
constant once the deployed Atlas configuration is confirmed.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

VISUAL_INDEX_NAME = "text_embedding"  # confirmed: single Atlas index covers both text + visual paths
VISUAL_PATH = "embeddings.visual.vec"

DEFAULT_TOP_K = 20
W_CLIP = 0.7
W_DIM = 0.3


@dataclass(frozen=True)
class Candidate:
    """One ranked match returned to the decision step."""

    product_id: str
    name: str
    category: str
    subcategory: str | None
    dims: tuple[float, float, float]
    usdz_url: str | None
    clip_score: float
    dim_fit_score: float
    combined_score: float


def _dim_fit_score(detected: tuple[float, float, float], cand: tuple[float, float, float]) -> float:
    """1 minus mean per-axis relative error, clamped to [0, 1]."""
    axes = []
    for det, c in zip(detected, cand):
        if det <= 0:
            continue
        axes.append(abs(c - det) / det)
    if not axes:
        return 0.0
    return float(np.clip(1.0 - sum(axes) / len(axes), 0.0, 1.0))


async def vector_search(
    query_vec: np.ndarray,
    candidate_filter: dict,
    top_k: int = DEFAULT_TOP_K,
) -> list[dict]:
    """Run a vector search then post-filter with `$match`.

    Atlas's `$vectorSearch.filter` requires the filtered fields to be declared
    as `type: "filter"` in the index definition — currently they aren't. Doing
    `$match` after is functionally equivalent (filter applies to results), at
    the cost of widening `numCandidates` so enough survive the filter."""
    from ..db import furniture_col  # lazy: keep matching importable without motor
    col = furniture_col()
    pipeline: list[dict] = [
        {
            "$vectorSearch": {
                "index": VISUAL_INDEX_NAME,
                "path": VISUAL_PATH,
                "queryVector": query_vec.tolist(),
                "numCandidates": max(top_k * 50, 500),
                "limit": max(top_k * 10, 200),
            }
        },
        {"$match": candidate_filter},
        {"$limit": top_k},
        {
            "$project": {
                "_id": 1,
                "name": 1,
                "taxonomy_inferred": 1,
                "dimensions_bbox": 1,
                "files.usdz_url": 1,
                "clip_score": {"$meta": "vectorSearchScore"},
            }
        },
    ]
    return await col.aggregate(pipeline).to_list(length=top_k)


def rank_candidates(
    detected_dims: tuple[float, float, float],
    raw_docs: list[dict],
) -> list[Candidate]:
    """Combine CLIP similarity with dimension fit, sort descending."""
    out: list[Candidate] = []
    for doc in raw_docs:
        bbox = doc.get("dimensions_bbox") or {}
        dims = (
            float(bbox.get("width_m", 0.0)),
            float(bbox.get("height_m", 0.0)),
            float(bbox.get("depth_m", 0.0)),
        )
        clip_score = float(doc.get("clip_score") or 0.0)
        dim_fit = _dim_fit_score(detected_dims, dims) if all(d > 0 for d in dims) else 0.0
        combined = W_CLIP * clip_score + W_DIM * dim_fit

        taxonomy = doc.get("taxonomy_inferred") or {}
        files = doc.get("files") or {}
        out.append(
            Candidate(
                product_id=str(doc.get("_id")),
                name=doc.get("name") or "",
                category=str(taxonomy.get("category") or ""),
                subcategory=taxonomy.get("subcategory"),
                dims=dims,
                usdz_url=files.get("usdz_url"),
                clip_score=clip_score,
                dim_fit_score=dim_fit,
                combined_score=combined,
            )
        )
    out.sort(key=lambda c: c.combined_score, reverse=True)
    return out


async def search_and_rank(
    query_vec: np.ndarray,
    detected_dims: tuple[float, float, float],
    candidate_filter: dict,
    top_k: int = DEFAULT_TOP_K,
) -> list[Candidate]:
    """End-to-end matching for one object: search + rank."""
    raw = await vector_search(query_vec, candidate_filter, top_k=top_k)
    return rank_candidates(detected_dims, raw)
