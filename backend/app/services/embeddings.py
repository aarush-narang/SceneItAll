from __future__ import annotations
import threading

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


_CAPTION_PROMPT_BASE = (
    "You are matching a piece of furniture in a room scan against an IKEA catalog. "
    "Describe ONLY the foreground furniture item in 1-2 sentences. "
    "Focus on primary material, color, leg style, back style, cushion presence, "
    "and any distinctive shape or structural features. "
    "Do not describe the background or surroundings. Output the description only."
)

_CAPTION_PROMPT_WITH_CATEGORY = (
    "You are matching a piece of furniture in a room scan against an IKEA catalog. "
    "RoomPlan has identified this object as a {category}. "
    "Describe ONLY the foreground {category} in 1-2 sentences. "
    "Focus on primary material, color, leg style, back style, cushion presence, "
    "and any distinctive shape or structural features that distinguish this specific {category}. "
    "Do not describe the background, surroundings, or other furniture nearby. "
    "Output the description only."
)


def caption_image_gemini(
    image: Image.Image,
    category: str | None = None,
    model: str = "gemini-2.0-flash",
) -> str:
    """One-shot caption of a single image via Gemini Flash.

    Pass `category` (the RoomPlan object category, e.g. "chair") to anchor
    the description to the correct furniture type — critical when the frame
    contains multiple furniture types in close proximity.
    """
    import io
    from google.genai import types

    if category:
        prompt = _CAPTION_PROMPT_WITH_CATEGORY.format(category=category)
    else:
        prompt = _CAPTION_PROMPT_BASE

    client = _get_gemini()
    buf = io.BytesIO()
    image.convert("RGB").save(buf, format="JPEG", quality=88)
    image_part = types.Part.from_bytes(data=buf.getvalue(), mime_type="image/jpeg")

    response = client.models.generate_content(
        model=model,
        contents=[image_part, prompt],
    )
    return (response.text or "").strip()

