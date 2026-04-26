"""Decide whether to commit the top-1 match or fall back to a white-box.

Demo mode: always commit if there are any candidates. Score thresholds and
category-ambiguity bailouts are kept as constants so we can re-enable them
later by setting `ALWAYS_COMMIT = False`."""
from __future__ import annotations

from dataclasses import dataclass

from .matching import Candidate

COMMIT_THRESHOLD = 0.45                 # tune via eval/tune_thresholds.py
CATEGORY_AMBIGUITY_FRACTION = 0.4       # if fewer than this share the top category, bail out
ALWAYS_COMMIT = True                    # demo mode: ignore both thresholds, take top-1


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

    The only true white-box paths are now:
        * No usable embedding (the iPad never got a clear view of the object).
        * Vector search returned zero candidates after the category/dim filter.
    Score and category-ambiguity bailouts are skipped while `ALWAYS_COMMIT` is
    True; the diagnostics are still recorded in the returned MatchDecision so
    `scan.match` log line stays informative."""
    if not had_usable_embedding:
        return MatchDecision(None, "no_usable_embedding", 0.0, 0.0)

    if not candidates:
        return MatchDecision(None, "no_candidates_after_filter", 0.0, 0.0)

    top = candidates[0]
    top_cat = top.category
    same_cat = sum(1 for c in candidates if c.category == top_cat)
    consistency = same_cat / len(candidates)

    if ALWAYS_COMMIT:
        return MatchDecision(top, "committed_demo", top.combined_score, consistency)

    if top.combined_score < threshold:
        return MatchDecision(None, "score_below_threshold", top.combined_score, consistency)

    if consistency < CATEGORY_AMBIGUITY_FRACTION:
        return MatchDecision(None, "category_ambiguous", top.combined_score, consistency)

    return MatchDecision(top, "committed", top.combined_score, consistency)
