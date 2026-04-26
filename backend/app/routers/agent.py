from fastapi import APIRouter, HTTPException

from ..db import chat_sessions_col
from ..models.agent import AgentChatRequest, AgentChatResponse, ChatSession
from ..services.agent import run_agent_chat

router = APIRouter(prefix="/agent", tags=["agent"])


@router.post("/chat", response_model=AgentChatResponse)
async def agent_chat(body: AgentChatRequest):
    return await run_agent_chat(body)


@router.get("/sessions", response_model=ChatSession)
async def get_session_by_design(design_id: str):
    doc = await chat_sessions_col().find_one(
        {"design_id": design_id},
        sort=[("created_at", -1)],
    )
    if not doc:
        raise HTTPException(status_code=404, detail="No session for design")
    doc["id"] = doc.pop("_id")
    return doc


@router.delete("/sessions/{session_id}/messages", status_code=204)
async def clear_session_messages(session_id: str):
    result = await chat_sessions_col().update_one(
        {"_id": session_id},
        {"$set": {"turns": []}},
    )
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Session not found")
    return None
