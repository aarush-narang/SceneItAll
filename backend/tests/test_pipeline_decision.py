"""Smoke tests for category refinement, decision threshold, filtering, and placement."""
import math

from app.models.scan import DetectedObject
from app.pipeline.category_refinement import refine_category
from app.pipeline.decision import COMMIT_THRESHOLD, decide
from app.pipeline.filtering import build_candidate_filter
from app.pipeline.matching import Candidate, _dim_fit_score, rank_candidates
from app.pipeline.placement import compute_transform


def _candidate(
    pid: str,
    *,
    category: str = "coffee_table",
    subcategory: str | None = "coffee_table",
    dims: tuple[float, float, float] = (1.2, 0.45, 0.6),
    clip_score: float = 0.6,
    dim_fit: float = 0.9,
) -> Candidate:
    combined = 0.7 * clip_score + 0.3 * dim_fit
    return Candidate(
        product_id=pid,
        name=pid,
        category=category,
        subcategory=subcategory,
        dims=dims,
        usdz_url=f"https://r2/{pid}.usdz",
        clip_score=clip_score,
        dim_fit_score=dim_fit,
        combined_score=combined,
    )


# --- category_refinement ---

def test_refine_category_promotes_subcategory_when_majority():
    cands = [_candidate(f"c{i}", subcategory="coffee_table") for i in range(8)]
    cands += [_candidate(f"c{i}", subcategory="side_table") for i in range(2)]
    assert refine_category("table", cands) == "coffee_table"


def test_refine_category_keeps_label_when_no_majority():
    cands = [_candidate(f"c{i}", subcategory="coffee_table") for i in range(5)]
    cands += [_candidate(f"c{i}", subcategory="side_table") for i in range(5)]
    assert refine_category("table", cands) == "table"


def test_refine_category_handles_empty():
    assert refine_category("table", []) == "table"


# --- decision ---

def test_decide_no_embedding_white_boxes():
    decision = decide([_candidate("c0")], had_usable_embedding=False)
    assert decision.matched is None
    assert decision.reason == "no_usable_embedding"


def test_decide_no_candidates_white_boxes():
    decision = decide([], had_usable_embedding=True)
    assert decision.matched is None
    assert decision.reason == "no_candidates_after_filter"


def test_decide_demo_mode_commits_even_weak_candidates():
    """ALWAYS_COMMIT=True: skips score and ambiguity checks; commits top-1."""
    weak = _candidate("c0", clip_score=0.1, dim_fit=0.1)
    decision = decide([weak], had_usable_embedding=True)
    assert decision.matched is not None
    assert decision.matched.product_id == "c0"
    assert decision.reason == "committed_demo"


def test_decide_commits_strong_match():
    cands = [_candidate(f"c{i}", clip_score=0.7, dim_fit=0.9) for i in range(10)]
    decision = decide(cands, had_usable_embedding=True)
    assert decision.matched is not None
    assert decision.matched.product_id == "c0"
    # ALWAYS_COMMIT path → "committed_demo"; strict path → "committed".
    assert decision.reason in ("committed", "committed_demo")


def test_decide_demo_mode_commits_ambiguous_categories():
    """ALWAYS_COMMIT=True: scattered categories no longer block the commit."""
    cands = [_candidate(f"c{i}", category=f"cat_{i}", subcategory=None) for i in range(10)]
    decision = decide(cands, had_usable_embedding=True)
    assert decision.matched is not None
    assert decision.reason == "committed_demo"


# --- filtering ---

def test_build_candidate_filter_includes_mapped_categories():
    f = build_candidate_filter("table", (1.2, 0.45, 0.6))
    cat_clause = f["taxonomy_inferred.category"]["$in"]
    assert "table" in cat_clause
    assert "desk" in cat_clause


def test_build_candidate_filter_returns_none_for_unmappable_category():
    """RoomPlan categories with no catalog equivalent (fireplace, stairs)
    return None so the orchestrator can short-circuit to white-box."""
    assert build_candidate_filter("fireplace", (1.0, 1.0, 0.5)) is None
    assert build_candidate_filter("stairs", (1.0, 2.0, 1.0)) is None


def test_build_candidate_filter_demo_mode_skips_dimension_filter():
    """STRICT_DIMENSION_FILTER is off; the filter only constrains category."""
    f = build_candidate_filter("chair", (0.6, 0.9, 0.6))
    assert "$and" not in f
    assert set(f.keys()) == {"taxonomy_inferred.category"}


# --- matching helpers ---

def test_dim_fit_score_perfect():
    assert _dim_fit_score((1.0, 1.0, 1.0), (1.0, 1.0, 1.0)) == 1.0


def test_dim_fit_score_clamps_negative():
    assert _dim_fit_score((1.0, 1.0, 1.0), (10.0, 10.0, 10.0)) == 0.0


def test_rank_candidates_orders_by_combined_score():
    docs = [
        {
            "_id": "low",
            "name": "low",
            "taxonomy_inferred": {"category": "coffee_table", "subcategory": "coffee_table"},
            "dimensions_bbox": {"width_m": 2.0, "height_m": 0.45, "depth_m": 0.6},
            "files": {"usdz_url": "u"},
            "clip_score": 0.4,
        },
        {
            "_id": "high",
            "name": "high",
            "taxonomy_inferred": {"category": "coffee_table", "subcategory": "coffee_table"},
            "dimensions_bbox": {"width_m": 1.2, "height_m": 0.45, "depth_m": 0.6},
            "files": {"usdz_url": "u"},
            "clip_score": 0.6,
        },
    ]
    ranked = rank_candidates((1.2, 0.45, 0.6), docs)
    assert ranked[0].product_id == "high"


# --- placement ---

def _identity_obj(category: str = "table", dims: tuple[float, float, float] = (1.0, 0.5, 1.0)) -> DetectedObject:
    transform = [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        2.0, 0.5, 3.0, 1.0,  # detected center at (2, 0.5, 3)
    ]
    return DetectedObject(
        identifier="obj1", category=category, dimensions=dims, transform=transform
    )


def test_compute_transform_uses_detected_xz_and_floor_anchors_y():
    obj = _identity_obj(dims=(1.0, 0.5, 1.0))  # detected box base at y=0.25
    cand = _candidate("c0", dims=(1.0, 1.0, 1.0))  # taller item
    t = compute_transform(obj, cand)
    assert math.isclose(t.position[0], 2.0)
    assert math.isclose(t.position[2], 3.0)
    # Floor at 0.5 - 0.5/2 = 0.25; item center sits at 0.25 + 1.0/2 = 0.75.
    assert math.isclose(t.position[1], 0.75)
    assert t.scale == (1.0, 1.0, 1.0)


def test_compute_transform_falls_back_to_detected_height_for_white_box():
    obj = _identity_obj(dims=(1.0, 0.5, 1.0))
    t = compute_transform(obj, None)
    # Item center stays at the detected center (0.25 + 0.5/2 = 0.5).
    assert math.isclose(t.position[1], 0.5)


def test_compute_transform_extracts_yaw_from_rotation():
    yaw = math.pi / 4
    c, s = math.cos(yaw), math.sin(yaw)
    transform = [
        c, 0.0, -s, 0.0,
        0.0, 1.0, 0.0, 0.0,
        s, 0.0, c, 0.0,
        0.0, 0.5, 0.0, 1.0,
    ]
    obj = DetectedObject(
        identifier="obj1", category="table", dimensions=(1.0, 0.5, 1.0), transform=transform
    )
    t = compute_transform(obj, None)
    assert math.isclose(t.rotation_euler[1], yaw, abs_tol=1e-6)
