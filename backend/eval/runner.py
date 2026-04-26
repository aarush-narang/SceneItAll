"""Shared fixture loader and per-object evaluator.

`run_eval.py` and `tune_thresholds.py` both call `evaluate_fixture`. Pipeline
functions are imported and called directly (no HTTP) so the harness measures
the matcher in isolation.
"""
from __future__ import annotations

import asyncio
import io
import json
from dataclasses import dataclass, asdict
from pathlib import Path

from PIL import Image

from app.models.scan import DetectedObject, FrameMetadata, ScanPayload
from app.pipeline.category_refinement import refine_category
from app.pipeline.cropping import crop_with_margin
from app.pipeline.decision import COMMIT_THRESHOLD, MatchDecision, decide
from app.pipeline.embedding import embed_crops_mean
from app.pipeline.filtering import build_candidate_filter
from app.pipeline.frame_scoring import score_frame, select_top_frames
from app.pipeline.matching import Candidate, search_and_rank
from app.pipeline.projection import bbox_corners_world, project_to_pixels
from app.pipeline.segmentation import segment_to_white_bg


@dataclass
class GroundTruth:
    detected_id: str
    expected_product_id: str | None
    expected_category: str


@dataclass
class ObjectResult:
    detected_id: str
    expected_product_id: str | None
    expected_category: str
    matched_product_id: str | None
    refined_category: str
    decision_reason: str
    top_score: float
    top_5_ids: list[str]
    n_frames_used: int


def _load_fixture(path: Path) -> tuple[ScanPayload, list[FrameMetadata], dict[str, Image.Image], list[GroundTruth]]:
    scan = ScanPayload(**json.loads((path / "scan.json").read_text()))
    frames = [FrameMetadata(**f) for f in json.loads((path / "frames_metadata.json").read_text())]
    gts = [GroundTruth(**g) for g in json.loads((path / "ground_truth.json").read_text())]
    images: dict[str, Image.Image] = {}
    for fm in frames:
        img_path = path / "frames" / fm.image_filename
        images[fm.frame_id] = Image.open(io.BytesIO(img_path.read_bytes())).convert("RGB")
    return scan, frames, images, gts


async def _process_for_eval(
    obj: DetectedObject,
    frames: list[FrameMetadata],
    images: dict[str, Image.Image],
    threshold: float,
) -> tuple[list[Candidate], int, str, MatchDecision]:
    """Same pipeline as the orchestrator, returning the full candidate list."""
    world_corners = bbox_corners_world(obj.transform, obj.dimensions)

    scored = []
    for fm in frames:
        image = images.get(fm.frame_id)
        if image is None:
            continue
        proj = project_to_pixels(
            world_corners=world_corners,
            camera_transform=fm.camera_transform,
            camera_intrinsics=fm.camera_intrinsics,
            image_w=fm.image_width,
            image_h=fm.image_height,
        )
        s = score_frame(fm.frame_id, proj, image, fm.image_width, fm.image_height)
        if s is not None:
            scored.append(s)

    top = select_top_frames(scored)
    crops = []
    for s in top:
        try:
            crops.append(crop_with_margin(images[s.frame_id], s.projection.rect))
        except ValueError:
            continue

    query_vec = None
    if crops:
        segmented = [segment_to_white_bg(c) for c in crops]
        query_vec = embed_crops_mean(segmented)

    candidates: list[Candidate] = []
    if query_vec is not None:
        candidate_filter = build_candidate_filter(obj.category, obj.dimensions)
        candidates = await search_and_rank(query_vec, obj.dimensions, candidate_filter)

    refined = refine_category(obj.category, candidates)
    decision = decide(candidates, had_usable_embedding=query_vec is not None, threshold=threshold)

    return candidates, len(top), refined, decision


async def evaluate_fixture(path: Path, threshold: float = COMMIT_THRESHOLD) -> list[ObjectResult]:
    """Run the matcher over one fixture and return per-object results."""
    scan, frames, images, gts = _load_fixture(path)
    gt_by_id = {g.detected_id: g for g in gts}
    out: list[ObjectResult] = []

    for obj in scan.detected_objects:
        gt = gt_by_id.get(obj.identifier)
        if gt is None:
            continue
        candidates, n_frames, refined, decision = await _process_for_eval(
            obj, frames, images, threshold
        )
        out.append(
            ObjectResult(
                detected_id=obj.identifier,
                expected_product_id=gt.expected_product_id,
                expected_category=gt.expected_category,
                matched_product_id=decision.matched.product_id if decision.matched else None,
                refined_category=refined,
                decision_reason=decision.reason,
                top_score=decision.top_score,
                top_5_ids=[c.product_id for c in candidates[:5]],
                n_frames_used=n_frames,
            )
        )
    return out


def aggregate(results: list[ObjectResult]) -> dict:
    """Top-1, top-5, category, white-box accuracy + per-category breakdown."""
    total = len(results)
    if total == 0:
        return {"total": 0}

    top1 = sum(1 for r in results if r.matched_product_id == r.expected_product_id)
    top5 = sum(
        1 for r in results
        if r.expected_product_id is not None
        and r.expected_product_id in r.top_5_ids
    )
    cat = sum(1 for r in results if r.refined_category == r.expected_category)

    truly_null = [r for r in results if r.expected_product_id is None]
    truly_real = [r for r in results if r.expected_product_id is not None]
    white_box_correct = sum(1 for r in truly_null if r.matched_product_id is None)
    false_white_box = sum(1 for r in truly_real if r.matched_product_id is None)

    by_cat: dict[str, dict] = {}
    for r in results:
        c = r.expected_category
        bucket = by_cat.setdefault(c, {"total": 0, "top1": 0})
        bucket["total"] += 1
        if r.matched_product_id == r.expected_product_id:
            bucket["top1"] += 1

    return {
        "total": total,
        "top1_accuracy": top1 / total,
        "top5_accuracy": top5 / max(len(truly_real), 1),
        "category_accuracy": cat / total,
        "white_box_correct": white_box_correct,
        "white_box_total": len(truly_null),
        "false_white_box_rate": false_white_box / max(len(truly_real), 1),
        "per_category": by_cat,
    }


def run_async(coro):
    return asyncio.run(coro)
