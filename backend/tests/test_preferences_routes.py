from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.app import app


EXISTING_USER_ID = "e327bd69-ef6a-4a2f-8f04-10186d3e8f4e"


def preference_payload() -> dict:
    return {
        "style_tags": ["minimalist", "modern"],
        "color_palette": ["white", "oak"],
        "material_preferences": ["wood", "metal"],
        "spatial_density": "balanced",
        "philosophies": ["Keep the room functional and uncluttered."],
        "hard_requirements": {"max_price_per_item": 500},
    }


def test_get_preferences_route():
    """GET /preferences/{user_id}"""
    user_id = str(uuid4())
    payload = preference_payload()

    with TestClient(app) as client:
        # First create a preference
        client.put(f"/preferences/{user_id}", json=payload)
        # Then retrieve it
        response = client.get(f"/preferences/{user_id}")

    assert response.status_code == 200
    data = response.json()
    assert data["user_id"] == user_id
    assert isinstance(data["id"], str)
    assert isinstance(data["style_tags"], list)
    assert isinstance(data["color_palette"], list)
    assert isinstance(data["material_preferences"], list)
    assert data["spatial_density"] in {"sparse", "balanced", "dense"}
    assert isinstance(data["philosophies"], list)
    assert isinstance(data["hard_requirements"], dict)


def test_upsert_preferences_route():
    """PUT /preferences/{user_id}"""
    user_id = str(uuid4())
    payload = preference_payload()

    with TestClient(app) as client:
        response = client.put(f"/preferences/{user_id}", json=payload)

    assert response.status_code == 200
    data = response.json()
    assert data["user_id"] == user_id
    assert data["is_template"] is False
    assert data["template_name"] is None
    assert data["style_tags"] == payload["style_tags"]
    assert data["color_palette"] == payload["color_palette"]
    assert data["material_preferences"] == payload["material_preferences"]
    assert data["spatial_density"] == payload["spatial_density"]
    assert data["philosophies"] == payload["philosophies"]
    assert data["hard_requirements"] == payload["hard_requirements"]


def test_extract_preferences_route():
    """POST /preferences/extract"""
    pytest.skip("TODO: test extract preferences route.")
