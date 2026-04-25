"""Build the hard-filter `$match` stage that prunes the catalog before vector search.

Demo mode: filter only on category (RoomPlan label → mapped catalog categories).
The dimension envelope was too aggressive — `dimensions_bbox.volume_m3` doesn't
exist in the live catalog, so the `$or` fallback no-op'd and per-axis ±25% was
filtering out almost everything. Dimensions still influence the *ranking* via
`matching.dim_fit_score`, so we'll still prefer correctly-sized matches without
hard-rejecting the slightly-off ones.

Set `STRICT_DIMENSION_FILTER = True` to re-enable the hard envelope (only do
this once `dimensions_bbox.volume_m3` is added to the catalog).
"""
from __future__ import annotations

from .category_map import catalog_categories_for

AXIS_TOLERANCE = 0.5         # widened from 0.25; only used when STRICT_DIMENSION_FILTER
STRICT_DIMENSION_FILTER = False


def _axis_envelope(dim: float, tol: float = AXIS_TOLERANCE) -> tuple[float, float]:
    return dim * (1.0 - tol), dim * (1.0 + tol)


def build_candidate_filter(
    roomplan_category: str,
    detected_dims: tuple[float, float, float],
) -> dict | None:
    """Return a Mongo `$match`-style filter dict, or `None` when the RoomPlan
    category has no plausible catalog match (caller should skip vector search
    and white-box)."""
    categories = catalog_categories_for(roomplan_category)
    if not categories:
        return None

    category_clause = {"taxonomy_inferred.category": {"$in": categories}}

    if not STRICT_DIMENSION_FILTER:
        return category_clause

    w_lo, w_hi = _axis_envelope(detected_dims[0])
    h_lo, h_hi = _axis_envelope(detected_dims[1])
    d_lo, d_hi = _axis_envelope(detected_dims[2])

    return {
        "$and": [
            category_clause,
            {"dimensions_bbox.width_m": {"$gte": w_lo, "$lte": w_hi}},
            {"dimensions_bbox.height_m": {"$gte": h_lo, "$lte": h_hi}},
            {"dimensions_bbox.depth_m": {"$gte": d_lo, "$lte": d_hi}},
        ]
    }
