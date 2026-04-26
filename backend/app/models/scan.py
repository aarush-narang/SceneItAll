from __future__ import annotations

from pydantic import BaseModel, Field


class FrameMetadata(BaseModel):
    """Camera frame captured during the RoomPlan scan session."""

    frame_id: str
    timestamp: float
    image_filename: str
    camera_transform: list[list[float]] = Field(
        description="4x4 world-space camera transform, row-major"
    )
    camera_intrinsics: list[list[float]] = Field(
        description="3x3 camera intrinsics matrix, row-major"
    )
    image_width: int
    image_height: int


class DetectedObject(BaseModel):
    """A furniture object detected by RoomPlan with bounding box and category."""

    identifier: str
    category: str
    dimensions: tuple[float, float, float] = Field(
        description="(width, height, depth) in meters"
    )
    transform: list[float] = Field(
        description="4x4 column-major transform (16 floats)"
    )
    confidence: str = "high"
    object_frame_ids: list[str] = Field(
        default_factory=list,
        description="Frame IDs captured specifically for this object. "
                    "When non-empty the pipeline uses only these frames "
                    "instead of searching the full general frame pool.",
    )


class ScanPayload(BaseModel):
    """Top-level scan JSON sent by the iOS client (RoomPlan export + detected objects)."""

    identifier: str
    story: int = 0
    version: int = 2
    walls: list[dict] = Field(default_factory=list)
    doors: list[dict] = Field(default_factory=list)
    windows: list[dict] = Field(default_factory=list)
    openings: list[dict] = Field(default_factory=list)
    floors: list[dict] = Field(default_factory=list)
    sections: list[dict] = Field(default_factory=list)
    detected_objects: list[DetectedObject] = Field(
        default_factory=list,
        alias="detectedObjects",
    )

    model_config = {"populate_by_name": True}


class ObjectTransform(BaseModel):
    position: tuple[float, float, float]
    rotation_euler: tuple[float, float, float]
    scale: tuple[float, float, float] = (1.0, 1.0, 1.0)


class OriginalBBox(BaseModel):
    dimensions: tuple[float, float, float]
    transform: list[float]


class MatchedObject(BaseModel):
    """Per-object result returned by the matching pipeline."""

    detected_id: str
    matched_product_id: str | None = None
    matched_product_name: str | None = None
    matched_usdz_url: str | None = None
    refined_category: str
    transform: ObjectTransform
    original_bbox: OriginalBBox


class ScanResponse(BaseModel):
    scan_id: str
    room: dict = Field(description="Pass-through room geometry")
    objects: list[MatchedObject]
