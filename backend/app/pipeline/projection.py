"""Project a 3D bounding box onto a camera frame.

Coordinate conventions (must match the iOS upload):
    * Object `transform` (16 floats, column-major) is the object-to-world matrix
      from RoomPlan; corners in object-local space are `(±w/2, ±h/2, ±d/2)`.
    * `camera_transform` (4x4, row-major nested list) is the ARKit camera-to-world
      matrix; the camera looks down its local **-Z** axis.
    * `camera_intrinsics` (3x3, row-major) follows the standard pinhole form.

To project a world point we (a) invert the camera transform to get world→camera,
(b) flip the y/z signs so the resulting frame matches the OpenCV pinhole model
expected by the intrinsics, and (c) apply K. Points with non-positive depth in
the OpenCV frame are behind the camera and rejected.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class ProjectionResult:
    """Outcome of projecting one object's 8 corners into one frame."""

    rect: tuple[float, float, float, float]  # (x, y, w, h) in pixel space, clipped
    rect_unclipped: tuple[float, float, float, float]  # before clipping (for in-frame fraction)
    in_frame_fraction: float  # area(clipped) / area(unclipped), in [0, 1]
    mean_depth: float  # mean OpenCV-frame depth across visible corners (meters)
    visible: bool  # True iff projection produced a usable rect


def _mat4_col_major(flat: list[float]) -> np.ndarray:
    """Reshape a 16-float column-major flat list into a 4x4 numpy matrix."""
    if len(flat) != 16:
        raise ValueError(f"expected 16 floats, got {len(flat)}")
    return np.array(flat, dtype=np.float64).reshape((4, 4), order="F")


def _mat_row_major(rows: list[list[float]], shape: tuple[int, int]) -> np.ndarray:
    """Convert a row-major nested list into a numpy matrix of `shape`."""
    arr = np.array(rows, dtype=np.float64)
    if arr.shape != shape:
        raise ValueError(f"expected shape {shape}, got {arr.shape}")
    return arr


def bbox_corners_world(transform_flat: list[float], dims: tuple[float, float, float]) -> np.ndarray:
    """Return the 8 world-space corners of an axis-aligned local bounding box."""
    w, h, d = dims
    hw, hh, hd = w / 2.0, h / 2.0, d / 2.0
    local = np.array(
        [
            [-hw, -hh, -hd, 1.0],
            [+hw, -hh, -hd, 1.0],
            [+hw, -hh, +hd, 1.0],
            [-hw, -hh, +hd, 1.0],
            [-hw, +hh, -hd, 1.0],
            [+hw, +hh, -hd, 1.0],
            [+hw, +hh, +hd, 1.0],
            [-hw, +hh, +hd, 1.0],
        ],
        dtype=np.float64,
    )
    M = _mat4_col_major(transform_flat)
    world_h = local @ M.T  # (8, 4)
    return world_h[:, :3]


def project_to_pixels(
    world_corners: np.ndarray,
    camera_transform: list[list[float]],
    camera_intrinsics: list[list[float]],
    image_w: int,
    image_h: int,
    min_pixel_size: int = 64,
) -> ProjectionResult:
    """Project world-space corners into pixel space and return the bounding rect."""
    cam_to_world = _mat_row_major(camera_transform, (4, 4))
    K = _mat_row_major(camera_intrinsics, (3, 3))

    world_to_cam = np.linalg.inv(cam_to_world)

    n = world_corners.shape[0]
    homog = np.concatenate([world_corners, np.ones((n, 1))], axis=1)
    cam = homog @ world_to_cam.T  # (n, 4)
    cam_xyz = cam[:, :3]

    # ARKit camera looks down -Z; flip y and z to convert to OpenCV pinhole frame.
    cv = cam_xyz.copy()
    cv[:, 1] = -cv[:, 1]
    cv[:, 2] = -cv[:, 2]

    in_front = cv[:, 2] > 1e-4
    if not np.any(in_front):
        return ProjectionResult((0, 0, 0, 0), (0, 0, 0, 0), 0.0, 0.0, False)

    front = cv[in_front]
    pix = front @ K.T  # (k, 3)
    u = pix[:, 0] / pix[:, 2]
    v = pix[:, 1] / pix[:, 2]

    x0, x1 = float(u.min()), float(u.max())
    y0, y1 = float(v.min()), float(v.max())
    rect_unclipped = (x0, y0, x1 - x0, y1 - y0)

    cx0 = max(0.0, x0)
    cy0 = max(0.0, y0)
    cx1 = min(float(image_w), x1)
    cy1 = min(float(image_h), y1)
    cw = max(0.0, cx1 - cx0)
    ch = max(0.0, cy1 - cy0)

    if cw < min_pixel_size or ch < min_pixel_size:
        return ProjectionResult(
            (cx0, cy0, cw, ch), rect_unclipped, 0.0, float(front[:, 2].mean()), False
        )

    unclipped_area = max(rect_unclipped[2] * rect_unclipped[3], 1e-6)
    in_frame_fraction = (cw * ch) / unclipped_area

    return ProjectionResult(
        rect=(cx0, cy0, cw, ch),
        rect_unclipped=rect_unclipped,
        in_frame_fraction=float(np.clip(in_frame_fraction, 0.0, 1.0)),
        mean_depth=float(front[:, 2].mean()),
        visible=True,
    )
