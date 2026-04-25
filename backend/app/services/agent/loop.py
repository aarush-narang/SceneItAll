"""The agent run loop. One `run_agent_chat` call = one user turn:

1. Build `AgentContext` and lazy-load design + prefs once.
2. Assemble the system instruction (rubric + rules + prefs + room digest).
3. Run a bounded tool-calling loop against `gemini-2.5-flash`.
4. Aggregate mutation outputs, recommendation outputs, and a tool-call log.
5. Persist the new chat turns to `chat_sessions`.
6. Return the structured `AgentChatResponse`.
"""

import json
import time
import uuid
from datetime import datetime, timezone
from typing import Any

from google import genai
from google.genai import types

from ...config import settings
from ...db import chat_sessions_col
from ...logging import log
from ...models.agent import (
    AgentChatRequest,
    AgentChatResponse,
    ChatTurn,
    Mutations,
    Recommendation,
    ToolCallLog,
)
from ...models.design import PlacedObject
from .context import AgentContext
from .prompt import build_system_instruction
from .registry import dispatch, function_declarations


_MODEL_ID = "gemini-2.5-flash"
_MAX_TOOL_ROUND_TRIPS = 8


def _coerce_placed(doc: dict[str, Any]) -> PlacedObject | None:
    try:
        return PlacedObject.model_validate(doc)
    except Exception:
        return None


def _extract_mutations(name: str, result: dict[str, Any], mutations: Mutations) -> None:
    if name == "place_item":
        placed = _coerce_placed(result.get("placed") or {})
        if placed is not None:
            mutations.placements_added.append(placed)
    elif name == "remove_item":
        if result.get("removed") and result.get("instance_id"):
            mutations.placements_removed.append(result["instance_id"])
    elif name == "move_item":
        placed = _coerce_placed(result.get("placed") or {})
        if placed is not None:
            mutations.placements_moved.append(placed)
    elif name in ("swap_style", "balance_budget"):
        for s in result.get("swapped", []) or []:
            placed = _coerce_placed(s)
            if placed is not None:
                mutations.placements_moved.append(placed)


def _extract_recommendations(name: str, result: dict[str, Any]) -> list[Recommendation]:
    if name != "search_catalog":
        return []
    out: list[Recommendation] = []
    for r in result.get("results", []) or []:
        item_id = r.get("id")
        if not item_id:
            continue
        out.append(
            Recommendation(
                item_id=item_id,
                name=r.get("name", ""),
                reason=r.get("design_summary") or "",
            )
        )
    return out


def _dedupe_recommendations(recs: list[Recommendation]) -> list[Recommendation]:
    seen: set[str] = set()
    out: list[Recommendation] = []
    for r in recs:
        if r.item_id in seen:
            continue
        seen.add(r.item_id)
        out.append(r)
    return out


async def _load_history(session_id: str) -> list[types.Content]:
    session_doc = await chat_sessions_col().find_one({"_id": session_id})
    if not session_doc:
        return []
    history: list[types.Content] = []
    for turn in session_doc.get("turns", []) or []:
        role = "model" if turn.get("role") == "assistant" else turn.get("role")
        if role in ("user", "model"):
            history.append(
                types.Content(role=role, parts=[types.Part(text=turn.get("content", ""))])
            )
    return history


async def run_agent_chat(req: AgentChatRequest) -> AgentChatResponse:
    session_id = req.session_id or str(uuid.uuid4())
    ctx = AgentContext(
        user_id=req.user_id, design_id=req.design_id, session_id=session_id
    )

    design = await ctx.load_design()
    prefs = await ctx.load_preferences()
    system_instruction = build_system_instruction(design, prefs)
    tools_block = types.Tool(function_declarations=function_declarations())

    history = await _load_history(req.session_id) if req.session_id else []

    client = genai.Client(api_key=settings.gemini_api_key)
    chat = client.aio.chats.create(
        model=_MODEL_ID,
        history=history,
        config=types.GenerateContentConfig(
            tools=[tools_block],
            system_instruction=system_instruction,
        ),
    )

    tool_calls: list[ToolCallLog] = []
    mutations = Mutations()
    recommendations: list[Recommendation] = []
    warnings: list[str] = []
    new_turns: list[ChatTurn] = [
        ChatTurn(role="user", content=req.message, ts=datetime.now(timezone.utc))
    ]

    response = await chat.send_message(req.message)

    for _ in range(_MAX_TOOL_ROUND_TRIPS):
        fn_calls = response.function_calls
        if not fn_calls:
            break

        fn_response_parts: list[types.Part] = []
        for fc in fn_calls:
            name = fc.name
            args = dict(fc.args or {})
            log.info("agent_tool_call", tool=name, args=args)

            t0 = time.perf_counter()
            result = await dispatch(name, args, ctx)
            ms = int((time.perf_counter() - t0) * 1000)

            tool_calls.append(
                ToolCallLog(tool=name, args=args, result=result, ms=ms)
            )

            if isinstance(result, dict) and "error" in result:
                warnings.append(f"{name}: {result['error']}")
            else:
                _extract_mutations(name, result, mutations)
                recommendations.extend(_extract_recommendations(name, result))

            fn_response_parts.append(
                types.Part(
                    function_response=types.FunctionResponse(name=name, response=result)
                )
            )
            new_turns.append(
                ChatTurn(
                    role="tool",
                    content=json.dumps(result, default=str),
                    tool_name=name,
                    tool_args=args,
                    tool_result=result,
                    ts=datetime.now(timezone.utc),
                )
            )

        response = await chat.send_message(fn_response_parts)

    assistant_text = response.text or ""
    new_turns.append(
        ChatTurn(
            role="assistant", content=assistant_text, ts=datetime.now(timezone.utc)
        )
    )

    now = datetime.now(timezone.utc)
    await chat_sessions_col().update_one(
        {"_id": session_id},
        {
            "$setOnInsert": {
                "user_id": req.user_id,
                "design_id": req.design_id,
                "created_at": now,
            },
            "$push": {"turns": {"$each": [t.model_dump() for t in new_turns]}},
        },
        upsert=True,
    )

    return AgentChatResponse(
        session_id=session_id,
        assistant_text=assistant_text,
        mutations=mutations,
        recommendations=_dedupe_recommendations(recommendations),
        tool_calls=tool_calls,
        warnings=warnings,
    )
