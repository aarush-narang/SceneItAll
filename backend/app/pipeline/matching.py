"""Vector search + dimension-aware re-ranking against the IKEA catalog.

Hybrid retrieval mode (`hybrid_search_and_rank`):
    1. Run two `$vectorSearch` queries in parallel against the same Atlas index:
         * visual: CLIP image embedding of the segmented crop  (path = embeddings.visual.vec)
         * text:   Gemini text embedding of a Gemini-Flash caption of the crop
                   (path = embeddings.text.vec)
    2. Merge by `_id`. A candidate that shows up on either side keeps both
       scores (missing side defaults to 0). Re-rank with weighted sum of
       visual + text + dimension fit.

The two vector searches go against the same logical index (`text_embedding`),
which the live Atlas deployment has configured with both vector paths defined.
"""
from __future__ import annotations

import asyncio
from dataclasses import dataclass

import numpy as np

VISUAL_INDEX_NAME = "text_embedding"  # confirmed: index covers both vector paths
VISUAL_PATH = "embeddings.visual.vec"
TEXT_PATH = "embeddings.text.vec"

DEFAULT_TOP_K = 20

# Retrieval mode:
#   "text"   — Gemini caption → text embedding only (prone to color/material
#              anchoring; ignores shape entirely)
#   "visual" — CLIP visual only
#   "hybrid" — text + visual + dims; best overall because CLIP shape features
#              give an independent signal from the Gemini caption
MATCH_MODE = "hybrid"

# Visual-only weights (used by `search_and_rank`, kept for backwards compat).
W_CLIP = 0.7
W_DIM = 0.3

# Hybrid weights — tune from the eval harness.
W_VISUAL = 0.4
W_TEXT = 0.4
W_DIM_HYBRID = 0.2

# Text-only weights — text similarity dominates, dim is a tiebreaker.
W_TEXT_ONLY = 0.85
W_DIM_TEXT_ONLY = 0.15


@dataclass(frozen=True)
class Candidate:
    """One ranked match returned to the decision step."""

    product_id: str
    name: str
    category: str
    subcategory: str | None
    dims: tuple[float, float, float]
    usdz_url: str | None
    clip_score: float          # visual cosine similarity
    text_score: float          # Gemini text cosine similarity (0 if hybrid not used)
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


def _project_stage() -> dict:
    """Common $project stage that emits the score under `vec_score` so we can
    rename it per-search after the fact."""
    return {
        "$project": {
            "_id": 1,
            "name": 1,
            "taxonomy_inferred": 1,
            "dimensions_bbox": 1,
            "files.usdz_url": 1,
            "vec_score": {"$meta": "vectorSearchScore"},
        }
    }


async def _vector_search(
    path: str,
    query_vec: np.ndarray,
    candidate_filter: dict,
    top_k: int,
) -> list[dict]:
    """Run one $vectorSearch against `path`, then post-filter with $match.
    Score is returned in the `vec_score` field."""
    from ..db import furniture_col  # lazy: keep matching importable without motor
    col = furniture_col()
    pipeline = [
        {
            "$vectorSearch": {
                "index": VISUAL_INDEX_NAME,
                "path": path,
                "queryVector": query_vec.tolist(),
                "numCandidates": max(top_k * 50, 500),
                "limit": max(top_k * 10, 200),
            }
        },
        {"$match": candidate_filter},
        {"$limit": top_k},
        _project_stage(),
    ]
    return await col.aggregate(pipeline).to_list(length=top_k)


async def vector_search(
    query_vec: np.ndarray,
    candidate_filter: dict,
    top_k: int = DEFAULT_TOP_K,
) -> list[dict]:
    """Visual-only search (legacy entrypoint). Returns docs with `clip_score`."""
    raw = await _vector_search(VISUAL_PATH, query_vec, candidate_filter, top_k)
    for doc in raw:
        doc["clip_score"] = doc.pop("vec_score", 0.0)
    return raw


def _build_candidate(
    doc: dict,
    detected_dims: tuple[float, float, float],
    clip_score: float,
    text_score: float,
    weights: tuple[float, float, float],
) -> Candidate:
    bbox = doc.get("dimensions_bbox") or {}
    dims = (
        float(bbox.get("width_m", 0.0)),
        float(bbox.get("height_m", 0.0)),
        float(bbox.get("depth_m", 0.0)),
    )
    dim_fit = _dim_fit_score(detected_dims, dims) if all(d > 0 for d in dims) else 0.0
    w_v, w_t, w_d = weights
    combined = w_v * clip_score + w_t * text_score + w_d * dim_fit

    taxonomy = doc.get("taxonomy_inferred") or {}
    files = doc.get("files") or {}
    return Candidate(
        product_id=str(doc.get("_id")),
        name=doc.get("name") or "",
        category=str(taxonomy.get("category") or ""),
        subcategory=taxonomy.get("subcategory"),
        dims=dims,
        usdz_url=files.get("usdz_url"),
        clip_score=clip_score,
        text_score=text_score,
        dim_fit_score=dim_fit,
        combined_score=combined,
    )


def rank_candidates(
    detected_dims: tuple[float, float, float],
    raw_docs: list[dict],
) -> list[Candidate]:
    """Visual-only ranking (legacy). Combines CLIP + dim fit."""
    out = [
        _build_candidate(
            doc, detected_dims,
            clip_score=float(doc.get("clip_score") or 0.0),
            text_score=0.0,
            weights=(W_CLIP, 0.0, W_DIM),
        )
        for doc in raw_docs
    ]
    out.sort(key=lambda c: c.combined_score, reverse=True)
    return out


async def search_and_rank(
    query_vec: np.ndarray,
    detected_dims: tuple[float, float, float],
    candidate_filter: dict,
    top_k: int = DEFAULT_TOP_K,
) -> list[Candidate]:
    """Visual-only end-to-end (legacy)."""
    raw = await vector_search(query_vec, candidate_filter, top_k=top_k)
    return rank_candidates(detected_dims, raw)


# ---------- hybrid (visual + text) ----------

def _merge_hits(visual_docs: list[dict], text_docs: list[dict]) -> dict[str, dict]:
    """Union the two hit lists by product id. Each merged entry carries
    `clip_score` and `text_score` (defaulted to 0 when the candidate only
    appeared in one search) plus the doc payload from whichever side has it."""
    merged: dict[str, dict] = {}
    for doc in visual_docs:
        pid = str(doc.get("_id"))
        merged.setdefault(pid, {"doc": doc, "clip_score": 0.0, "text_score": 0.0})
        merged[pid]["clip_score"] = float(doc.get("vec_score") or 0.0)
    for doc in text_docs:
        pid = str(doc.get("_id"))
        if pid in merged:
            merged[pid]["text_score"] = float(doc.get("vec_score") or 0.0)
        else:
            merged[pid] = {
                "doc": doc,
                "clip_score": 0.0,
                "text_score": float(doc.get("vec_score") or 0.0),
            }
    return merged


def rank_hybrid(
    detected_dims: tuple[float, float, float],
    visual_docs: list[dict],
    text_docs: list[dict],
) -> list[Candidate]:
    """Combine visual + text vector hits and re-rank with dim fit."""
    merged = _merge_hits(visual_docs, text_docs)
    weights = (W_VISUAL, W_TEXT, W_DIM_HYBRID)
    out = [
        _build_candidate(
            entry["doc"], detected_dims,
            clip_score=entry["clip_score"],
            text_score=entry["text_score"],
            weights=weights,
        )
        for entry in merged.values()
    ]
    out.sort(key=lambda c: c.combined_score, reverse=True)
    return out


async def hybrid_search_and_rank(
    visual_query: np.ndarray,
    text_query: np.ndarray | None,
    detected_dims: tuple[float, float, float],
    candidate_filter: dict,
    top_k: int = DEFAULT_TOP_K,
) -> list[Candidate]:
    """Dispatch to text / visual / hybrid retrieval based on `MATCH_MODE`.

    Falls back to visual-only if `MATCH_MODE == "text"` but `text_query is None`
    (e.g. Gemini captioning failed) — so a transient Gemini blip degrades to
    a worse-but-still-functional match instead of forcing a white-box."""
    if MATCH_MODE == "text":
        if text_query is None:
            return await search_and_rank(visual_query, detected_dims, candidate_filter, top_k)
        text_docs = await _vector_search(TEXT_PATH, text_query, candidate_filter, top_k)
        weights = (0.0, W_TEXT_ONLY, W_DIM_TEXT_ONLY)
        out = [
            _build_candidate(
                doc, detected_dims,
                clip_score=0.0,
                text_score=float(doc.get("vec_score") or 0.0),
                weights=weights,
            )
            for doc in text_docs
        ]
        out.sort(key=lambda c: c.combined_score, reverse=True)
        return out[:top_k]

    if MATCH_MODE == "visual" or text_query is None:
        return await search_and_rank(visual_query, detected_dims, candidate_filter, top_k)

    visual_task = _vector_search(VISUAL_PATH, visual_query, candidate_filter, top_k)
    text_task = _vector_search(TEXT_PATH, text_query, candidate_filter, top_k)
    visual_docs, text_docs = await asyncio.gather(visual_task, text_task)
    return rank_hybrid(detected_dims, visual_docs, text_docs)[:top_k]
