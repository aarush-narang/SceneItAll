"""Crop selected frames to the projected object rect with a small margin."""
from __future__ import annotations

from PIL import Image

DEFAULT_MARGIN_FRACTION = 0.08


def crop_with_margin(
    image: Image.Image,
    rect: tuple[float, float, float, float],
    margin_fraction: float = DEFAULT_MARGIN_FRACTION,
) -> Image.Image:
    """Crop `image` to `rect` expanded by `margin_fraction` and clipped to bounds.

    `rect` is `(x, y, w, h)` in pixel space. The expansion grows the rect on
    every side by `margin_fraction * max(w, h)` so a value of 0.08 gives roughly
    8% extra context, which empirically helps CLIP separate a piece of furniture
    from its visual surroundings.
    """
    x, y, w, h = rect
    if w <= 0 or h <= 0:
        raise ValueError(f"non-positive crop rect: {rect}")

    margin = margin_fraction * max(w, h)
    x0 = max(0, int(x - margin))
    y0 = max(0, int(y - margin))
    x1 = min(image.width, int(x + w + margin))
    y1 = min(image.height, int(y + h + margin))

    if x1 <= x0 or y1 <= y0:
        raise ValueError(f"crop collapsed after clipping: {(x0, y0, x1, y1)}")

    return image.crop((x0, y0, x1, y1))
