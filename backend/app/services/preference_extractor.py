from __future__ import annotations
from ..db import furniture_col
from ..models.design import Design


async def extract_from_design(design: Design) -> dict:
    """Derive preference signals from a completed design's placed items.

    Returns a partial PreferenceProfile dict (style_tags, color_palette,
    material_preferences) by aggregating the placed items'
    catalog metadata and visual embeddings.
    """
    if not design.objects:
        return {}

    item_ids = [pi.furniture.id for pi in design.objects]
    col = furniture_col()
    docs = await col.find({"_id": {"$in": item_ids}}).to_list(length=None)

    if not docs:
        return {}

    style_counter: dict[str, int] = {}
    color_counter: dict[str, int] = {}
    material_counter: dict[str, int] = {}

    for doc in docs:
        attributes = doc.get("attributes", {})
        taxonomy_ikea = doc.get("taxonomy_ikea", {})

        for tag in attributes.get("style_tags", []):
            style_counter[tag] = style_counter.get(tag, 0) + 1

        colors = [
            attributes.get("color_primary"),
            attributes.get("color_secondary"),
            taxonomy_ikea.get("color"),
        ]
        for color in colors:
            if color:
                color_counter[color] = color_counter.get(color, 0) + 1

        materials = [
            attributes.get("material_primary"),
            attributes.get("material_secondary"),
            taxonomy_ikea.get("material"),
        ]
        for material in materials:
            if material:
                material_counter[material] = material_counter.get(
                    material, 0) + 1

    def top(counter: dict[str, int], n: int = 5) -> list[str]:
        return [k for k, _ in sorted(counter.items(), key=lambda x: -x[1])[:n]]

    # taste_vector computation disabled — back-burner feature
    # if embeddings:
    #     dim = len(embeddings[0])
    #     mean = [statistics.mean(e[i] for e in embeddings) for i in range(dim)]
    #     norm = sum(v * v for v in mean) ** 0.5 or 1.0
    #     taste_vector = [v / norm for v in mean]

    return {
        "style_tags": top(style_counter),
        "color_palette": top(color_counter, 6),
        "material_preferences": top(material_counter),
    }
