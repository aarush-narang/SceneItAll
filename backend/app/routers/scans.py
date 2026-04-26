from __future__ import annotations

import asyncio
import io
import json
import re
import time
import uuid
import numpy as np
from fastapi import APIRouter, HTTPException, Request
from PIL import Image

from ..logging import log
from ..models.scan import (
    DetectedObject,
    FrameMetadata,
    MatchedObject,
    OriginalBBox,
    ScanPayload,
    ScanResponse,
)
from ..pipeline.category_refinement import refine_category
from ..pipeline.cropping import crop_with_margin
from ..pipeline.decision import decide
from ..pipeline.embedding import embed_crops_mean
from ..pipeline.filtering import build_candidate_filter
from ..pipeline.frame_scoring import score_frame, select_top_frames
from ..pipeline.matching import hybrid_search_and_rank
from ..pipeline.placement import compute_transform
from ..pipeline.projection import bbox_corners_world, project_to_pixels
from ..pipeline.segmentation import segment_to_white_bg
from ..services.embeddings import caption_image_gemini, embed_text_gemini

router = APIRouter(prefix="/v1/scans", tags=["scans"])

# Cap parallel object processing — CLIP + rembg are CPU/GPU heavy and the
# bottleneck is one-object-at-a-time on the same device.
MAX_OBJECT_CONCURRENCY = 8


# ---------- request parsing ----------

_BOUNDARY_RE = re.compile(rb'boundary="?([^";]+)"?', re.IGNORECASE)
_DISPOSITION_NAME_RE = re.compile(rb'name="([^"]+)"', re.IGNORECASE)


async def _read_multipart(
    request: Request,
) -> tuple[bytes, bytes, dict[str, bytes]]:
    """Parse the multipart body manually so binary file parts (JPEGs) stay as
    raw bytes. Starlette's `request.form()` decodes file parts as text under
    some conditions, which corrupts binary data — we side-step that here.
    """
    content_type = request.headers.get("content-type", "")
    boundary_match = _BOUNDARY_RE.search(content_type.encode())
    if not boundary_match:
        raise HTTPException(status_code=400, detail="Missing multipart boundary in Content-Type")
    boundary = boundary_match.group(1)

    body = await request.body()
    parts = _split_multipart(body, boundary)

    scan_raw: bytes | None = None
    frames_meta_raw: bytes | None = None
    frame_images: dict[str, bytes] = {}

    for part in parts:
        name = part["name"]
        data = part["data"]
        if name == "scan_json":
            scan_raw = data
        elif name == "frames_metadata":
            frames_meta_raw = data
        elif name.startswith("frame_"):
            frame_images[name] = data

    log.info(
        "scan.multipart_parsed",
        scan_json_bytes=(len(scan_raw) if scan_raw else 0),
        frames_metadata_bytes=(len(frames_meta_raw) if frames_meta_raw else 0),
        frame_keys=sorted(frame_images.keys())[:10],
        n_frame_keys=len(frame_images),
    )

    if scan_raw is None:
        raise HTTPException(status_code=422, detail="Missing scan_json part")
    if frames_meta_raw is None:
        raise HTTPException(status_code=422, detail="Missing frames_metadata part")

    return scan_raw, frames_meta_raw, frame_images


def _split_multipart(body: bytes, boundary: bytes) -> list[dict]:
    """Tiny RFC-2046 multipart splitter. Returns one dict per body part with
    keys `name`, `filename`, `data`. Treats the body as raw bytes throughout —
    nothing is decoded as text except the headers."""
    delimiter = b"--" + boundary
    chunks = body.split(delimiter)
    parts: list[dict] = []
    for chunk in chunks:
        # Skip preamble, the closing `--\r\n` epilogue, and empty splits.
        if not chunk or chunk in (b"--\r\n", b"--"):
            continue
        if chunk.startswith(b"--"):  # closing boundary marker
            continue
        if chunk.startswith(b"\r\n"):
            chunk = chunk[2:]
        if chunk.endswith(b"\r\n"):
            chunk = chunk[:-2]
        # Header block ends at the first blank line.
        sep = chunk.find(b"\r\n\r\n")
        if sep < 0:
            continue
        headers_raw = chunk[:sep]
        data = chunk[sep + 4:]

        name: str | None = None
        filename: str | None = None
        for line in headers_raw.split(b"\r\n"):
            if not line.lower().startswith(b"content-disposition:"):
                continue
            m_name = _DISPOSITION_NAME_RE.search(line)
            if m_name:
                name = m_name.group(1).decode("utf-8", errors="replace")
            m_file = re.search(rb'filename="([^"]*)"', line, re.IGNORECASE)
            if m_file:
                filename = m_file.group(1).decode("utf-8", errors="replace")
        if name is None:
            continue
        parts.append({"name": name, "filename": filename, "data": data})
    return parts


def _parse_scan(scan_raw: bytes) -> ScanPayload:
    try:
        return ScanPayload(**json.loads(scan_raw))
    except Exception as exc:
        log.error("scan.invalid_scan_json", error=str(exc), preview=scan_raw[:400].decode(errors="replace"))
        raise HTTPException(status_code=422, detail=f"Invalid scan_json: {exc}") from exc


def _parse_frames(frames_meta_raw: bytes) -> list[FrameMetadata]:
    try:
        raw = json.loads(frames_meta_raw)
        return [FrameMetadata(**f) for f in raw]
    except Exception as exc:
        log.error("scan.invalid_frames_metadata", error=str(exc), preview=frames_meta_raw[:400].decode(errors="replace"))
        raise HTTPException(status_code=422, detail=f"Invalid frames_metadata: {exc}") from exc


def _validate_frames_present(
    frames: list[FrameMetadata], frame_images: dict[str, bytes]
) -> None:
    for fm in frames:
        key = fm.frame_id if fm.frame_id.startswith("frame_") else f"frame_{fm.frame_id}"
        if key not in frame_images:
            log.error(
                "scan.frame_part_missing",
                frame_id=fm.frame_id,
                available=sorted(frame_images.keys())[:10],
            )
            raise HTTPException(
                status_code=422,
                detail=f"Frame metadata references {fm.frame_id} but no matching upload part",
            )


def _validate_objects(objects: list[DetectedObject]) -> None:
    for obj in objects:
        w, h, d = obj.dimensions
        if w <= 0 or h <= 0 or d <= 0:
            log.error(
                "scan.bad_dimensions",
                identifier=obj.identifier,
                category=obj.category,
                dimensions=list(obj.dimensions),
            )
            raise HTTPException(
                status_code=422,
                detail=f"Object {obj.identifier} has non-positive dimensions",
            )


def _decode_images(
    frames: list[FrameMetadata], frame_images: dict[str, bytes]
) -> dict[str, Image.Image]:
    decoded: dict[str, Image.Image] = {}
    for fm in frames:
        key = fm.frame_id if fm.frame_id.startswith("frame_") else f"frame_{fm.frame_id}"
        decoded[fm.frame_id] = Image.open(io.BytesIO(frame_images[key])).convert("RGB")
    return decoded


def _build_room_passthrough(scan: ScanPayload) -> dict:
    return {
        "identifier": scan.identifier,
        "story": scan.story,
        "version": scan.version,
        "walls": scan.walls,
        "doors": scan.doors,
        "windows": scan.windows,
        "openings": scan.openings,
        "floors": scan.floors,
        "sections": scan.sections,
    }


# ---------- per-object pipeline ----------

def _embed_object_sync(
    crops: list[Image.Image],
) -> tuple[np.ndarray | None, Image.Image | None]:
    """Segment + visual-embed in a worker thread.

    Returns `(visual_query_vec, best_segmented_crop)`. The best crop (the first
    one — `select_top_frames` returns frames already sorted by score) is
    handed back so the orchestrator can run a Gemini caption on it for the
    text side of the hybrid search."""
    if not crops:
        return None, None
    segmented = [segment_to_white_bg(c) for c in crops]
    visual = embed_crops_mean(segmented)
    return visual, segmented[0]


def _caption_and_embed_sync(image: Image.Image) -> tuple[str, np.ndarray] | None:
    """Run Gemini Flash caption + Gemini text embed on one image. Returns
    `(caption, text_query_vec)` or None if either step fails. Network IO is
    blocking, so this runs in a worker thread."""
    try:
        caption = caption_image_gemini(image)
        if not caption:
            return None
        vec = np.asarray(embed_text_gemini(caption), dtype=np.float32)
        return caption, vec
    except Exception:
        return None


async def _process_object(
    obj: DetectedObject,
    frames: list[FrameMetadata],
    images: dict[str, Image.Image],
    scan_id: str,
    sem: asyncio.Semaphore,
) -> MatchedObject:
    async with sem:
        return await _process_object_inner(obj, frames, images, scan_id)


async def _process_object_inner(
    obj: DetectedObject,
    frames: list[FrameMetadata],
    images: dict[str, Image.Image],
    scan_id: str,
) -> MatchedObject:
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

    crops: list[Image.Image] = []
    for s in top:
        try:
            crops.append(crop_with_margin(images[s.frame_id], s.projection.rect))
        except ValueError:
            continue

    query_vec: np.ndarray | None = None
    text_query_vec: np.ndarray | None = None
    caption: str | None = None
    if crops:
        query_vec, best_crop = await asyncio.to_thread(_embed_object_sync, crops)
        if best_crop is not None:
            caption_result = await asyncio.to_thread(_caption_and_embed_sync, best_crop)
            if caption_result is not None:
                caption, text_query_vec = caption_result

    candidates = []
    if query_vec is not None:
        candidate_filter = build_candidate_filter(obj.category, obj.dimensions)
        if candidate_filter is not None:
            try:
                candidates = await hybrid_search_and_rank(
                    visual_query=query_vec,
                    text_query=text_query_vec,
                    detected_dims=obj.dimensions,
                    candidate_filter=candidate_filter,
                )
            except Exception as exc:
                log.warning(
                    "scan.vector_search_failed",
                    scan_id=scan_id,
                    detected_id=obj.identifier,
                    error=str(exc),
                )

    refined = refine_category(obj.category, candidates)
    decision = decide(candidates, had_usable_embedding=query_vec is not None)

    transform = compute_transform(obj, decision.matched)

    log.info(
        "scan.match",
        scan_id=scan_id,
        detected_id=obj.identifier,
        roomplan_category=obj.category,
        refined_category=refined,
        decision_reason=decision.reason,
        matched_product_id=(decision.matched.product_id if decision.matched else "WHITE_BOX"),
        matched_product_name=(decision.matched.name if decision.matched else None),
        top_clip_score=round(decision.matched.clip_score, 3) if decision.matched else 0.0,
        top_text_score=round(decision.matched.text_score, 3) if decision.matched else 0.0,
        top_dim_fit=round(decision.matched.dim_fit_score, 3) if decision.matched else 0.0,
        top_combined=round(decision.top_score, 3),
        category_consistency=round(decision.category_consistency, 3),
        n_frames_used=len(top),
        n_candidates=len(candidates),
        had_visual=query_vec is not None,
        had_text=text_query_vec is not None,
        gemini_caption=caption,
    )

    return MatchedObject(
        detected_id=obj.identifier,
        matched_product_id=decision.matched.product_id if decision.matched else None,
        matched_product_name=decision.matched.name if decision.matched else None,
        matched_usdz_url=decision.matched.usdz_url if decision.matched else None,
        refined_category=refined,
        transform=transform,
        original_bbox=OriginalBBox(
            dimensions=obj.dimensions,
            transform=obj.transform,
        ),
    )




# ---------- endpoint ----------

@router.post("", response_model=ScanResponse)
async def create_scan(request: Request) -> ScanResponse:
    scan_id = str(uuid.uuid4())
    started = time.monotonic()

    scan_raw, frames_meta_raw, frame_images = await _read_multipart(request)
    scan = _parse_scan(scan_raw)
    frames = _parse_frames(frames_meta_raw)
    _validate_frames_present(frames, frame_images)
    _validate_objects(scan.detected_objects)
    images = _decode_images(frames, frame_images)

    log.info(
        "scan.received",
        scan_id=scan_id,
        detected_objects=len(scan.detected_objects),
        frames=len(frames),
    )

    sem = asyncio.Semaphore(MAX_OBJECT_CONCURRENCY)
    matched_objects = await asyncio.gather(
        *[
            _process_object(obj, frames, images, scan_id, sem)
            for obj in scan.detected_objects
        ]
    )

    n_matched = sum(1 for m in matched_objects if m.matched_product_id)
    n_whitebox = len(matched_objects) - n_matched
    elapsed = time.monotonic() - started
    log.info(
        "scan.complete",
        scan_id=scan_id,
        matched=n_matched,
        whitebox=n_whitebox,
        elapsed_s=round(elapsed, 2),
    )

    return ScanResponse(
        scan_id=scan_id,
        room=_build_room_passthrough(scan),
        objects=list(matched_objects),
    )
