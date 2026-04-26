# Eval fixtures

Each fixture is a folder named `scan_<id>/` containing:

```
scan_<id>/
  scan.json              # the RoomPlan JSON the iOS app would POST as `scan_json`
  frames_metadata.json   # array of FrameMetadata, matches the multipart `frames_metadata` part
  frames/                # one JPEG per sampled frame, named `frame_<id>.jpg`
  ground_truth.json      # array of {detected_id, expected_product_id, expected_category}
```

`expected_product_id: null` means "no good match exists in the catalog — the
matcher should white-box this object." The eval harness counts those as
positive cases for "white-box correctness."

## Adding a fixture

1. Capture a scan with the iOS app pointed at a local backend in *capture
   mode* (not actual matching). Tee the multipart upload to disk before it
   hits the matcher — the parts map 1:1 to files above.
2. Hand-label `ground_truth.json`. Browse the catalog
   (`furniture` collection) and pick the closest IKEA SKU per object. Use
   `null` when nothing in the catalog is reasonable.
3. Run `python -m eval.run_eval --fixtures eval/fixtures/scan_<id>` to verify.

## Goal

5–10 fixtures, ~50–100 total objects. Cover: every RoomPlan category we care
about, at least one all-white-box scan, at least one scan with multiple
instances of the same SKU.
