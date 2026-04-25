"""Run the matching pipeline against fixtures and report metrics.

Usage:
    python -m eval.run_eval --fixtures eval/fixtures
    python -m eval.run_eval --fixtures eval/fixtures/scan_001 --json out.json
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path

from app.pipeline.decision import COMMIT_THRESHOLD

from .runner import aggregate, evaluate_fixture, run_async


def _discover_fixtures(root: Path) -> list[Path]:
    if (root / "scan.json").exists():
        return [root]
    return sorted(p for p in root.iterdir() if p.is_dir() and (p / "scan.json").exists())


def _print_table(title: str, metrics: dict) -> None:
    print(f"\n=== {title} ===")
    for k in (
        "total",
        "top1_accuracy",
        "top5_accuracy",
        "category_accuracy",
        "white_box_correct",
        "white_box_total",
        "false_white_box_rate",
    ):
        v = metrics.get(k)
        if isinstance(v, float):
            print(f"  {k:24s} {v:.3f}")
        else:
            print(f"  {k:24s} {v}")
    by_cat = metrics.get("per_category") or {}
    if by_cat:
        print("  per_category:")
        for cat, b in sorted(by_cat.items()):
            acc = b["top1"] / b["total"] if b["total"] else 0.0
            print(f"    {cat:20s} {b['top1']}/{b['total']}  ({acc:.2f})")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures", required=True, help="Path to a fixture or fixtures directory")
    parser.add_argument("--threshold", type=float, default=COMMIT_THRESHOLD)
    parser.add_argument("--json", help="Optional path to dump per-object results as JSON")
    args = parser.parse_args()

    fixtures = _discover_fixtures(Path(args.fixtures))
    if not fixtures:
        print(f"no fixtures found under {args.fixtures}", file=sys.stderr)
        return 2

    all_results = []
    for f in fixtures:
        print(f"running {f.name} ...")
        results = run_async(evaluate_fixture(f, threshold=args.threshold))
        metrics = aggregate(results)
        _print_table(f.name, metrics)
        all_results.extend(results)

    if len(fixtures) > 1:
        _print_table("OVERALL", aggregate(all_results))

    if args.json:
        Path(args.json).write_text(
            json.dumps([asdict(r) for r in all_results], indent=2)
        )
        print(f"\nwrote {args.json}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
