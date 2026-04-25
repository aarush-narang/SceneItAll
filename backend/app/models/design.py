from __future__ import annotations
from datetime import datetime
from typing import Literal
from pydantic import BaseModel, Field


class Vec3(BaseModel):
    x: float  # meters, room-local
    y: float
    z: float


class Quat(BaseModel):
    x: float
    y: float
    z: float
    w: float  # scalar component


class PlacedItem(BaseModel):
    instance_id: str                          # UUID — allows multiple copies of the same SKU in a room
    item_id: str                              # references FurnitureItem.id
    position: Vec3                            # placement position in meters, room-local space
    rotation: Quat                            # orientation quaternion
    placed_by: Literal["user", "agent"] = "user"  # whether the user or Gemini placed this item
    rationale: str | None = None              # one-sentence explanation from the agent; None for user-placed items


class RoomShell(BaseModel):
    usdz_url: str            # S3 URL to the CapturedRoom USDZ export from RoomPlan
    metadata_json_url: str   # S3 URL to RoomPlan JSON (walls, floor, ceiling, doors, windows)
    floor_polygon: list[Vec3]  # 2D footprint at y=0; used to validate that placements stay inside the room
    bbox_min: Vec3           # minimum corner of the room bounding box
    bbox_max: Vec3           # maximum corner; agent checks placed item height against bbox_max.y


class Design(BaseModel):
    id: str = Field(alias="_id")              # UUID
    user_id: str                              # device UUID of the owner
    name: str                                 # user-facing project name
    preference_profile_id: str | None = None  # linked PreferenceProfile; None if the user hasn't set one
    shell: RoomShell                          # the scanned room geometry
    placed_items: list[PlacedItem] = []       # all furniture currently in the room
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None        # set on soft-delete; None means active

    model_config = {"populate_by_name": True}


class DesignPublic(BaseModel):
    id: str
    user_id: str
    name: str
    preference_profile_id: str | None = None
    shell: RoomShell
    placed_items: list[PlacedItem] = []
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None

    @classmethod
    def from_doc(cls, doc: dict) -> "DesignPublic":
        doc = dict(doc)
        doc["id"] = doc.pop("_id", doc.get("id", ""))
        return cls(**doc)


class DesignCreateRequest(BaseModel):
    user_id: str
    name: str
    preference_profile_id: str | None = None
    shell: RoomShell


class DesignPatchRequest(BaseModel):
    name: str | None = None                       # rename the design
    preference_profile_id: str | None = None      # swap the linked preference profile
    add_items: list[PlacedItem] = []              # new items to place
    update_items: list[PlacedItem] = []           # existing items to move/rotate (matched by instance_id)
    delete_instance_ids: list[str] = []           # instance_ids to remove
