"""Decide whether to commit the top-1 match or fall back to a white-box."""
from __future__ import annotations

from dataclasses import dataclass

from .category_map import catalog_categories_for
from .matching import Candidate

COMMIT_THRESHOLD = 0.45                 # tune via eval/tune_thresholds.py
CATEGORY_AMBIGUITY_FRACTION = 0.4       # if fewer than this share the top category, bail out
ALWAYS_COMMIT = True                    # demo mode: skip score/ambiguity thresholds, take top-1

# The minimum combined score below which we white-box even in ALWAYS_COMMIT mode.
# Protects against committing catalog items that are completely wrong
# (e.g. a table matched to a sofa because both are brown).
HARD_FLOOR_SCORE = 0.10


@dataclass(frozen=True)
class MatchDecision:
    """Result of the commit/white-box decision plus diagnostics for logging."""

    matched: Candidate | None
    reason: str
    top_score: float
    category_consistency: float


def _is_category_match(roomplan_category: str, candidate_category: str) -> bool:
    """Return True if the candidate's catalog category is in the expected set
    for the RoomPlan label. Used as a hard guard even in demo mode."""
    expected = set(catalog_categories_for(roomplan_category))
    return not expected or candidate_category in expected


def decide(
    candidates: list[Candidate],
    had_usable_embedding: bool,
    roomplan_category: str = "",
    threshold: float = COMMIT_THRESHOLD,
) -> MatchDecision:
    """Return a `MatchDecision`. `matched is None` means render a white-box.

    White-box paths:
        * No usable embedding (the device never got a clear view).
        * Zero candidates after the category/dim filter.
        * Top score is below HARD_FLOOR_SCORE (even in ALWAYS_COMMIT mode).
        * Top candidate's category doesn't match the RoomPlan label (even in
          ALWAYS_COMMIT mode) — prevents a chair filter leak returning sofas.
    Score and ambiguity thresholds are skipped while ALWAYS_COMMIT is True;
    diagnostics are still recorded so logs stay informative."""
    if not had_usable_embedding:
        return MatchDecision(None, "no_usable_embedding", 0.0, 0.0)

    if not candidates:
        return MatchDecision(None, "no_candidates_after_filter", 0.0, 0.0)

    top = candidates[0]
    top_cat = top.category
    same_cat = sum(1 for c in candidates if c.category == top_cat)
    consistency = same_cat / len(candidates)

    # Hard guards that apply even in demo mode.
    if top.combined_score < HARD_FLOOR_SCORE:
        return MatchDecision(None, "score_below_hard_floor", top.combined_score, consistency)

    if roomplan_category and not _is_category_match(roomplan_category, top.category):
        return MatchDecision(
            None, "category_mismatch", top.combined_score, consistency
        )

    if ALWAYS_COMMIT:
        return MatchDecision(top, "committed_demo", top.combined_score, consistency)

    if top.combined_score < threshold:
        return MatchDecision(None, "score_below_threshold", top.combined_score, consistency)

    if consistency < CATEGORY_AMBIGUITY_FRACTION:
        return MatchDecision(None, "category_ambiguous", top.combined_score, consistency)

    return MatchDecision(top, "committed", top.combined_score, consistency)
