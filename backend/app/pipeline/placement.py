"""Compute the placement transform for a matched (or unmatched) object.

* **Position** — the floor-anchored XZ center from the detected bounding box.
  Y is set so the matched IKEA item's bottom sits on the floor (uses the
  candidate's height when known; falls back to detected height otherwise).
* **Rotation** — preserve RoomPlan's heading (Y rotation) extracted from the
  4x4 column-major object transform.
* **Scale** — uniform 1.0. IKEA item dimensions are authoritative; we never
  scale to fit.
"""
from __future__ import annotations

import math

from ..models.scan import DetectedObject, ObjectTransform
from .matching import Candidate


def _heading_y(transform_flat: list[float]) -> float:
    """Extract Y rotation (yaw) from a column-major 4x4. Element [r=c, c=col]
    lives at `flat[col*4 + row]`. We use `m[0, 0]` and `m[0, 2]` to recover yaw.
    """
    if len(transform_flat) != 16:
        return 0.0
    m00 = transform_flat[0]   # [row=0, col=0]
    m02 = transform_flat[8]   # [row=0, col=2]
    return math.atan2(m02, m00)


def _floor_y(transform_flat: list[float], detected_height: float, item_height: float | None) -> float:
    """Returns the *center* y so the matched item's bottom sits on the floor.

    Convention: the iOS client's placed node has its pivot at the model's
    rotated geometric center (see `BarebonesCapturedRoom.normalizedImportedNode`).
    Setting `position.y = detected_floor + item_height / 2` therefore puts the
    model centered at floor + h/2 — i.e. its bottom resting on the floor.
    """
    if len(transform_flat) != 16:
        return 0.0
    detected_center_y = transform_flat[13]  # column 3, row 1
    detected_floor = detected_center_y - detected_height / 2.0
    use_height = item_height if (item_height and item_height > 0) else detected_height
    return detected_floor + use_height / 2.0


def compute_transform(detected: DetectedObject, candidate: Candidate | None) -> ObjectTransform:
    """Build the final transform for the response."""
    item_height = candidate.dims[1] if candidate and candidate.dims[1] > 0 else None
    detected_height = detected.dimensions[1]

    tx = detected.transform[12] if len(detected.transform) == 16 else 0.0
    tz = detected.transform[14] if len(detected.transform) == 16 else 0.0
    ty = _floor_y(detected.transform, detected_height, item_height)

    yaw = _heading_y(detected.transform)

    return ObjectTransform(
        position=(tx, ty, tz),
        rotation_euler=(0.0, yaw, 0.0),
        scale=(1.0, 1.0, 1.0),
    )
