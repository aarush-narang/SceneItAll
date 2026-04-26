"""CLIP-encode segmented crops and pool them into a per-object query embedding.

Reuses the same `open_clip` model that ingested the catalog (`ViT-B-32 / openai`,
configured in `app/config.py`). Embeddings are L2-normalized, mean-pooled across
the (up to 3) crops for an object, and L2-normalized again. Same space as the
catalog `embeddings.visual.vec` field — required for cosine vector search to
mean anything.
"""
from __future__ import annotations

import threading

import numpy as np
import torch
from PIL import Image

from ..config import settings

_lock = threading.Lock()
_model = None
_preprocess = None


def _load() -> None:
    """Load the CLIP model lazily; matches the catalog's encoder."""
    global _model, _preprocess
    with _lock:
        if _model is None:
            import open_clip
            _model, _, _preprocess = open_clip.create_model_and_transforms(
                settings.clip_model, pretrained=settings.clip_pretrained
            )
            _model.eval()


def embed_crop(image: Image.Image) -> np.ndarray:
    """Embed one PIL image with CLIP. Returns L2-normalized 1D float32 vector."""
    _load()
    img = _preprocess(image.convert("RGB")).unsqueeze(0)
    with torch.no_grad():
        vec = _model.encode_image(img)
        vec = vec / vec.norm(dim=-1, keepdim=True)
    return vec[0].cpu().numpy().astype(np.float32)


def embed_crops_mean(images: list[Image.Image]) -> np.ndarray | None:
    """Embed multiple crops, mean-pool, and L2-normalize the result.

    Returns None when `images` is empty so the caller can take the white-box
    branch. Robust to a single image (degenerates to plain `embed_crop`).
    """
    if not images:
        return None
    if len(images) == 1:
        return embed_crop(images[0])

    vecs = [embed_crop(img) for img in images]
    stacked = np.stack(vecs, axis=0)
    mean = stacked.mean(axis=0)
    norm = np.linalg.norm(mean)
    if norm < 1e-8:
        return None
    return (mean / norm).astype(np.float32)
