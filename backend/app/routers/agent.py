from __future__ import annotations
from fastapi import APIRouter
from ..models.agent import AgentChatRequest, AgentChatResponse
from ..services.gemini import run_agent_chat

router = APIRouter(prefix="/agent", tags=["agent"])


@router.post("/chat", response_model=AgentChatResponse)
async def agent_chat(body: AgentChatRequest):
    return await run_agent_chat(body)
