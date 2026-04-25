"""Grid-sample the floor and return positions where a probe-sized item would
fit without colliding with walls, existing furniture, or door/opening
clearance zones. Used by the agent for "where could a chair go?" reasoning."""

from pydantic import BaseModel, Field

from ....utils.geometry import (
    boxes_overlap_xz,
    default_clearance_for,
    opening_clearance_zone,
    point_in_polygon,
    rotated_footprint_corners,
)
from ..context import AgentContext
from ..registry import register


class EmptyZone(BaseModel):
    x: float
    z: float


class FindEmptyZonesInput(BaseModel):
    probe_width_m: float = Field(
        default=1.0, gt=0, description="Width of the probe box in meters (xz plane)."
    )
    probe_depth_m: float = Field(
        default=1.0, gt=0, description="Depth of the probe box in meters (xz plane)."
    )
    grid_spacing_m: float = Field(
        default=0.5, gt=0, description="Grid sampling resolution in meters."
    )
    limit: int = Field(default=20, ge=1, le=100)


class FindEmptyZonesOutput(BaseModel):
    zones: list[EmptyZone]


@register(
    name="find_empty_zones",
    description=(
        "Return up to `limit` (x, z) centre points on the floor where a probe-"
        "sized axis-aligned box would fit (footprint inside the polygon, no "
        "overlap with placed items, no overlap with door/opening clearance "
        "zones). Use this to find candidate placement spots before calling "
        "place_item or check_constraints."
    ),
    input=FindEmptyZonesInput,
    output=FindEmptyZonesOutput,
    mutates=False,
    tier=2,
)
async def find_empty_zones(
    ctx: AgentContext, inp: FindEmptyZonesInput
) -> FindEmptyZonesOutput:
    design = await ctx.load_design()
    shell = design["shell"]
    polygon = shell["room"]["floor_polygon"]

    other_corners: list[list[tuple[float, float]]] = []
    for o in design.get("placed_items", []):
        placement = o.get("placement") or {}
        bbox = (o.get("furniture") or {}).get("dimensions_bbox") or {}
        pos = placement.get("position")
        if not pos or not bbox:
            continue
        yaw = (placement.get("euler_angles") or [0.0, 0.0, 0.0])[1]
        other_corners.append(
            rotated_footprint_corners(
                pos[0], pos[2], bbox["width_m"], bbox["depth_m"], yaw
            )
        )

    walls_by_id = {w["id"]: w for w in shell.get("walls") or []}
    forbidden_zones: list[list[tuple[float, float]]] = []
    for opening in shell.get("openings") or []:
        clearance = default_clearance_for(opening.get("type", ""))
        if clearance <= 0:
            continue
        wall = walls_by_id.get(opening.get("wall_id"))
        if not wall:
            continue
        zone = opening_clearance_zone(opening, wall, polygon, clearance)
        if zone is not None:
            forbidden_zones.append(zone)

    xs = [p[0] for p in polygon]
    zs = [p[1] for p in polygon]
    if not xs:
        return FindEmptyZonesOutput(zones=[])
    min_x, max_x = min(xs), max(xs)
    min_z, max_z = min(zs), max(zs)

    zones: list[EmptyZone] = []
    x = min_x + inp.probe_width_m / 2
    while x <= max_x - inp.probe_width_m / 2 + 1e-9 and len(zones) < inp.limit:
        z = min_z + inp.probe_depth_m / 2
        while z <= max_z - inp.probe_depth_m / 2 + 1e-9 and len(zones) < inp.limit:
            corners = rotated_footprint_corners(
                x, z, inp.probe_width_m, inp.probe_depth_m, 0.0
            )
            inside = all(point_in_polygon(cx, cz, polygon) for cx, cz in corners)
            if inside:
                clear_of_items = not any(
                    boxes_overlap_xz(corners, oc) for oc in other_corners
                )
                clear_of_zones = not any(
                    boxes_overlap_xz(corners, fz) for fz in forbidden_zones
                )
                if clear_of_items and clear_of_zones:
                    zones.append(EmptyZone(x=x, z=z))
            z += inp.grid_spacing_m
        x += inp.grid_spacing_m

    return FindEmptyZonesOutput(zones=zones)
