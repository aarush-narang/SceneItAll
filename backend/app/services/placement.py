"""Shared placement validator used by both the designs router and the agent's
mutation tools. Single source of truth for what "a valid placement" means."""

from typing import Iterable

from ..db import furniture_col
from ..models.design import PlacedObject
from ..utils.geometry import (
    PlacementBox,
    check_item_placement,
    default_clearance_for,
    derive_floor_y,
    opening_clearance_zone,
)


def _placement_box_from_model(item: PlacedObject) -> PlacementBox:
    bbox = item.furniture.dimensions_bbox
    return PlacementBox(
        position=tuple(item.placement.position),
        euler_angles=tuple(item.placement.euler_angles),
        width_m=bbox.width_m,
        height_m=bbox.height_m,
        depth_m=bbox.depth_m,
    )


def _placement_box_from_doc(doc: dict) -> PlacementBox | None:
    placement = doc.get("placement") or {}
    bbox = (doc.get("furniture") or {}).get("dimensions_bbox") or {}
    pos = placement.get("position")
    if not pos or not bbox:
        return None
    return PlacementBox(
        position=tuple(pos),
        euler_angles=tuple(placement.get("euler_angles", (0.0, 0.0, 0.0))),
        width_m=bbox["width_m"],
        height_m=bbox["height_m"],
        depth_m=bbox["depth_m"],
    )


def _forbidden_zones_for(shell: dict) -> list[tuple[str, list[tuple[float, float]]]]:
    """Compute clearance rectangles for each door/opening on the shell. Returns
    `(label, corners)` pairs ready to feed into `check_item_placement`."""
    walls_by_id = {w["id"]: w for w in shell.get("walls") or []}
    floor_polygon = shell["room"]["floor_polygon"]
    zones: list[tuple[str, list[tuple[float, float]]]] = []
    for opening in shell.get("openings") or []:
        clearance = default_clearance_for(opening.get("type", ""))
        if clearance <= 0:
            continue
        wall = walls_by_id.get(opening.get("wall_id"))
        if not wall:
            continue
        corners = opening_clearance_zone(opening, wall, floor_polygon, clearance)
        if corners is None:
            continue
        label = f"{opening.get('type', 'opening')} {opening.get('id', '?')}"
        zones.append((label, corners))
    return zones


def _other_items(
    placed_items: Iterable[dict], exclude_id: str | None
) -> list[PlacementBox]:
    out: list[PlacementBox] = []
    for o in placed_items:
        if exclude_id is not None and o.get("id") == exclude_id:
            continue
        box = _placement_box_from_doc(o)
        if box is not None:
            out.append(box)
    return out


async def validate_placement(
    item: PlacedObject,
    design_doc: dict,
) -> tuple[bool, str | None]:
    """Validate a `PlacedObject` against a stored design document.

    Checks:
    1. The catalog item referenced by `item.furniture.id` exists.
    2. Geometry: upright, inside floor polygon, fits under ceiling, no collision
       with other placed items (excluding the one being updated, matched by
       `item.id`), no intrusion into door/opening clearance zones.

    Returns `(True, None)` on success, `(False, message)` on the first failure.
    Pure data — never raises HTTPException; callers translate as needed.
    """
    catalog_id = item.furniture.id
    if not await furniture_col().count_documents({"_id": catalog_id}, limit=1):
        return False, f"Furniture item {catalog_id} not found"

    shell = design_doc["shell"]
    room = shell["room"]
    floor_y = derive_floor_y(shell.get("walls") or [])
    others = _other_items(design_doc.get("placed_items") or [], exclude_id=item.id)
    forbidden = _forbidden_zones_for(shell)

    return check_item_placement(
        _placement_box_from_model(item),
        floor_polygon=room["floor_polygon"],
        ceiling_height=room["ceiling_height"],
        floor_y=floor_y,
        other_items=others,
        forbidden_zones=forbidden,
    )
