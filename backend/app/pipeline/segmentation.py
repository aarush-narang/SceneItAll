"""Foreground segmentation to close the domain gap with white-background catalog renders.

The catalog's CLIP visual embeddings come from 4-angle Blender renders of each
USDZ on a clean white background. ARKit crops have rooms behind them, which
shifts the CLIP feature distribution and hurts retrieval. We segment the
foreground out of each crop with `rembg` and composite onto a white background
to mimic the catalog distribution.

`segment_to_white_bg` is the public entry point. To swap in BiRefNet later,
re-implement only this function.

`rembg` and its ONNX model are heavy and lazy-loaded. The first call downloads
the model and is slow; subsequent calls reuse the in-process session.
"""
from __future__ import annotations

import threading

from PIL import Image

_session = None
_lock = threading.Lock()
_MIN_FOREGROUND_FRACTION = 0.02  # below this, treat segmentation as failed


def _get_session():
    global _session
    with _lock:
        if _session is None:
            from rembg import new_session
            _session = new_session("u2net")
    return _session


def segment_to_white_bg(crop: Image.Image) -> Image.Image:
    """Run rembg on `crop`, composite the foreground onto a white background.

    Returns the unsegmented crop on white if segmentation fails or produces a
    near-empty mask. Always returns an RGB PIL image suitable for CLIP encoding.
    """
    if crop.mode != "RGBA":
        rgba_input = crop.convert("RGBA")
    else:
        rgba_input = crop

    try:
        from rembg import remove
        cut = remove(rgba_input, session=_get_session())
    except Exception:
        return _composite_on_white(rgba_input)

    if cut.mode != "RGBA":
        cut = cut.convert("RGBA")

    alpha = cut.split()[-1]
    bbox = alpha.getbbox()
    if bbox is None:
        return _composite_on_white(rgba_input)

    fg_pixels = sum(1 for p in alpha.getdata() if p > 16)
    if fg_pixels / max(alpha.width * alpha.height, 1) < _MIN_FOREGROUND_FRACTION:
        return _composite_on_white(rgba_input)

    return _composite_on_white(cut)


def _composite_on_white(image: Image.Image) -> Image.Image:
    if image.mode != "RGBA":
        image = image.convert("RGBA")
    bg = Image.new("RGB", image.size, (255, 255, 255))
    bg.paste(image, mask=image.split()[-1])
    return bg
