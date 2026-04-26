"""Sweep the commit threshold over the fixtures and tabulate trade-offs.

Manual sweep — not an optimizer. Prints a table of (threshold, top-1, false
white-box rate) so you can pick a value by eye and bake it into
`pipeline/decision.COMMIT_THRESHOLD`.

    python -m eval.tune_thresholds --fixtures eval/fixtures
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .run_eval import _discover_fixtures
from .runner import aggregate, evaluate_fixture, run_async


THRESHOLDS = [0.30, 0.35, 0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures", required=True)
    args = parser.parse_args()

    fixtures = _discover_fixtures(Path(args.fixtures))
    if not fixtures:
        print(f"no fixtures found under {args.fixtures}", file=sys.stderr)
        return 2

    print(f"{'threshold':>10s}  {'top1':>6s}  {'false_wb':>8s}  {'wb_correct':>10s}")
    for t in THRESHOLDS:
        results = []
        for f in fixtures:
            results.extend(run_async(evaluate_fixture(f, threshold=t)))
        m = aggregate(results)
        print(
            f"{t:>10.2f}  "
            f"{m['top1_accuracy']:>6.3f}  "
            f"{m['false_white_box_rate']:>8.3f}  "
            f"{m['white_box_correct']}/{m['white_box_total']:<10}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
