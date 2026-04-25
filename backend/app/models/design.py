from datetime import datetime
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field


# RoomPlan / SceneKit ship 3D vectors as plain JSON arrays. Tuples enforce length
# at parse time and round-trip cleanly through MongoDB.
Vec3 = tuple[float, float, float]   # (x, y, z), meters
Vec2 = tuple[float, float]          # (x, z) on the floor plane (y = 0)


class FurnitureBoundingBox(BaseModel):
    width_m: float
    height_m: float
    depth_m: float


class FurnitureFiles(BaseModel):
    usdz_url: str


class FurnitureSnapshot(BaseModel):
    """Catalog snapshot embedded in a placement so the iOS client can render
    without re-fetching catalog rows. `id` references the full FurnitureItem."""

    model_config = ConfigDict(populate_by_name=True)

    id: str = Field(alias="_id")
    name: str
    family_key: str | None = None
    dimensions_bbox: FurnitureBoundingBox
    files: FurnitureFiles


class Placement(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    position: Vec3
    euler_angles: Vec3 = Field(alias="eulerAngles")  # radians, SceneKit ZYX intrinsic order
    scale: Vec3 = (1.0, 1.0, 1.0)


class PlacedObject(BaseModel):
    """A single piece of furniture placed in the design. `id` is a per-instance
    UUID — it allows multiple copies of the same SKU in one room."""

    model_config = ConfigDict(populate_by_name=True)

    id: str
    furniture: FurnitureSnapshot
    placement: Placement
    added_at: datetime = Field(alias="addedAt")
    placed_by: Literal["user", "agent"] = "user"
    rationale: str | None = None  # populated when placed_by == "agent"


class Wall(BaseModel):
    """`start`/`end` are the wall's footprint endpoints on the xz plane;
    `center` is the 3D midpoint of the wall surface."""

    model_config = ConfigDict(populate_by_name=True)

    id: str
    center: Vec3
    start: Vec2
    end: Vec2
    width: float
    height: float
    rotation_radians: float = Field(alias="rotationRadians")
    confidence: float


class Opening(BaseModel):
    """A door, window, or open passageway. `bottom_height` is the sill height
    above the floor; `is_open` is only set on doors."""

    model_config = ConfigDict(populate_by_name=True)

    id: str
    type: Literal["door", "window", "opening"]
    wall_id: str = Field(alias="wallID")
    center: Vec3
    width: float
    height: float
    bottom_height: float = Field(alias="bottomHeight")
    rotation_radians: float = Field(alias="rotationRadians")
    confidence: float
    is_open: bool | None = Field(default=None, alias="isOpen")


class RoomBoundingBox(BaseModel):
    width: float   # x extent
    depth: float   # z extent


class Room(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str
    type: str                                       # "bedroom", "livingRoom", "kitchen", ...
    story: int = 0
    ceiling_height: float = Field(alias="ceilingHeight")
    bounding_box: RoomBoundingBox = Field(alias="boundingBox")
    floor_polygon: list[Vec2] = Field(alias="floorPolygon")


class CaptureMetadata(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    generated_at: datetime = Field(alias="generatedAt")
    source_version: int = Field(alias="sourceVersion")


class RoomShell(BaseModel):
    """Static room geometry from a single RoomPlan capture. Combined with
    `Design.objects`, this is the full scene the iOS client renders."""

    model_config = ConfigDict(populate_by_name=True)

    schema_version: str = Field(default="1.0", alias="schemaVersion")
    units: Literal["meters"] = "meters"
    metadata: CaptureMetadata
    room: Room
    walls: list[Wall] = Field(default_factory=list)
    openings: list[Opening] = Field(default_factory=list)


class Design(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str = Field(alias="_id")
    user_id: str
    name: str
    preference_profile_id: str | None = None
    shell: RoomShell
    objects: list[PlacedObject] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None


class DesignPublic(BaseModel):
    """API-facing design document with `_id` normalised to `id`."""

    id: str
    user_id: str
    name: str
    preference_profile_id: str | None = None
    shell: RoomShell
    objects: list[PlacedObject] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None

    @classmethod
    def from_doc(cls, doc: dict) -> "DesignPublic":
        doc = dict(doc)
        doc["id"] = doc.pop("_id", doc.get("id", ""))
        return cls(**doc)


class DesignCreateRequest(BaseModel):
    """Payload for POST /designs. `shell` + `objects` are the raw RoomPlan capture."""

    user_id: str
    name: str
    preference_profile_id: str | None = None
    shell: RoomShell
    objects: list[PlacedObject] = Field(default_factory=list)


class DesignPatchRequest(BaseModel):
    name: str | None = None
    preference_profile_id: str | None = None
    add_items: list[PlacedObject] = Field(default_factory=list)
    update_items: list[PlacedObject] = Field(default_factory=list)
    delete_instance_ids: list[str] = Field(default_factory=list)
