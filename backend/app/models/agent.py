from __future__ import annotations
from datetime import datetime
from typing import Any, Literal
from pydantic import BaseModel
from .design import Vec3, Quat


class ChatTurn(BaseModel):
    role: Literal["user", "assistant", "tool"]  # who produced this turn
    content: str                                 # text content of the turn
    tool_name: str | None = None                 # name of the tool called, if role == "tool"
    tool_args: dict | None = None                # arguments passed to the tool
    tool_result: dict | None = None              # structured result returned by the tool
    ts: datetime                                 # timestamp of the turn


class ChatSession(BaseModel):
    id: str          # UUID
    user_id: str     # device UUID of the owner
    design_id: str   # the design this session is scoped to
    turns: list[ChatTurn]
    created_at: datetime


class AgentChatRequest(BaseModel):
    user_id: str                   # device UUID; passed to get_preferences tool
    design_id: str                 # which room the agent is working on
    message: str                   # the user's natural language message
    session_id: str | None = None  # resume an existing session; None starts a new one


class PlacementSuggestion(BaseModel):
    item_id: str      # references FurnitureItem.id
    position: Vec3    # suggested position in room-local meters
    rotation: Quat    # suggested orientation
    rationale: str    # one-sentence explanation of why the agent chose this item and position


class AgentChatResponse(BaseModel):
    session_id: str                          # echoed or newly created session ID
    assistant_text: str                      # Gemini's conversational reply
    placements: list[PlacementSuggestion] = []  # furniture the agent wants to place; empty if none suggested
    tool_calls: list[dict[str, Any]] = []    # raw tool call log for debugging
