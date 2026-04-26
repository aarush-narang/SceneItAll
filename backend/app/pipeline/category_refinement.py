"""Refine the RoomPlan category label using the consensus of top candidates.

If at least `MAJORITY_FRACTION` of the top-K candidates share a *catalog*
sub-category that differs from the RoomPlan label, surface that sub-category as
the refined label. v1 is informational only — the white-box label uses it and
it goes in the response, but no re-filter or re-rank is triggered.
"""
from __future__ import annotations

from collections import Counter

from .matching import Candidate

MAJORITY_FRACTION = 0.7


def refine_category(roomplan_category: str, candidates: list[Candidate]) -> str:
    """Return the refined category if the top candidates strongly cluster on a
    sub-category, otherwise the original RoomPlan label."""
    if not candidates:
        return roomplan_category

    sub_labels = [c.subcategory for c in candidates if c.subcategory]
    if not sub_labels:
        cat_labels = [c.category for c in candidates if c.category]
        if not cat_labels:
            return roomplan_category
        most_common, count = Counter(cat_labels).most_common(1)[0]
        if count / len(candidates) >= MAJORITY_FRACTION and most_common != roomplan_category:
            return most_common
        return roomplan_category

    most_common, count = Counter(sub_labels).most_common(1)[0]
    if count / len(candidates) >= MAJORITY_FRACTION:
        return most_common
    return roomplan_category
