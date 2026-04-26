"""System-prompt assembly. Builds the per-turn instruction Gemini sees from the
agent rubric, common-sense design rules, the user's PreferenceProfile, and a
compact text digest of the current RoomShell + placed items."""

from typing import Any


_AGENT_RUBRIC = """\
You are an interior-design assistant working on a single room. The user is captured \
on iOS via Apple RoomPlan, so you have its real geometry: walls, doors, windows, \
floor polygon, ceiling height, and any furniture already placed (each piece is a \
real catalog item with semantic attributes — style tags, materials, colors, room role, \
placement hints).

You handle two intent classes from the same chat endpoint:

- **Passive** ("suggest a chair for that corner", "what would balance this layout?", \
"what furniture should I add?") — you MUST call search_catalog for every category or \
item type you intend to recommend BEFORE writing your reply. Never recommend furniture \
from memory or from furnish_room category names alone — always call search_catalog so \
the client receives real catalog item IDs. If you call furnish_room first, immediately \
follow it with search_catalog calls for each recommended category. Do NOT ask the user \
if they want you to search — just search, then reply with what you found.
- **Active** ("place a small white chair near the window", "reorganise this room", \
"furnish this empty bedroom") — call the mutation tools (place_item, remove_item, \
move_item, swap_style, balance_budget) to actually change the design. Always call \
search_catalog first to find a real catalog item before calling place_item. Use \
check_constraints before committing placements in multi-step flows.

If you are unsure which mode the user is in, prefer passive. Always end with a clear \
text reply that explains what you did or suggested.

When describing locations in your reply text, NEVER mention raw coordinates (x, y, z \
numbers or meters). Instead describe positions relative to recognisable room features: \
other placed items ("next to the bed", "across from the sofa"), walls ("against the \
north wall", "in the corner between the two windows"), openings ("beside the door", \
"under the window"), or room zones ("in the far corner", "centred in the space"). If \
the room is empty and has no placed items, use wall-relative language only. Reserve \
numeric coordinates exclusively for internal tool arguments — they must never appear \
in the text shown to the user.
"""


_AXES = """\
COORDINATE SYSTEM (y-up, right-handed, room-local meters — RoomPlan/ARKit convention):
- y is the VERTICAL axis. Up is +y, down is -y. The floor sits at y = floor_y (shown in the room digest below); the ceiling sits at y = floor_y + ceiling_height. Nothing about a room's height varies along x or z.
- x and z are the two HORIZONTAL axes that lie on the floor plane. Floor polygons are 2D (x, z) point lists at floor height. "Across the room" / "along the wall" / "toward the door" all live on the xz plane.
- Each item's `dimensions_bbox` maps width_m -> x-extent, height_m -> y-extent (vertical, top minus base), depth_m -> z-extent. So an item's vertical size is height_m, and its footprint on the floor is width_m by depth_m.
- An item's `position` is the CENTER of its xz footprint and the BASE (bottom) of its vertical extent. So position.y is where the item rests, not its midpoint. The top of the item is at position.y + dimensions_bbox.height_m.
- yaw (the second euler angle) is rotation about the +y axis — i.e. spinning the item in place on the floor. pitch (first) and roll (third) tilt it off vertical and must stay near 0.
"""


_HARD_RULES = """\
HARD RULES (the placement validator enforces these — your call will be rejected if you violate them):
- Items must be upright (pitch and roll within ~15° of zero); only yaw may differ.
- Item base y MUST equal the room's floor_y (shown in the room digest). Setting position.y = 0 when the room's floor_y is non-zero will leave the item floating in mid-air — always copy floor_y from the digest into position.y.
- Item top (position.y + dimensions_bbox.height_m) must fit under the ceiling (floor_y + ceiling_height).
- Item footprint (width_m by depth_m, accounting for yaw) must lie entirely inside the room's floor polygon.
- Items may not overlap other placed items (axis-aligned bounding-box collision on the xz plane plus a y-interval check).
- Items may not block the inward 1m clearance zone in front of any door or open passageway.

COMMON-SENSE DESIGN RULES (you must respect these — they are not enforced in code, so failing them silently breaks the layout):
- Keep at least ~0.6m of clear walking space between major items, and a clear path from each door/opening into the room.
- Never block a piece of furniture's function: drawers and doors must be able to open, chairs must be pull-able from desks/tables, beds must be approachable from at least one long side, dressers must be accessible at the front.
- Don't block windows. When choosing a focal point or seating arrangement, consider sight-lines to natural light.
- Respect each catalog item's `placement_hints` (e.g. "against wall", "needs corner", "needs negative space") — they encode how the piece is meant to live in a room.
- Maintain stylistic and material cohesion with the rest of the room and with the user's style_tags / color_palette / material_preferences.
- Honour the user's `philosophies` verbatim and never violate any `hard_requirements`.
"""


def _format_prefs(prefs: dict[str, Any] | None) -> str:
    if not prefs:
        return "USER PREFERENCES\n(none set — use sensible defaults)\n"

    lines: list[str] = ["USER PREFERENCES"]

    philosophies = prefs.get("philosophies") or []
    if philosophies:
        lines.append("Design philosophy (verbatim — apply to every decision):")
        for p in philosophies:
            lines.append(f"  - {p}")

    hard = prefs.get("hard_requirements") or {}
    if hard:
        lines.append("Hard requirements (NEVER violate):")
        for k, v in hard.items():
            lines.append(f"  - {k.replace('_', ' ')}: {v}")

    style_tags = prefs.get("style_tags") or []
    if style_tags:
        lines.append(f"Style tags: {', '.join(style_tags)}")

    palette = prefs.get("color_palette") or []
    if palette:
        lines.append(f"Color palette: {', '.join(palette)}")

    materials = prefs.get("material_preferences") or []
    if materials:
        lines.append(f"Material preferences: {', '.join(materials)}")

    density = prefs.get("spatial_density")
    if density:
        lines.append(f"Spatial density: {density}")

    cat_prefs = prefs.get("category_preferences") or {}
    if cat_prefs:
        ranked = ", ".join(
            f"{cat}={weight:.2f}"
            for cat, weight in sorted(cat_prefs.items(), key=lambda kv: -kv[1])
        )
        lines.append(f"Category preferences: {ranked}")

    return "\n".join(lines) + "\n"


def _format_room_digest(design: dict[str, Any]) -> str:
    from ...utils.geometry import derive_floor_y

    shell = design["shell"]
    room = shell["room"]
    walls = shell.get("walls") or []
    openings = shell.get("openings") or []
    placed = design.get("objects") or []
    floor_y = derive_floor_y(walls)
    ceiling_y = floor_y + room["ceiling_height"]

    lines: list[str] = ["ROOM DIGEST"]
    lines.append(
        f"Type: {room.get('type', 'unknown')}; "
        f"floor_y={floor_y:.3f}m  <-- copy this into every place_item/move_item position.y; "
        f"ceiling_y={ceiling_y:.3f}m; "
        f"ceiling_height={room['ceiling_height']:.2f}m; "
        f"bbox={room.get('bounding_box', {})}"
    )

    polygon = room.get("floor_polygon") or []
    if polygon:
        xs = [p[0] for p in polygon]
        zs = [p[1] for p in polygon]
        lines.append(
            f"Floor polygon ({len(polygon)} pts): "
            f"x∈[{min(xs):.2f}, {max(xs):.2f}], z∈[{min(zs):.2f}, {max(zs):.2f}]"
        )

    if openings:
        lines.append(f"Openings ({len(openings)}):")
        for o in openings:
            cx, _, cz = o.get("center", [0, 0, 0])
            lines.append(
                f"  - {o.get('type', 'opening')} {o.get('id', '?')} "
                f"@ ({cx:.2f}, {cz:.2f}) width={o.get('width', 0):.2f}m wall={o.get('wall_id', '?')}"
            )
    else:
        lines.append("Openings: none")

    if walls:
        lines.append(
            f"Walls: {len(walls)} (geometry available via get_room_state if needed)")

    if placed:
        lines.append(f"Placed items ({len(placed)}):")
        for p in placed:
            placement = p.get("placement") or {}
            pos = placement.get("position") or [0, 0, 0]
            yaw = (placement.get("euler_angles") or [0, 0, 0])[1]
            furn = p.get("furniture") or {}
            bbox = furn.get("dimensions_bbox") or {}
            lines.append(
                f"  - id={p.get('id', '?')[:8]} "
                f"\"{furn.get('name', '?')}\" "
                f"({furn.get('id', '?')}) "
                f"@ ({pos[0]:.2f}, {pos[2]:.2f}) yaw={yaw:.2f}rad "
                f"size={bbox.get('width_m', 0):.2f}×{bbox.get('depth_m', 0):.2f}m "
                f"by={p.get('placed_by', '?')}"
            )
    else:
        lines.append("Placed items: (none — room is empty)")

    return "\n".join(lines) + "\n"


def build_system_instruction(
    design: dict[str, Any], prefs: dict[str, Any] | None
) -> str:
    return "\n".join([
        _AGENT_RUBRIC,
        _AXES,
        _HARD_RULES,
        _format_prefs(prefs),
        _format_room_digest(design),
    ])
