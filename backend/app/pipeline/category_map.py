"""RoomPlan → catalog category mapping.

Audited against the live `interior_design.furniture` collection: 7,950 docs,
case-inconsistent labels (`storage` 3105 + `Storage` 97, `sofa` 488 + `Sofa`
24, etc.), and `desk` is its own top-level category — not nested under `table`.
"""
from __future__ import annotations

CATEGORY_MAP: dict[str, set[str]] = {
    "sofa": {"sofa", "Sofa", "chaise"},
    "chair": {"chair", "stool", "ottoman", "bench"},
    "table": {"table", "desk", "Desk", "dining_set", "table_and_chair_set", "table_and_chairs_set"},
    "bed": {"bed", "Bed", "mattress", "headboard"},
    "storage": {"storage", "Storage", "cabinet", "cabinetry", "shelf"},
    "television": {"appliance", "Home electronics"},
    "refrigerator": {"appliance"},
    "stove": {"appliance"},
    "oven": {"appliance"},
    "dishwasher": {"appliance"},
    "washer_dryer": {"appliance"},
    "sink": {"vanity", "faucet"},
    "toilet": {"vanity"},
    "bathtub": {"vanity"},
    "fireplace": set(),  # no catalog match — will white-box
    "stairs": set(),     # no catalog match — will white-box
}


def catalog_categories_for(roomplan_category: str) -> list[str]:
    """Return the catalog categories to consider for a RoomPlan label.

    Returns an empty list when no catalog match exists for the RoomPlan
    category (e.g. fireplace, stairs); callers should treat this as "always
    white-box" without running a vector search."""
    mapped = CATEGORY_MAP.get(roomplan_category.lower())
    if mapped is None:
        return [roomplan_category.lower()]
    return sorted(mapped)
