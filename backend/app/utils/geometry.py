"""Geometry helpers for validating furniture placements against a RoomPlan capture.

Coordinate convention: y-up, eulerAngles in radians applied as (pitch, yaw, roll)
on the (x, y, z) axes. Floor polygons are 2D `(x, z)` sequences at floor height.
"""

import math
from dataclasses import dataclass
from typing import Sequence


_DEFAULT_UPRIGHT_TOLERANCE_RAD = math.radians(15)
_DEFAULT_FLOOR_TOLERANCE_M = 0.05
_DEFAULT_DOOR_CLEARANCE_M = 1.0
_DEFAULT_OPENING_CLEARANCE_M = 1.0
_DEFAULT_WINDOW_CLEARANCE_M = 0.0
_INWARD_PROBE_M = 0.1


@dataclass(frozen=True)
class PlacementBox:
    """An item's spatial footprint, packaged for placement checks."""

    position: Sequence[float]            # (x, y, z), meters
    euler_angles: Sequence[float]        # (pitch, yaw, roll), radians
    width_m: float
    height_m: float
    depth_m: float


def point_in_polygon(px: float, pz: float, polygon: Sequence[Sequence[float]]) -> bool:
    """Ray-cast point-in-polygon test on the xz plane. Each polygon point is a
    2-element sequence `(x, z)` (tuple from pydantic, list from BSON — both work)."""
    n = len(polygon)
    if n < 3:
        return False

    inside = False
    j = n - 1
    for i in range(n):
        xi, zi = polygon[i][0], polygon[i][1]
        xj, zj = polygon[j][0], polygon[j][1]
        if (zi > pz) != (zj > pz):
            if px < (xj - xi) * (pz - zi) / (zj - zi) + xi:
                inside = not inside
        j = i
    return inside


def rotated_footprint_corners(
    cx: float, cz: float, width_m: float, depth_m: float, yaw_rad: float
) -> list[tuple[float, float]]:
    """The 4 footprint corners of a `width × depth` box centred at `(cx, cz)` and
    rotated by `yaw_rad` around the y axis. Returned in CCW order on the xz plane."""
    half_w = width_m / 2
    half_d = depth_m / 2
    c, s = math.cos(yaw_rad), math.sin(yaw_rad)
    local = ((-half_w, -half_d), (half_w, -half_d), (half_w, half_d), (-half_w, half_d))
    return [(cx + lx * c - lz * s, cz + lx * s + lz * c) for lx, lz in local]


def boxes_overlap_xz(
    corners_a: Sequence[Sequence[float]],
    corners_b: Sequence[Sequence[float]],
) -> bool:
    """Separating-axis test for two convex 2D quads on the xz plane (used for
    OBB-OBB overlap of furniture footprints)."""
    for poly in (corners_a, corners_b):
        n = len(poly)
        for i in range(n):
            x1, z1 = poly[i][0], poly[i][1]
            x2, z2 = poly[(i + 1) % n][0], poly[(i + 1) % n][1]
            nx, nz = -(z2 - z1), x2 - x1   # edge normal
            a_proj = [px * nx + pz * nz for px, pz in corners_a]
            b_proj = [px * nx + pz * nz for px, pz in corners_b]
            if max(a_proj) < min(b_proj) or max(b_proj) < min(a_proj):
                return False
    return True


def is_upright(
    euler_angles: Sequence[float],
    tolerance_rad: float = _DEFAULT_UPRIGHT_TOLERANCE_RAD,
) -> bool:
    """Item is upright when pitch (x) and roll (z) are within `tolerance_rad`
    of zero. Yaw (rotation around the vertical axis) is unconstrained, so a
    chair rotated to face any direction is still upright."""
    pitch, _yaw, roll = euler_angles
    pitch = ((pitch + math.pi) % (2 * math.pi)) - math.pi
    roll = ((roll + math.pi) % (2 * math.pi)) - math.pi
    return abs(pitch) <= tolerance_rad and abs(roll) <= tolerance_rad


def opening_clearance_zone(
    opening: dict,
    wall: dict,
    floor_polygon: Sequence[Sequence[float]],
    clearance_m: float,
) -> list[tuple[float, float]] | None:
    """4 corners of the floor-plane clearance rectangle in front of an opening.

    The rectangle sits flush with the wall (its base edge spans the opening's
    width) and extends `clearance_m` inward into the room. Used to prevent
    furniture from being placed where it would block a door's swing path or an
    open passageway.

    Returns `None` when `clearance_m <= 0`, the wall geometry is degenerate, or
    the inward direction can't be determined (no candidate normal lands inside
    the floor polygon).
    """
    if clearance_m <= 0:
        return None

    cx, cz = opening["center"][0], opening["center"][2]
    width = float(opening["width"])

    sx, sz = wall["start"][0], wall["start"][1]
    ex, ez = wall["end"][0], wall["end"][1]
    dx, dz = ex - sx, ez - sz
    length = math.hypot(dx, dz)
    if length < 1e-9:
        return None
    tx, tz = dx / length, dz / length          # wall tangent
    nx, nz = -tz, tx                           # candidate normal

    if not point_in_polygon(cx + nx * _INWARD_PROBE_M, cz + nz * _INWARD_PROBE_M, floor_polygon):
        nx, nz = -nx, -nz
        if not point_in_polygon(cx + nx * _INWARD_PROBE_M, cz + nz * _INWARD_PROBE_M, floor_polygon):
            return None

    half_w = width / 2
    base_l = (cx - half_w * tx, cz - half_w * tz)
    base_r = (cx + half_w * tx, cz + half_w * tz)
    far_r = (base_r[0] + nx * clearance_m, base_r[1] + nz * clearance_m)
    far_l = (base_l[0] + nx * clearance_m, base_l[1] + nz * clearance_m)
    return [base_l, base_r, far_r, far_l]


def default_clearance_for(opening_type: str) -> float:
    """Default inward clearance depth for a door/opening/window type. Doors and
    open passageways block placements by default; windows do not."""
    if opening_type == "door":
        return _DEFAULT_DOOR_CLEARANCE_M
    if opening_type == "opening":
        return _DEFAULT_OPENING_CLEARANCE_M
    return _DEFAULT_WINDOW_CLEARANCE_M


def derive_floor_y(walls: Sequence[dict], default: float = 0.0) -> float:
    """Absolute floor y in ARKit world space, derived from wall geometry.

    RoomPlan walls span floor-to-ceiling, so the floor sits at the lowest wall
    bottom edge: `wall.center.y - wall.height / 2`. Returns `default` when no
    walls are present (common in test fixtures)."""
    if not walls:
        return default
    return min(w["center"][1] - w["height"] / 2 for w in walls)


def check_item_placement(
    item: PlacementBox,
    floor_polygon: Sequence[Sequence[float]],
    ceiling_height: float,
    floor_y: float = 0.0,
    other_items: Sequence[PlacementBox] = (),
    forbidden_zones: Sequence[tuple[str, Sequence[Sequence[float]]]] = (),
    upright_tolerance_rad: float = _DEFAULT_UPRIGHT_TOLERANCE_RAD,
    floor_tolerance_m: float = _DEFAULT_FLOOR_TOLERANCE_M,
) -> tuple[bool, str | None]:
    """Validate a furniture placement.

    Checks, in order: orientation is upright, xz footprint lies inside the floor
    polygon, vertical extents fit between floor and ceiling, no OBB overlap with
    `other_items`, no overlap with any `forbidden_zones` (e.g. door clearance
    rectangles). Each forbidden zone is a `(label, corners)` pair so the error
    message can name what was blocked. Returns `(True, None)` on success,
    `(False, message)` on the first failure.
    """
    if not is_upright(item.euler_angles, upright_tolerance_rad):
        pitch, _, roll = item.euler_angles
        return False, (
            f"Item is not upright (pitch={pitch:.3f}rad, roll={roll:.3f}rad); "
            f"max allowed deviation is {upright_tolerance_rad:.3f}rad"
        )

    px, py, pz = item.position[0], item.position[1], item.position[2]
    yaw = item.euler_angles[1]
    corners = rotated_footprint_corners(px, pz, item.width_m, item.depth_m, yaw)
    for cx, cz in corners:
        if not point_in_polygon(cx, cz, floor_polygon):
            return False, (
                f"Item footprint corner ({cx:.3f}, {cz:.3f}) lies outside the "
                "room floor polygon"
            )

    ceiling_y = floor_y + ceiling_height
    if py < floor_y - floor_tolerance_m:
        return False, f"Item base y={py:.3f} is below the floor at y={floor_y:.3f}"
    if py + item.height_m > ceiling_y + floor_tolerance_m:
        return False, (
            f"Item top y={py + item.height_m:.3f} exceeds the ceiling at y={ceiling_y:.3f}"
        )

    a_y0, a_y1 = py, py + item.height_m
    for other in other_items:
        b_y0 = other.position[1]
        b_y1 = b_y0 + other.height_m
        if a_y1 <= b_y0 or b_y1 <= a_y0:
            continue
        b_corners = rotated_footprint_corners(
            other.position[0], other.position[2],
            other.width_m, other.depth_m, other.euler_angles[1],
        )
        if boxes_overlap_xz(corners, b_corners):
            return False, "Item collides with an existing placed item"

    for label, zone in forbidden_zones:
        if boxes_overlap_xz(corners, zone):
            return False, f"Item blocks the clearance zone of {label}"

    return True, None
