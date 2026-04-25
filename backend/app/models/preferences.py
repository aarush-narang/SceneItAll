from __future__ import annotations
from typing import Any, Literal
from pydantic import BaseModel, Field


class PreferenceProfile(BaseModel):
    id: str = Field(alias="_id")                          # UUID for user profiles; e.g. "tpl_minimalist" for templates
    user_id: str | None = None                            # device UUID of the owner; None on seed templates
    is_template: bool = False                             # True for the 3 built-in seeds, False for real user profiles
    template_name: str | None = None                      # "minimalist" | "cozy" | "midcentury"; only set on templates
    style_tags: list[str]                                 # broad aesthetic labels e.g. ["modern", "clean"]; fed to Gemini
    color_palette: list[str]                              # hex codes e.g. ["#FFFFFF"]; Gemini avoids clashing suggestions
    material_preferences: list[str]                       # e.g. ["wood", "metal"]; weights furniture suggestions
    spatial_density: Literal["sparse", "balanced", "dense"]  # how full the agent tries to make the room
    philosophies: list[str]                               # short sentences injected verbatim into Gemini's system prompt
    hard_requirements: dict[str, Any]                     # strict filters e.g. {"max_price_per_item": 500}; agent must never violate
    # taste_vector: list[float] | None = None               # 512-d mean of visual embeddings of liked/placed items; None until first design is completed

    model_config = {"populate_by_name": True}


class PreferenceProfilePublic(BaseModel):
    id: str
    user_id: str | None = None
    is_template: bool = False
    template_name: str | None = None
    style_tags: list[str]
    color_palette: list[str]
    material_preferences: list[str]
    spatial_density: Literal["sparse", "balanced", "dense"]
    philosophies: list[str]
    hard_requirements: dict[str, Any]
    # taste_vector: list[float] | None = None

    @classmethod
    def from_doc(cls, doc: dict) -> "PreferenceProfilePublic":
        doc = dict(doc)
        doc["id"] = str(doc.pop("_id", doc.get("id", "")))
        return cls(**doc)


class PreferenceProfileUpsert(BaseModel):
    style_tags: list[str]
    color_palette: list[str]
    material_preferences: list[str]
    spatial_density: Literal["sparse", "balanced", "dense"]
    philosophies: list[str]
    hard_requirements: dict[str, Any] = {}
    # taste_vector: list[float] | None = None
