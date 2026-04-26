# Eval harness

Measures match quality against hand-labeled scans. The harness imports the
pipeline functions directly — it does **not** go through the FastAPI endpoint —
so it isolates matcher quality from request/upload behavior.

## Run

From the repo root with the conda env activated:

```bash
python -m eval.run_eval --fixtures eval/fixtures
python -m eval.run_eval --fixtures eval/fixtures/scan_001 --json out.json
python -m eval.tune_thresholds --fixtures eval/fixtures
```

## Metrics reported

| Metric | Meaning |
| --- | --- |
| `top1_accuracy` | `matched_product_id == expected_product_id` |
| `top5_accuracy` | `expected_product_id ∈ top-5 ranked candidates` (over non-null GTs only) |
| `category_accuracy` | refined category equals expected category |
| `white_box_correct` | matcher white-boxed when GT was null |
| `false_white_box_rate` | matcher white-boxed when GT had a real expected ID |

Plus a per-category top-1 breakdown.

## Adding fixtures

See `fixtures/README.md`. Target ~5–10 scans / ~50–100 objects.

## Threshold tuning

`tune_thresholds.py` sweeps `COMMIT_THRESHOLD` from 0.30 → 0.70. The output
table is meant to be eyeballed; pick a value and update
`backend/app/pipeline/decision.py`.
