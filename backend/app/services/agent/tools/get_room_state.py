"""Return the full RoomShell + placed items for the design in context.

Mostly redundant with the room digest in the system prompt — the agent uses
this when it needs fresh state mid-conversation (e.g. after a sequence of
mutations) or wants the raw geometry of walls/openings.
"""

from typing import Any

from pydantic import BaseModel, Field

from ..context import AgentContext
from ..registry import register


class PlacedItemSummary(BaseModel):
    id: str
    catalog_id: str
    name: str
    position: tuple[float, float, float]
    euler_angles: tuple[float, float, float]
    width_m: float | None = None
    height_m: float | None = None
    depth_m: float | None = None
    placed_by: str = "user"
    rationale: str | None = None
    style_tags: list[str] = Field(default_factory=list)
    room_role: str | None = None


class GetRoomStateInput(BaseModel):
    pass


class GetRoomStateOutput(BaseModel):
    room_id: str
    room_type: str | None = None
    ceiling_height: float
    bounding_box: dict[str, float]
    floor_polygon: list[list[float]]
    walls: list[dict[str, Any]] = Field(default_factory=list)
    openings: list[dict[str, Any]] = Field(default_factory=list)
    placed_items: list[PlacedItemSummary] = Field(default_factory=list)


def _summarise_placed(doc: dict[str, Any]) -> PlacedItemSummary:
    placement = doc.get("placement") or {}
    furn = doc.get("furniture") or {}
    bbox = furn.get("dimensions_bbox") or {}
    return PlacedItemSummary(
        id=doc.get("id", ""),
        catalog_id=furn.get("id") or furn.get("_id", ""),
        name=furn.get("name", ""),
        position=tuple(placement.get("position") or (0, 0, 0)),
        euler_angles=tuple(placement.get("euler_angles") or (0, 0, 0)),
        width_m=bbox.get("width_m"),
        height_m=bbox.get("height_m"),
        depth_m=bbox.get("depth_m"),
        placed_by=doc.get("placed_by", "user"),
        rationale=doc.get("rationale"),
    )


@register(
    name="get_room_state",
    description=(
        "Return the current RoomShell (room metadata, walls, openings, floor "
        "polygon, ceiling height) and every placed_item in the design. Use this "
        "when you need fresh state — e.g. after placing/moving items in this "
        "turn — or when you need the raw geometry of walls and openings."
    ),
    input=GetRoomStateInput,
    output=GetRoomStateOutput,
    mutates=False,
    tier=1,
)
async def get_room_state(ctx: AgentContext, inp: GetRoomStateInput) -> GetRoomStateOutput:
    design = await ctx.load_design()
    shell = design["shell"]
    room = shell["room"]
    return GetRoomStateOutput(
        room_id=room.get("id", ""),
        room_type=room.get("type"),
        ceiling_height=room["ceiling_height"],
        bounding_box=room.get("bounding_box", {}),
        floor_polygon=[list(p) for p in room.get("floor_polygon", [])],
        walls=shell.get("walls") or [],
        openings=shell.get("openings") or [],
        placed_items=[_summarise_placed(p) for p in design.get("placed_items", [])],
    )
