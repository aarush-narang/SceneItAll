from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

from .design import PlacedObject, Vec3


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


class Mutations(BaseModel):
    """Concrete changes the agent applied to the design during this turn.
    Empty when the turn was purely passive (recommendations only)."""

    placements_added: list[PlacedObject] = Field(default_factory=list)
    placements_removed: list[str] = Field(default_factory=list)        # instance ids
    placements_moved: list[PlacedObject] = Field(default_factory=list)


class Recommendation(BaseModel):
    """A passive suggestion the agent surfaced for the user to consider.
    `suggested_position` is populated when the agent has a specific spot in mind."""

    item_id: str
    name: str
    reason: str
    suggested_position: Vec3 | None = None


class ToolCallLog(BaseModel):
    tool: str
    args: dict[str, Any]
    result: dict[str, Any]
    ms: int


class AgentChatResponse(BaseModel):
    session_id: str
    assistant_text: str
    mutations: Mutations = Field(default_factory=Mutations)
    recommendations: list[Recommendation] = Field(default_factory=list)
    tool_calls: list[ToolCallLog] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
