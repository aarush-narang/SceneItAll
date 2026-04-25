"""Return the current user's PreferenceProfile (minus internal fields)."""

from typing import Any

from pydantic import BaseModel, Field

from ..context import AgentContext
from ..registry import register


class GetPreferencesInput(BaseModel):
    pass


class GetPreferencesOutput(BaseModel):
    style_tags: list[str] = Field(default_factory=list)
    color_palette: list[str] = Field(default_factory=list)
    material_preferences: list[str] = Field(default_factory=list)
    spatial_density: str | None = None
    philosophies: list[str] = Field(default_factory=list)
    hard_requirements: dict[str, Any] = Field(default_factory=dict)
    category_preferences: dict[str, float] = Field(default_factory=dict)


@register(
    name="get_preferences",
    description=(
        "Return the user's PreferenceProfile: style_tags, color_palette, "
        "material_preferences, spatial_density, philosophies (verbatim user "
        "values), hard_requirements (must never be violated), and "
        "category_preferences. Falls back to empty defaults if the user has "
        "no profile yet."
    ),
    input=GetPreferencesInput,
    output=GetPreferencesOutput,
    mutates=False,
    tier=1,
)
async def get_preferences(ctx: AgentContext, inp: GetPreferencesInput) -> GetPreferencesOutput:
    prefs = await ctx.load_preferences() or {}
    return GetPreferencesOutput(
        style_tags=prefs.get("style_tags", []) or [],
        color_palette=prefs.get("color_palette", []) or [],
        material_preferences=prefs.get("material_preferences", []) or [],
        spatial_density=prefs.get("spatial_density"),
        philosophies=prefs.get("philosophies", []) or [],
        hard_requirements=prefs.get("hard_requirements", {}) or {},
        category_preferences=prefs.get("category_preferences", {}) or {},
    )
