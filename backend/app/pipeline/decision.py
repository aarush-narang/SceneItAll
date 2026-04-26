"""Decide whether to commit the top-1 match or fall back to a white-box.

The embedding (CLIP + Gemini) is treated as ground truth for what the object IS.
RoomPlan's category label is not used here — it is only trusted for 3D geometry.
"""
from __future__ import annotations

from dataclasses import dataclass

from .matching import Candidate

COMMIT_THRESHOLD = 0.45                 # tune via eval/tune_thresholds.py
CATEGORY_AMBIGUITY_FRACTION = 0.4       # if fewer than this share the top category, bail out
ALWAYS_COMMIT = True                    # demo mode: skip score/ambiguity thresholds, take top-1

# Hard floor applied even in ALWAYS_COMMIT mode — below this score the
# embedding had no real signal and committing would just be noise.
HARD_FLOOR_SCORE = 0.10


@dataclass(frozen=True)
class MatchDecision:
    """Result of the commit/white-box decision plus diagnostics for logging."""

    matched: Candidate | None
    reason: str
    top_score: float
    category_consistency: float


def decide(
    candidates: list[Candidate],
    had_usable_embedding: bool,
    threshold: float = COMMIT_THRESHOLD,
) -> MatchDecision:
    """Return a `MatchDecision`. `matched is None` means render a white-box.

    White-box paths:
        * No usable embedding (device never got a clear view of the object).
        * Zero candidates returned by vector search.
        * Top combined score below HARD_FLOOR_SCORE.
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

    if top.combined_score < HARD_FLOOR_SCORE:
        return MatchDecision(None, "score_below_hard_floor", top.combined_score, consistency)

    if ALWAYS_COMMIT:
        return MatchDecision(top, "committed_demo", top.combined_score, consistency)

    if top.combined_score < threshold:
        return MatchDecision(None, "score_below_threshold", top.combined_score, consistency)

    if consistency < CATEGORY_AMBIGUITY_FRACTION:
        return MatchDecision(None, "category_ambiguous", top.combined_score, consistency)

    return MatchDecision(top, "committed", top.combined_score, consistency)
