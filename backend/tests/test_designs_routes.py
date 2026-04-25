import math
from uuid import uuid4

from fastapi.testclient import TestClient

from app.main import app


KNOWN_FURNITURE_ID = "00069768"  # exists in the catalog; used for catalog-existence checks


def sample_shell() -> dict:
    """A minimal valid RoomShell payload — 5×4 m bedroom, 3 m ceiling, no walls.

    `walls` is empty so the validator falls back to floor_y=0, which keeps the
    placement maths simple in tests.
    """
    return {
        "schemaVersion": "1.0",
        "units": "meters",
        "metadata": {
            "generatedAt": "2026-04-25T17:54:17Z",
            "sourceVersion": 2,
        },
        "room": {
            "id": "test-room-id",
            "type": "bedroom",
            "story": 0,
            "ceilingHeight": 3.0,
            "boundingBox": {"width": 5.0, "depth": 4.0},
            "floorPolygon": [[0.0, 0.0], [5.0, 0.0], [5.0, 4.0], [0.0, 4.0]],
        },
        "walls": [],
        "openings": [],
    }


def design_payload(user_id: str | None = None, objects: list[dict] | None = None) -> dict:
    return {
        "user_id": user_id or str(uuid4()),
        "name": "Test Design",
        "preference_profile_id": None,
        "shell": sample_shell(),
        "objects": objects or [],
    }


def sample_placed_object(
    *,
    catalog_id: str = KNOWN_FURNITURE_ID,
    instance_id: str | None = None,
    position: tuple[float, float, float] = (2.5, 0.0, 2.0),
    euler_angles: tuple[float, float, float] = (0.0, 0.0, 0.0),
    width: float = 0.5,
    height: float = 0.8,
    depth: float = 0.5,
) -> dict:
    return {
        "id": instance_id or str(uuid4()),
        "furniture": {
            "_id": catalog_id,
            "name": "Test Item",
            "family_key": "test_family",
            "dimensions_bbox": {"width_m": width, "height_m": height, "depth_m": depth},
            "files": {"usdz_url": "https://example.com/test.usdz"},
        },
        "placement": {
            "position": list(position),
            "eulerAngles": list(euler_angles),
            "scale": [1.0, 1.0, 1.0],
        },
        "addedAt": "2026-04-25T17:54:16Z",
        "placed_by": "user",
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
    assert data["objects"] == []


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
    """PATCH referencing a non-existent furniture catalog id returns 422."""
    with TestClient(app) as client:
        created = client.post("/designs", json=design_payload()).json()
        response = client.patch(f"/designs/{created['id']}", json={
            "add_items": [sample_placed_object(catalog_id="non-existent-item-id")]
        })

    assert response.status_code == 422
    assert "not found" in response.json()["detail"]


def test_validate_placement_valid():
    """An upright item inside the room footprint and below the ceiling is accepted."""
    with TestClient(app) as client:
        created = client.post("/designs", json=design_payload()).json()
        response = client.patch(f"/designs/{created['id']}", json={
            "add_items": [sample_placed_object()]
        })

    assert response.status_code == 200, response.json()
    assert len(response.json()["objects"]) == 1


def test_validate_placement_outside_floor_polygon():
    """Position whose footprint falls outside the floor polygon returns 422."""
    with TestClient(app) as client:
        created = client.post("/designs", json=design_payload()).json()
        response = client.patch(f"/designs/{created['id']}", json={
            "add_items": [sample_placed_object(position=(10.0, 0.0, 10.0))]
        })

    assert response.status_code == 422
    assert "floor polygon" in response.json()["detail"]


def test_validate_placement_exceeds_ceiling():
    """Item taller than the ceiling height returns 422."""
    with TestClient(app) as client:
        created = client.post("/designs", json=design_payload()).json()
        response = client.patch(f"/designs/{created['id']}", json={
            "add_items": [sample_placed_object(height=4.0)]   # ceiling is 3.0
        })

    assert response.status_code == 422
    assert "ceiling" in response.json()["detail"]


def test_validate_placement_tilted():
    """Item tilted beyond the upright tolerance (e.g. on its edge) returns 422."""
    with TestClient(app) as client:
        created = client.post("/designs", json=design_payload()).json()
        response = client.patch(f"/designs/{created['id']}", json={
            "add_items": [sample_placed_object(euler_angles=(math.pi / 4, 0.0, 0.0))]
        })

    assert response.status_code == 422
    assert "upright" in response.json()["detail"]


def test_validate_placement_upside_down():
    """A flipped item (pitched ~180°) is not upright and returns 422."""
    with TestClient(app) as client:
        created = client.post("/designs", json=design_payload()).json()
        response = client.patch(f"/designs/{created['id']}", json={
            "add_items": [sample_placed_object(euler_angles=(math.pi, 0.0, 0.0))]
        })

    assert response.status_code == 422
    assert "upright" in response.json()["detail"]


def test_validate_placement_collides_with_existing():
    """A new item whose OBB overlaps an existing placed item returns 422."""
    existing = sample_placed_object(position=(2.5, 0.0, 2.0))
    payload = design_payload(objects=[existing])

    with TestClient(app) as client:
        created = client.post("/designs", json=payload).json()
        response = client.patch(f"/designs/{created['id']}", json={
            "add_items": [sample_placed_object(position=(2.5, 0.0, 2.0))]
        })

    assert response.status_code == 422
    assert "collides" in response.json()["detail"]


def test_validate_placement_yaw_only_is_allowed():
    """Yaw rotation around the vertical axis is fine — it doesn't tilt the item."""
    with TestClient(app) as client:
        created = client.post("/designs", json=design_payload()).json()
        response = client.patch(f"/designs/{created['id']}", json={
            "add_items": [sample_placed_object(euler_angles=(0.0, math.pi / 4, 0.0))]
        })

    assert response.status_code == 200, response.json()
