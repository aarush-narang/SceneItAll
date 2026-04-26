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


_ANNOTATED_FRAME_PROMPT = (
    "You are matching a piece of furniture against an IKEA catalog. "
    "A bright red rectangle is drawn around the specific furniture item you should identify. "
    "Describe ONLY that highlighted object in 1-2 sentences. "
    "State what type of furniture it is (chair, sofa, dining table, coffee table, etc.), "
    "then its primary material, color, leg style, back style, cushion presence, "
    "and any distinctive shape or structural features. "
    "Ignore everything outside the red rectangle. Output the description only."
)

# Padding factor around the projected bbox when cropping the frame for context.
# 0.6 means 60% of the bbox dimensions added on each side.
_CONTEXT_PAD = 0.6


def caption_annotated_frame_gemini(
    frame: Image.Image,
    rect: tuple[float, float, float, float],
    model: str = "gemini-2.0-flash",
) -> str:
    """Caption a specific object in a camera frame by annotating it with a
    bounding box and asking Gemini to identify it in context.

    Sends a region-cropped version of the full frame (object + surrounding room
    context) with a red rectangle drawn around the exact object bbox. This
    gives Gemini full spatial context — neighbouring furniture, room type, scale
    — so it can distinguish a dining chair from a sofa even when both are in
    the same frame, rather than inferring from a de-backgrounded crop blob.
    """
    import io

    from PIL import ImageDraw
    from google.genai import types

    x, y, w, h = rect
    img_w, img_h = frame.size

    # Crop to object + generous context so Gemini sees the surroundings.
    pad_x = w * _CONTEXT_PAD
    pad_y = h * _CONTEXT_PAD
    x0 = max(0.0, x - pad_x)
    y0 = max(0.0, y - pad_y)
    x1 = min(float(img_w), x + w + pad_x)
    y1 = min(float(img_h), y + h + pad_y)

    region = frame.convert("RGB").crop((x0, y0, x1, y1))

    # Draw the bounding box in the cropped coordinate space.
    draw = ImageDraw.Draw(region)
    rx0, ry0 = x - x0, y - y0
    rx1, ry1 = rx0 + w, ry0 + h
    for offset in range(3):  # thick outline for visibility
        draw.rectangle(
            [rx0 - offset, ry0 - offset, rx1 + offset, ry1 + offset],
            outline=(255, 30, 30),
        )

    client = _get_gemini()
    buf = io.BytesIO()
    region.save(buf, format="JPEG", quality=88)
    image_part = types.Part.from_bytes(data=buf.getvalue(), mime_type="image/jpeg")

    response = client.models.generate_content(
        model=model,
        contents=[image_part, _ANNOTATED_FRAME_PROMPT],
    )
    return (response.text or "").strip()

