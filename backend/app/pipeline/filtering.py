"""Build the pre-filter `$match` stage that prunes the catalog before vector search.

Category filtering is intentionally removed. RoomPlan's category label is used
only for its 3D geometry (dimensions, transform, position). The actual furniture
type is determined by the visual + text embeddings — CLIP shape features and
Gemini's free-form identification are treated as ground truth for category.

Searching across the full catalog lets a chair crop match a chair even when
RoomPlan incorrectly labelled it as a sofa.

STRICT_DIMENSION_FILTER can be re-enabled once `dimensions_bbox.volume_m3` is
added to the catalog schema.
"""
from __future__ import annotations

AXIS_TOLERANCE = 0.5
STRICT_DIMENSION_FILTER = False


def _axis_envelope(dim: float, tol: float = AXIS_TOLERANCE) -> tuple[float, float]:
    return dim * (1.0 - tol), dim * (1.0 + tol)


def build_candidate_filter(
    roomplan_category: str,
    detected_dims: tuple[float, float, float],
) -> dict | None:
    """Return a Mongo `$match`-style filter dict for the vector search pre-filter.

    Returns an empty dict (search the full catalog) — category filtering is
    disabled so the embedding determines furniture type, not RoomPlan's label.
    Returns `None` only when the detected object is a structural element that
    has no plausible catalog match at all (stairs, fireplace).
    """
    # Structural elements that are never purchaseable furniture.
    if roomplan_category.lower() in {"fireplace", "stairs"}:
        return None

    if not STRICT_DIMENSION_FILTER:
        return {}  # no pre-filter; vector search ranges over the full catalog

    w_lo, w_hi = _axis_envelope(detected_dims[0])
    h_lo, h_hi = _axis_envelope(detected_dims[1])
    d_lo, d_hi = _axis_envelope(detected_dims[2])

    return {
        "$and": [
            {"dimensions_bbox.width_m": {"$gte": w_lo, "$lte": w_hi}},
            {"dimensions_bbox.height_m": {"$gte": h_lo, "$lte": h_hi}},
            {"dimensions_bbox.depth_m": {"$gte": d_lo, "$lte": d_hi}},
        ]
    }
