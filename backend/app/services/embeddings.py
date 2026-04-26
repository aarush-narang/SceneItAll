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


_CAPTION_PROMPT = (
    "You are matching a piece of furniture in a room scan against an IKEA catalog. "
    "Describe ONLY the foreground furniture item in 1-2 sentences. "
    "Mention type, primary material, color, style, and any distinctive shape or features. "
    "Do not describe the background or surroundings. Output the description only."
)


def caption_image_gemini(image: Image.Image, model: str = "gemini-2.0-flash") -> str:
    """One-shot caption of a single image via Gemini Flash. Returns plain text
    suitable for embedding via `embed_text_gemini`. Caller should encode the
    image to JPEG/PNG bytes — Gemini handles either."""
    import io
    from google.genai import types

    client = _get_gemini()
    buf = io.BytesIO()
    image.convert("RGB").save(buf, format="JPEG", quality=88)
    image_part = types.Part.from_bytes(data=buf.getvalue(), mime_type="image/jpeg")

    response = client.models.generate_content(
        model=model,
        contents=[image_part, _CAPTION_PROMPT],
    )
    return (response.text or "").strip()

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
