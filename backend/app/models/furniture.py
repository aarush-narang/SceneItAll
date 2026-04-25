from __future__ import annotations
from pydantic import BaseModel, Field


class FurnitureSource(BaseModel):
    name: str
    url: str


class IkeaTaxonomy(BaseModel):
    category_leaf: str
    category_path: list[str] = Field(default_factory=list)
    segment: str
    top_department: str
    material: str | None = None
    color: str | None = None


class InferredTaxonomy(BaseModel):
    category: str
    subcategory: str


class PriceInfo(BaseModel):
    value: float
    currency: str


class RatingInfo(BaseModel):
    value: float
    count: int


class IkeaDimensions(BaseModel):
    width_in: float
    depth_in: float
    height_in: float


class BoundingBoxDimensions(BaseModel):
    width_m: float
    height_m: float
    depth_m: float


class FurnitureAttributes(BaseModel):
    style_tags: list[str] = Field(default_factory=list)
    design_lineage: str | None = None
    material_primary: str | None = None
    material_secondary: str | None = None
    texture_and_finish: str | None = None
    color_primary: str | None = None
    color_secondary: str | None = None
    era: str | None = None
    formality: str | None = None
    ambient_mood: list[str] = Field(default_factory=list)
    visual_weight: str | None = None
    scale: str | None = None
    room_role: str | None = None
    suitable_rooms: list[str] = Field(default_factory=list)
    placement_hints: list[str] = Field(default_factory=list)
    pairs_well_with: list[str] = Field(default_factory=list)
    use_scenarios: list[str] = Field(default_factory=list)
    space_requirements: str | None = None
    has_arms: bool | None = None
    has_legs: bool | None = None
    stackable: bool | None = None


class FurnitureFiles(BaseModel):
    usdz_url: str
    thumb_urls: list[str] = Field(default_factory=list)


class EmbeddingValue(BaseModel):
    vec: list[float] = Field(default_factory=list)
    model: str
    dim: int


class FurnitureEmbeddings(BaseModel):
    text: EmbeddingValue
    visual: EmbeddingValue


class FurnitureItem(BaseModel):
    id: str | None = Field(default=None, alias="_id")
    name: str
    family_key: str
    source: FurnitureSource
    taxonomy_ikea: IkeaTaxonomy
    taxonomy_inferred: InferredTaxonomy
    price: PriceInfo
    rating: RatingInfo
    dimensions_ikea: IkeaDimensions
    dimensions_bbox: BoundingBoxDimensions
    attributes: FurnitureAttributes
    design_summary: str
    description: str
    embedding_text: str
    embeddings: FurnitureEmbeddings
    files: FurnitureFiles

    model_config = {"populate_by_name": True}


class FurnitureItemPublic(FurnitureItem):
    """API-facing furniture document with `_id` normalized to `id`."""

    @classmethod
    def from_doc(cls, doc: dict) -> "FurnitureItemPublic":
        doc = dict(doc)
        doc["id"] = str(doc.pop("_id", doc.get("id", ""))) or None
        return cls(**doc)


class FurnitureSearchParams(BaseModel):
    q: str                        # free-text query, encoded via CLIP text encoder
    category: str | None = None   # optional category filter
    max_price: float | None = None
    limit: int = 10


class FurnitureSimilarParams(BaseModel):
    id: str                        # source item to find neighbors for
    max_price: float | None = None
    limit: int = 10
