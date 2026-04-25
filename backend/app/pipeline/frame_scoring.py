"""Pick the best frames for each detected object.

A frame is good when the object's projected box is large, centered, fully
inside the image, and sharp. The combined score is a weighted sum; the top-K
frames per object are kept (default K=3). Sharpness is computed on the cropped
region with a Laplacian-variance approximation in pure numpy so we don't pull
in OpenCV.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from PIL import Image

from .projection import ProjectionResult


W_AREA = 0.4
W_CENTERED = 0.2
W_IN_FRAME = 0.3
W_SHARPNESS = 0.1

DEFAULT_TOP_K = 3


@dataclass(frozen=True)
class FrameScore:
    frame_id: str
    projection: ProjectionResult
    area_score: float
    centered_score: float
    in_frame_score: float
    sharpness_score: float
    total: float


def _laplacian_variance(gray: np.ndarray) -> float:
    """Variance of a 3x3 Laplacian — proxy for image sharpness."""
    if gray.size == 0:
        return 0.0
    kernel = np.array([[0, 1, 0], [1, -4, 1], [0, 1, 0]], dtype=np.float32)
    h, w = gray.shape
    if h < 3 or w < 3:
        return 0.0
    out = np.zeros_like(gray, dtype=np.float32)
    out[1:-1, 1:-1] = (
        gray[:-2, 1:-1] + gray[2:, 1:-1] + gray[1:-1, :-2] + gray[1:-1, 2:]
        - 4 * gray[1:-1, 1:-1]
    )
    return float(out.var())


def _sharpness_score(image: Image.Image, rect: tuple[float, float, float, float]) -> float:
    """Normalize Laplacian variance into [0, 1] with a soft cap."""
    x, y, w, h = rect
    if w <= 0 or h <= 0:
        return 0.0
    crop = image.crop((int(x), int(y), int(x + w), int(y + h))).convert("L")
    arr = np.asarray(crop, dtype=np.float32)
    if arr.size == 0:
        return 0.0
    # Downsample large crops so this stays fast on 1024px frames.
    if max(arr.shape) > 256:
        scale = 256 / max(arr.shape)
        new_size = (max(int(arr.shape[1] * scale), 1), max(int(arr.shape[0] * scale), 1))
        arr = np.asarray(crop.resize(new_size), dtype=np.float32)
    variance = _laplacian_variance(arr)
    return float(np.clip(variance / 1000.0, 0.0, 1.0))


def score_frame(
    frame_id: str,
    projection: ProjectionResult,
    image: Image.Image,
    image_w: int,
    image_h: int,
) -> FrameScore | None:
    """Score a single (object, frame) pair. Returns None if the projection isn't usable."""
    if not projection.visible:
        return None

    x, y, w, h = projection.rect
    image_area = float(image_w * image_h) or 1.0
    area = (w * h) / image_area
    area_score = float(np.clip(area * 4.0, 0.0, 1.0))  # ~25% of frame ≈ saturated

    cx, cy = x + w / 2.0, y + h / 2.0
    image_diag = float(np.hypot(image_w, image_h)) or 1.0
    dist = float(np.hypot(cx - image_w / 2.0, cy - image_h / 2.0))
    centered_score = max(0.0, 1.0 - dist / (image_diag / 2.0))

    in_frame_score = projection.in_frame_fraction
    sharpness_score = _sharpness_score(image, projection.rect)

    total = (
        W_AREA * area_score
        + W_CENTERED * centered_score
        + W_IN_FRAME * in_frame_score
        + W_SHARPNESS * sharpness_score
    )

    return FrameScore(
        frame_id=frame_id,
        projection=projection,
        area_score=area_score,
        centered_score=centered_score,
        in_frame_score=in_frame_score,
        sharpness_score=sharpness_score,
        total=total,
    )


def select_top_frames(scores: list[FrameScore], top_k: int = DEFAULT_TOP_K) -> list[FrameScore]:
    """Sort scored frames descending by total and keep the top K."""
    return sorted(scores, key=lambda s: s.total, reverse=True)[:top_k]
