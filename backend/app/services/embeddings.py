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


_CAPTION_PROMPT = (
    "You are matching a piece of furniture in a room scan against an IKEA catalog. "
    "Identify and describe ONLY the primary foreground furniture item in 1-2 sentences. "
    "State what type of furniture it is, then its primary material, color, leg style, "
    "back style, cushion presence, and any distinctive shape or structural features. "
    "Do not describe the background, room, or other furniture nearby. "
    "Output the description only."
)


def caption_image_gemini(
    image: Image.Image,
    model: str = "gemini-2.0-flash",
) -> str:
    """One-shot caption of a single furniture crop via Gemini Flash.

    Gemini freely identifies the furniture type from the image — RoomPlan's
    category label is intentionally not passed here so the embedding reflects
    what the camera actually saw, not what RoomPlan guessed.
    """
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

