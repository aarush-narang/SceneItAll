from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.main import app


def sample_shell() -> dict:
    return {
        "usdz_url": "https://example.com/room.usdz",
        "metadata_json_url": "https://example.com/room.json",
        "floor_polygon": [
            {"x": 0, "y": 0, "z": 0},
            {"x": 5, "y": 0, "z": 0},
            {"x": 5, "y": 0, "z": 4},
            {"x": 0, "y": 0, "z": 4},
        ],
        "bbox_min": {"x": 0, "y": 0, "z": 0},
        "bbox_max": {"x": 5, "y": 3, "z": 4},
    }


def design_payload(user_id: str | None = None) -> dict:
    return {
        "user_id": user_id or str(uuid4()),
        "name": "Test Design",
        "preference_profile_id": None,
        "shell": sample_shell(),
    }


def test_create_design_route():
    """POST /designs creates and returns a new design."""
    payload = design_payload()

    with TestClient(app) as client:
        response = client.post("/designs", json=payload)

    assert response.status_code == 201
    data = response.json()
    assert isinstance(data["id"], str)
    assert data["name"] == payload["name"]
    assert data["user_id"] == payload["user_id"]
    assert data["placed_items"] == []


def test_list_designs_route():
    """GET /designs?user_id=... returns designs for that user."""
    user_id = str(uuid4())
    payload = design_payload(user_id=user_id)

    with TestClient(app) as client:
        client.post("/designs", json=payload)
        response = client.get(f"/designs?user_id={user_id}")

    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) >= 1
    assert all(d["user_id"] == user_id for d in data)


def test_get_design_route():
    """GET /designs/{id} returns the matching design."""
    with TestClient(app) as client:
        created = client.post("/designs", json=design_payload()).json()
        response = client.get(f"/designs/{created['id']}")

    assert response.status_code == 200
    data = response.json()
    assert data["id"] == created["id"]
    assert data["name"] == created["name"]


def test_get_design_route_not_found():
    """GET /designs/{id} returns 404 for a non-existent design."""
    with TestClient(app) as client:
        response = client.get(f"/designs/{uuid4()}")

    assert response.status_code == 404


def test_patch_design_route_rename():
    """PATCH /designs/{id} with name updates the design name."""
    with TestClient(app) as client:
        created = client.post("/designs", json=design_payload()).json()
        response = client.patch(f"/designs/{created['id']}", json={"name": "Renamed"})

    assert response.status_code == 200
    assert response.json()["name"] == "Renamed"


def test_delete_design_route():
    """DELETE /designs/{id} soft-deletes; subsequent GET returns 404."""
    with TestClient(app) as client:
        created = client.post("/designs", json=design_payload()).json()
        del_response = client.delete(f"/designs/{created['id']}")
        get_response = client.get(f"/designs/{created['id']}")

    assert del_response.status_code == 204
    assert get_response.status_code == 404


def test_delete_design_route_not_found():
    """DELETE /designs/{id} returns 404 for a non-existent design."""
    with TestClient(app) as client:
        response = client.delete(f"/designs/{uuid4()}")

    assert response.status_code == 404


def test_validate_placed_item_not_found():
    """PATCH referencing a non-existent furniture item returns 422."""
    with TestClient(app) as client:
        created = client.post("/designs", json=design_payload()).json()
        response = client.patch(f"/designs/{created['id']}", json={
            "add_items": [{
                "instance_id": str(uuid4()),
                "item_id": "non-existent-item-id",
                "position": {"x": 2.5, "y": 0.0, "z": 2.0},
                "rotation": {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0},
                "placed_by": "user",
            }]
        })

    assert response.status_code == 422
    assert "not found" in response.json()["detail"]


def test_validate_placed_item_geometry():
    """TODO: placement geometry tests (outside polygon, exceeds ceiling) require
    the furniture dimensions schema to be finalised."""
    pytest.skip("TODO: implement once furniture model schema is confirmed.")
