"""Importing this package registers every tool. Order doesn't matter."""

from . import (  # noqa: F401  — import side effects register the tool
    balance_budget,
    check_constraints,
    find_empty_zones,
    furnish_room,
    get_preferences,
    get_room_state,
    move_item,
    place_item,
    remove_item,
    search_catalog,
    swap_style,
)
