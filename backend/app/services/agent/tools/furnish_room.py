"""Plan a furnishing strategy for the current room.

Read-only advisory tool. Returns a recommended set of furniture categories
(driven by room type + size), and the current free zones on the floor. The
agent then drives the actual furnishing by calling `search_catalog` →
`check_constraints` → `place_item` per category.
"""

from pydantic import BaseModel, Field

from ..context import AgentContext
from ..registry import register
from .find_empty_zones import (
    FindEmptyZonesInput,
    FindEmptyZonesOutput,
    find_empty_zones,
)


# Hand-picked starter sets per room type. Each entry is (category, role, why).
_FURNISHING_TEMPLATES: dict[str, list[tuple[str, str, str]]] = {
    "bedroom": [
        ("bed", "anchor", "centerpiece; biggest item, dictates the layout"),
        ("nightstand", "secondary", "flanks the bed for lamp / clock / phone"),
        ("dresser", "secondary", "bulk clothing storage; goes against a wall"),
        ("chair", "accent", "reading or dressing corner; near a window if possible"),
        ("rug", "accent", "anchors the bed visually; defines walking zones"),
    ],
    "livingRoom": [
        ("sofa", "anchor", "primary seating; faces the focal point (TV / fireplace)"),
        ("coffee table", "secondary", "in front of the sofa, ~45cm clearance"),
        ("armchair", "secondary", "L-shaped or perpendicular to the sofa"),
        ("side table", "accent", "beside seating for drinks / lamp"),
        ("rug", "accent", "defines the conversation area"),
    ],
    "diningRoom": [
        ("dining table", "anchor", "centred in the room"),
        ("dining chair", "secondary", "matched count to the table seats"),
        ("buffet", "accent", "against a long wall for serving / storage"),
    ],
    "kitchen": [
        ("bar stool", "secondary", "at the island / counter overhang"),
        ("dining chair", "accent", "small breakfast nook if space allows"),
    ],
    "office": [
        ("desk", "anchor", "facing the window or opposite the door"),
        ("office chair", "secondary", "behind the desk; pull-out clearance"),
        ("bookshelf", "secondary", "wall-mounted; balances the desk"),
    ],
}

_DEFAULT_TEMPLATE = [
    ("table", "anchor", "central piece"),
    ("chair", "secondary", "seating around or near the table"),
    ("lamp", "accent", "task or ambient lighting"),
]


class CategoryRecommendation(BaseModel):
    category: str
    role: str = Field(description="`anchor`, `secondary`, or `accent`.")
    reason: str


class FurnishRoomInput(BaseModel):
    style_hint: str | None = Field(
        default=None,
        description="Optional style descriptor passed through when the agent searches the catalog.",
    )
    probe_width_m: float = Field(default=1.0, gt=0)
    probe_depth_m: float = Field(default=1.0, gt=0)
    zone_limit: int = Field(default=12, ge=1, le=40)


class FurnishRoomOutput(BaseModel):
    room_type: str
    floor_area_m2: float
    recommended_categories: list[CategoryRecommendation]
    empty_zones: list[tuple[float, float]]
    guidance: str


def _polygon_area(polygon: list) -> float:
    """Shoelace on the (x, z) polygon."""
    n = len(polygon)
    if n < 3:
        return 0.0
    total = 0.0
    for i in range(n):
        x1, z1 = polygon[i][0], polygon[i][1]
        x2, z2 = polygon[(i + 1) % n][0], polygon[(i + 1) % n][1]
        total += x1 * z2 - x2 * z1
    return abs(total) / 2


@register(
    name="furnish_room",
    description=(
        "Return a plan for furnishing the current room from scratch: a curated "
        "list of furniture categories appropriate for the room type, plus the "
        "current empty floor zones where things could go. This is advisory — "
        "the agent should follow up with `search_catalog` to pick concrete "
        "items per category and `place_item` (with `check_constraints`) to put "
        "them in."
    ),
    input=FurnishRoomInput,
    output=FurnishRoomOutput,
    mutates=False,
    tier=3,
)
async def furnish_room(ctx: AgentContext, inp: FurnishRoomInput) -> FurnishRoomOutput:
    design = await ctx.load_design()
    room = design["shell"]["room"]
    room_type = room.get("type") or "room"
    polygon = room.get("floor_polygon") or []
    area = _polygon_area(polygon)

    template = _FURNISHING_TEMPLATES.get(room_type, _DEFAULT_TEMPLATE)
    recommendations = [
        CategoryRecommendation(category=c, role=r, reason=why) for c, r, why in template
    ]

    zones_out: FindEmptyZonesOutput = await find_empty_zones(
        ctx,
        FindEmptyZonesInput(
            probe_width_m=inp.probe_width_m,
            probe_depth_m=inp.probe_depth_m,
            limit=inp.zone_limit,
        ),
    )

    style_phrase = f" with a {inp.style_hint} feel" if inp.style_hint else ""
    guidance = (
        f"Furnish this {room_type}{style_phrase} starting with the anchor "
        "category, then secondaries, then accents. Use search_catalog with the "
        "category and any style filter, then check_constraints at a candidate "
        "from `empty_zones` before calling place_item. Respect the user's "
        "philosophies and hard requirements at every step."
    )

    return FurnishRoomOutput(
        room_type=room_type,
        floor_area_m2=area,
        recommended_categories=recommendations,
        empty_zones=[(z.x, z.z) for z in zones_out.zones],
        guidance=guidance,
    )
