"""Smoke tests for pipeline.projection.

The 4x4 conventions are easy to get wrong, so these fix the math against a
hand-constructed scenario (camera at the origin looking down -Z, object 2m in
front, axis-aligned 1m cube)."""
import math

import numpy as np

from app.pipeline.projection import (
    bbox_corners_world,
    project_to_pixels,
    _mat4_col_major,
)


def _identity_col_major() -> list[float]:
    """4x4 identity, column-major flat."""
    return [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    ]


def _translation_col_major(tx: float, ty: float, tz: float) -> list[float]:
    """4x4 pure translation, column-major flat (translation in last column)."""
    return [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        tx, ty, tz, 1.0,
    ]


def test_mat4_col_major_roundtrip():
    M = _mat4_col_major(_translation_col_major(1.0, 2.0, 3.0))
    assert M[0, 3] == 1.0
    assert M[1, 3] == 2.0
    assert M[2, 3] == 3.0


def test_bbox_corners_world_axis_aligned():
    """An axis-aligned 1m cube at the origin has 8 corners at ±0.5."""
    corners = bbox_corners_world(_identity_col_major(), (1.0, 1.0, 1.0))
    assert corners.shape == (8, 3)
    assert np.allclose(np.sort(corners.flatten()), [-0.5] * 12 + [0.5] * 12)


def test_bbox_corners_world_translated():
    corners = bbox_corners_world(_translation_col_major(2.0, 0.0, -3.0), (1.0, 2.0, 1.0))
    means = corners.mean(axis=0)
    assert np.allclose(means, [2.0, 0.0, -3.0])


def test_project_to_pixels_object_in_front_of_camera():
    """A 1m cube 2m in front of the camera (camera at origin, ARKit -Z forward)
    should project to a positive-area rect roughly centered in the image."""
    image_w, image_h = 1024, 768
    fx = fy = 800.0
    cx, cy = image_w / 2.0, image_h / 2.0
    intrinsics = [[fx, 0.0, cx], [0.0, fy, cy], [0.0, 0.0, 1.0]]
    cam_to_world = [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]
    # Object 2m in front of the camera (world -Z is "forward" for an identity camera).
    corners = bbox_corners_world(_translation_col_major(0.0, 0.0, -2.0), (1.0, 1.0, 1.0))
    result = project_to_pixels(corners, cam_to_world, intrinsics, image_w, image_h)
    assert result.visible
    x, y, w, h = result.rect
    assert w > 0 and h > 0
    rect_cx = x + w / 2.0
    rect_cy = y + h / 2.0
    assert abs(rect_cx - cx) < 50
    assert abs(rect_cy - cy) < 50


def test_project_to_pixels_object_behind_camera_rejected():
    image_w, image_h = 1024, 768
    intrinsics = [[800.0, 0.0, 512.0], [0.0, 800.0, 384.0], [0.0, 0.0, 1.0]]
    cam_to_world = [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]
    # Object 2m behind the camera — should be rejected.
    corners = bbox_corners_world(_translation_col_major(0.0, 0.0, 2.0), (1.0, 1.0, 1.0))
    result = project_to_pixels(corners, cam_to_world, intrinsics, image_w, image_h)
    assert not result.visible


def test_project_to_pixels_too_small_rejected():
    """A 1cm cube 5m away projects below the 64px minimum and is rejected."""
    image_w, image_h = 1024, 768
    intrinsics = [[800.0, 0.0, 512.0], [0.0, 800.0, 384.0], [0.0, 0.0, 1.0]]
    cam_to_world = [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]
    corners = bbox_corners_world(_translation_col_major(0.0, 0.0, -5.0), (0.01, 0.01, 0.01))
    result = project_to_pixels(corners, cam_to_world, intrinsics, image_w, image_h)
    assert not result.visible
