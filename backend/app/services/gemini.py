from __future__ import annotations
import json
import uuid
from datetime import datetime, timezone
from typing import Any

from google import genai
from google.genai import types

from ..config import settings
from ..db import designs_col, furniture_col, preferences_col, chat_sessions_col
from ..models.agent import AgentChatRequest, AgentChatResponse, PlacementSuggestion, ChatTurn
from ..models.design import Vec3, Quat, PlacedItem
from ..logging import log
from ..utils.geometry import point_in_polygon, check_item_fits_in_room
from .embeddings import embed_text

_TOOLS = types.Tool(
    function_declarations=[
        types.FunctionDeclaration(
            name="search_furniture",
            description="Search the furniture catalog by text query with optional filters.",
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    "query": types.Schema(type=types.Type.STRING),
                    "category": types.Schema(type=types.Type.STRING),
                    "max_price": types.Schema(type=types.Type.NUMBER),
                    "style_tags": types.Schema(
                        type=types.Type.ARRAY,
                        items=types.Schema(type=types.Type.STRING),
                    ),
                    "limit": types.Schema(type=types.Type.INTEGER),
                },
                required=["query"],
            ),
        ),
        types.FunctionDeclaration(
            name="get_room_state",
            description="Get the current state of a design room (bounding box and placed items).",
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={"design_id": types.Schema(type=types.Type.STRING)},
                required=["design_id"],
            ),
        ),
        types.FunctionDeclaration(
            name="place_item",
            description="Place a furniture item in a design room at a given position and rotation.",
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    "design_id": types.Schema(type=types.Type.STRING),
                    "item_id": types.Schema(type=types.Type.STRING),
                    "position": types.Schema(
                        type=types.Type.OBJECT,
                        properties={
                            "x": types.Schema(type=types.Type.NUMBER),
                            "y": types.Schema(type=types.Type.NUMBER),
                            "z": types.Schema(type=types.Type.NUMBER),
                        },
                        required=["x", "y", "z"],
                    ),
                    "rotation": types.Schema(
                        type=types.Type.OBJECT,
                        properties={
                            "x": types.Schema(type=types.Type.NUMBER),
                            "y": types.Schema(type=types.Type.NUMBER),
                            "z": types.Schema(type=types.Type.NUMBER),
                            "w": types.Schema(type=types.Type.NUMBER),
                        },
                        required=["x", "y", "z", "w"],
                    ),
                    "rationale": types.Schema(type=types.Type.STRING),
                },
                required=["design_id", "item_id", "position", "rotation"],
            ),
        ),
        types.FunctionDeclaration(
            name="get_preferences",
            description="Get the preference profile for a user.",
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={"user_id": types.Schema(type=types.Type.STRING)},
                required=["user_id"],
            ),
        ),
        types.FunctionDeclaration(
            name="suggest_alternatives",
            description="Find visually similar furniture items to a given item.",
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    "item_id": types.Schema(type=types.Type.STRING),
                    "max_price": types.Schema(type=types.Type.NUMBER),
                    "limit": types.Schema(type=types.Type.INTEGER),
                },
                required=["item_id"],
            ),
        ),
    ]
)

_SYSTEM_INSTRUCTION = (
    "You are an interior design assistant. Help the user furnish their room. "
    "When suggesting furniture placements always call place_item to persist them. "
    "Each placement must include a concise rationale. "
    "Validate coordinates fit inside the room before placing."
)


async def _search_furniture(args: dict) -> dict:
    query = args["query"]
    category = args.get("category")
    max_price = args.get("max_price")
    style_tags = args.get("style_tags", [])
    limit = int(args.get("limit", 5))

    text_vec = embed_text(query)
    pipeline: list[dict] = [
        {
            "$vectorSearch": {
                "index": "text_index",
                "path": "text_embedding",
                "queryVector": text_vec,
                "numCandidates": limit * 10,
                "limit": limit * 4,
            }
        }
    ]

    match: dict[str, Any] = {}
    if category:
        match["category"] = category
    if max_price is not None:
        match["price_usd"] = {"$lte": max_price}
    if style_tags:
        match["style_tags"] = {"$in": style_tags}
    if match:
        pipeline.append({"$match": match})
    pipeline.append({"$limit": limit})
    pipeline.append({"$project": {"visual_embedding": 0, "text_embedding": 0}})

    docs = await furniture_col().aggregate(pipeline).to_list(length=limit)
    for doc in docs:
        doc["id"] = doc.pop("_id", "")
    return {"results": docs}


async def _get_room_state(args: dict) -> dict:
    design_id = args["design_id"]
    doc = await designs_col().find_one({"_id": design_id, "deleted_at": None})
    if not doc:
        return {"error": f"Design {design_id} not found"}
    return {
        "bbox_min": doc["shell"]["bbox_min"],
        "bbox_max": doc["shell"]["bbox_max"],
        "floor_polygon": doc["shell"]["floor_polygon"],
        "placed_items": doc.get("placed_items", []),
    }


async def _place_item(args: dict) -> dict:
    design_id = args["design_id"]
    item_id = args["item_id"]
    pos = args["position"]
    rot = args["rotation"]
    rationale = args.get("rationale", "")

    design_doc = await designs_col().find_one({"_id": design_id, "deleted_at": None})
    if not design_doc:
        return {"error": f"Design {design_id} not found"}

    item_doc = await furniture_col().find_one({"_id": item_id})
    if not item_doc:
        return {"error": f"Furniture item {item_id} not found"}

    floor_polygon = design_doc["shell"]["floor_polygon"]
    bbox_max = design_doc["shell"]["bbox_max"]

    is_valid, error_msg = check_item_fits_in_room(
        position=pos,
        dimensions=item_doc["dimensions"],
        floor_polygon=floor_polygon,
        bbox_max=bbox_max,
    )
    if not is_valid:
        return {"error": error_msg}

    placed = PlacedItem(
        instance_id=str(uuid.uuid4()),
        item_id=item_id,
        position=Vec3(**pos),
        rotation=Quat(**rot),
        placed_by="agent",
        rationale=rationale,
    )
    await designs_col().update_one(
        {"_id": design_id},
        {
            "$push": {"placed_items": placed.model_dump()},
            "$set": {"updated_at": datetime.now(timezone.utc)},
        },
    )
    return {"success": True, "instance_id": placed.instance_id}


async def _get_preferences(args: dict) -> dict:
    user_id = args["user_id"]
    doc = await preferences_col().find_one({"user_id": user_id})
    if not doc:
        return {"error": f"No preference profile for user {user_id}"}
    # doc.pop("taste_vector", None)
    doc["id"] = doc.pop("_id", "")
    return doc


async def _suggest_alternatives(args: dict) -> dict:
    item_id = args["item_id"]
    max_price = args.get("max_price")
    limit = int(args.get("limit", 5))

    source = await furniture_col().find_one({"_id": item_id})
    if not source:
        return {"error": f"Item {item_id} not found"}

    visual_vec = source.get("visual_embedding")
    if not visual_vec:
        return {"error": "Source item has no visual embedding"}

    pipeline: list[dict] = [
        {
            "$vectorSearch": {
                "index": "visual_index",
                "path": "visual_embedding",
                "queryVector": visual_vec,
                "numCandidates": (limit + 1) * 10,
                "limit": (limit + 1) * 4,
            }
        },
        {"$match": {"_id": {"$ne": item_id}}},
    ]
    if max_price is not None:
        pipeline.append({"$match": {"price_usd": {"$lte": max_price}}})
    pipeline.append({"$limit": limit})
    pipeline.append({"$project": {"visual_embedding": 0, "text_embedding": 0}})

    docs = await furniture_col().aggregate(pipeline).to_list(length=limit)
    for doc in docs:
        doc["id"] = doc.pop("_id", "")
    return {"results": docs}


_TOOL_HANDLERS = {
    "search_furniture": _search_furniture,
    "get_room_state": _get_room_state,
    "place_item": _place_item,
    "get_preferences": _get_preferences,
    "suggest_alternatives": _suggest_alternatives,
}


async def run_agent_chat(req: AgentChatRequest) -> AgentChatResponse:
    client = genai.Client(api_key=settings.gemini_api_key)

    history: list[types.Content] = []
    if req.session_id:
        session_doc = await chat_sessions_col().find_one({"_id": req.session_id})
        if session_doc:
            for turn in session_doc.get("turns", []):
                role = "model" if turn["role"] == "assistant" else turn["role"]
                if role in ("user", "model"):
                    history.append(
                        types.Content(role=role, parts=[types.Part(text=turn["content"])])
                    )

    chat = client.aio.chats.create(
        model="gemini-2.0-flash",
        history=history,
        config=types.GenerateContentConfig(
            tools=[_TOOLS],
            system_instruction=_SYSTEM_INSTRUCTION,
        ),
    )

    tool_call_log: list[dict] = []
    placements: list[PlacementSuggestion] = []
    new_turns: list[ChatTurn] = [
        ChatTurn(role="user", content=req.message, ts=datetime.now(timezone.utc))
    ]

    response = await chat.send_message(req.message)

    while True:
        fn_calls = response.function_calls
        if not fn_calls:
            break

        fn_response_parts: list[types.Part] = []
        for fc in fn_calls:
            name = fc.name
            args = dict(fc.args)
            log.info("agent_tool_call", tool=name, args=args)

            handler = _TOOL_HANDLERS.get(name)
            if handler is None:
                result = {"error": f"Unknown tool {name}"}
            else:
                try:
                    result = await handler(args)
                except Exception as exc:
                    result = {"error": str(exc)}

            tool_call_log.append({"tool": name, "args": args, "result": result})
            fn_response_parts.append(
                types.Part(
                    function_response=types.FunctionResponse(name=name, response=result)
                )
            )

            if name == "place_item" and result.get("success"):
                placements.append(
                    PlacementSuggestion(
                        item_id=args["item_id"],
                        position=Vec3(**args["position"]),
                        rotation=Quat(**args["rotation"]),
                        rationale=args.get("rationale", ""),
                    )
                )

            new_turns.append(
                ChatTurn(
                    role="tool",
                    content=json.dumps(result),
                    tool_name=name,
                    tool_args=args,
                    tool_result=result,
                    ts=datetime.now(timezone.utc),
                )
            )

        response = await chat.send_message(fn_response_parts)

    assistant_text = response.text or ""
    new_turns.append(
        ChatTurn(role="assistant", content=assistant_text, ts=datetime.now(timezone.utc))
    )

    session_id = req.session_id or str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    await chat_sessions_col().update_one(
        {"_id": session_id},
        {
            "$setOnInsert": {"user_id": req.user_id, "design_id": req.design_id, "created_at": now},
            "$push": {"turns": {"$each": [t.model_dump() for t in new_turns]}},
        },
        upsert=True,
    )

    return AgentChatResponse(
        session_id=session_id,
        assistant_text=assistant_text,
        placements=placements,
        tool_calls=tool_call_log,
    )
