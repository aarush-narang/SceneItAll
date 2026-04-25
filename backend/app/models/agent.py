from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel

from .design import Vec3


class ChatTurn(BaseModel):
    role: Literal["user", "assistant", "tool"]
    content: str
    tool_name: str | None = None
    tool_args: dict | None = None
    tool_result: dict | None = None
    ts: datetime


class ChatSession(BaseModel):
    id: str
    user_id: str
    design_id: str
    turns: list[ChatTurn]
    created_at: datetime


class AgentChatRequest(BaseModel):
    user_id: str
    design_id: str
    message: str
    session_id: str | None = None


class PlacementSuggestion(BaseModel):
    item_id: str       # references FurnitureItem.id
    position: Vec3     # room-local meters
    euler_angles: Vec3 # radians (x, y, z), SceneKit ZYX intrinsic order
    rationale: str


class AgentChatResponse(BaseModel):
    session_id: str
    assistant_text: str
    placements: list[PlacementSuggestion] = []
    tool_calls: list[dict[str, Any]] = []
