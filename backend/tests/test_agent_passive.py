"""Integration test: passive agent turn.

The Gemini chat is stubbed to (1) call `search_catalog` once, then (2) return a
text reply. We assert the design is NOT mutated, `recommendations` are
populated from the search results, and `mutations` is empty.
"""

from datetime import datetime, timezone
from uuid import uuid4

import pytest

import app.services.agent.loop as loop_module
import app.services.agent.tools.search_catalog as search_catalog_module
from app.db import designs_col
from app.models.agent import AgentChatRequest
from app.services.agent.loop import run_agent_chat

from _fake_genai import FakeFunctionCall, FakeResponse, fake_client_factory


def _fake_embed_text_gemini(text: str) -> list[float]:
    """Return a deterministic 768-d unit vector — the dimension matches the
    text_embedding Atlas index, so $vectorSearch accepts it."""
    return [0.0] * 767 + [1.0]


def _empty_bedroom_doc(*, design_id: str, user_id: str) -> dict:
    now = datetime.now(timezone.utc)
    return {
        "_id": design_id,
        "user_id": user_id,
        "name": "Passive Test",
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
async def test_passive_search_then_text(monkeypatch):
    user_id = str(uuid4())
    design_id = str(uuid4())
    db = designs_col()

    await db.insert_one(_empty_bedroom_doc(design_id=design_id, user_id=user_id))
    try:
        scripted = [
            FakeResponse(function_calls=[
                FakeFunctionCall("search_catalog", {"query": "small reading chair"}),
            ]),
            FakeResponse(function_calls=[], text="Here are a few small reading chairs that fit your style."),
        ]
        monkeypatch.setattr(
            loop_module.genai, "Client", fake_client_factory(scripted)
        )
        monkeypatch.setattr(
            search_catalog_module, "embed_text_gemini", _fake_embed_text_gemini
        )

        resp = await run_agent_chat(AgentChatRequest(
            user_id=user_id,
            design_id=design_id,
            message="recommend a small chair for the corner",
        ))

        assert resp.assistant_text.startswith("Here are")
        assert len(resp.tool_calls) == 1
        assert resp.tool_calls[0].tool == "search_catalog"

        # Passive turn → no mutations
        assert resp.mutations.placements_added == []
        assert resp.mutations.placements_removed == []
        assert resp.mutations.placements_moved == []

        # Recommendations were populated from the search results
        assert len(resp.recommendations) > 0
        for rec in resp.recommendations:
            assert rec.item_id
            assert rec.name

        # Design was not touched
        doc = await db.find_one({"_id": design_id})
        assert doc["objects"] == []
    finally:
        await db.delete_one({"_id": design_id})
