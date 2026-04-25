from __future__ import annotations
import threading
from pathlib import Path
from PIL import Image
import torch
import open_clip
from google import genai
from ..config import settings

_gemini_client: genai.Client | None = None
_gemini_lock = threading.Lock()


def _get_gemini() -> genai.Client:
    global _gemini_client
    with _gemini_lock:
        if _gemini_client is None:
            _gemini_client = genai.Client(api_key=settings.gemini_api_key)
    return _gemini_client


def embed_text_gemini(text: str) -> list[float]:
    """768-d text embedding via gemini-embedding-001 (matches DB index)."""
    from google.genai import types
    client = _get_gemini()
    result = client.models.embed_content(
        model="gemini-embedding-001",
        contents=text,
        config=types.EmbedContentConfig(output_dimensionality=768),
    )
    return result.embeddings[0].values

_lock = threading.Lock()
_model = None
_preprocess = None
_tokenizer = None


def _load() -> None:
    global _model, _preprocess, _tokenizer
    with _lock:
        if _model is None:
            _model, _, _preprocess = open_clip.create_model_and_transforms(
                settings.clip_model, pretrained=settings.clip_pretrained
            )
            _tokenizer = open_clip.get_tokenizer(settings.clip_model)
            _model.eval()


def embed_text(text: str) -> list[float]:
    _load()
    tokens = _tokenizer([text])
    with torch.no_grad():
        vec = _model.encode_text(tokens)
        vec = vec / vec.norm(dim=-1, keepdim=True)
    return vec[0].tolist()


def embed_image(image_path: str | Path) -> list[float]:
    _load()
    img = _preprocess(Image.open(image_path).convert("RGB")).unsqueeze(0)
    with torch.no_grad():
        vec = _model.encode_image(img)
        vec = vec / vec.norm(dim=-1, keepdim=True)
    return vec[0].tolist()


def embed_images_mean(image_paths: list[str | Path]) -> list[float]:
    """Return the mean of CLIP image embeddings for multiple renders."""
    _load()
    tensors = []
    for p in image_paths:
        img = _preprocess(Image.open(p).convert("RGB")).unsqueeze(0)
        with torch.no_grad():
            vec = _model.encode_image(img)
            vec = vec / vec.norm(dim=-1, keepdim=True)
        tensors.append(vec)
    mean = torch.stack(tensors).mean(dim=0)
    mean = mean / mean.norm(dim=-1, keepdim=True)
    return mean[0].tolist()
