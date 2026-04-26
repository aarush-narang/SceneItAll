"""Integration test: active agent turn that places an item.

Gemini is stubbed to issue one `place_item` call against a real catalog id and
a known-valid pose, then return a text confirmation. Assertions:

- `mutations.placements_added` contains the new PlacedObject
- The design's `objects` array got the $push in Mongo
- The catalog id matches
"""

from datetime import datetime, timezone
from uuid import uuid4

import pytest

import app.services.agent.loop as loop_module
from app.db import designs_col
from app.models.agent import AgentChatRequest
from app.services.agent.loop import run_agent_chat

from _fake_genai import FakeFunctionCall, FakeResponse, fake_client_factory


KNOWN_FURNITURE_ID = "00069768"


def _empty_bedroom_doc(*, design_id: str, user_id: str) -> dict:
    now = datetime.now(timezone.utc)
    return {
        "_id": design_id,
        "user_id": user_id,
        "name": "Active Test",
        "preference_profile_id": None,
        "shell": {
            "schema_version": "1.0",
            "units": "meters",
            "metadata": {"generated_at": now, "source_version": 2},
            "room": {
                "id": "test-room",
                "type": "bedroom",
                "story": 0,
                "ceiling_height": 3.0,
                "bounding_box": {"width": 5.0, "depth": 4.0},
                "floor_polygon": [[0.0, 0.0], [5.0, 0.0], [5.0, 4.0], [0.0, 4.0]],
            },
            "walls": [],
            "openings": [],
        },
        "objects": [],
        "created_at": now,
        "updated_at": now,
        "deleted_at": None,
    }


@pytest.mark.anyio
async def test_active_place_item_persists_and_reports(monkeypatch):
    user_id = str(uuid4())
    design_id = str(uuid4())
    db = designs_col()

    await db.insert_one(_empty_bedroom_doc(design_id=design_id, user_id=user_id))
    try:
        scripted = [
            FakeResponse(function_calls=[
                FakeFunctionCall("place_item", {
                    "catalog_id": KNOWN_FURNITURE_ID,
                    "position": [2.5, 0.0, 2.0],
                    "euler_angles": [0.0, 0.0, 0.0],
                    "rationale": "Anchors the room.",
                }),
            ]),
            FakeResponse(function_calls=[], text="Done — I placed it in the centre of the room."),
        ]
        monkeypatch.setattr(
            loop_module.genai, "Client", fake_client_factory(scripted)
        )

        resp = await run_agent_chat(AgentChatRequest(
            user_id=user_id,
            design_id=design_id,
            message="place a chair in the middle of the room",
        ))

        assert resp.assistant_text.startswith("Done")
        assert len(resp.tool_calls) == 1
        assert resp.tool_calls[0].tool == "place_item"
        assert "error" not in resp.tool_calls[0].result, resp.tool_calls[0].result

        # Active turn → mutation captured
        assert len(resp.mutations.placements_added) == 1
        added = resp.mutations.placements_added[0]
        assert added.furniture.id == KNOWN_FURNITURE_ID
        assert added.placement.position == (2.5, 0.0, 2.0)
        assert added.placed_by == "agent"
        assert added.rationale == "Anchors the room."

        # No removed / moved
        assert resp.mutations.placements_removed == []
        assert resp.mutations.placements_moved == []

        # Design got the $push
        doc = await db.find_one({"_id": design_id})
        assert len(doc["objects"]) == 1
        assert doc["objects"][0]["furniture"]["id"] == KNOWN_FURNITURE_ID
        assert doc["objects"][0]["placed_by"] == "agent"
    finally:
        await db.delete_one({"_id": design_id})
