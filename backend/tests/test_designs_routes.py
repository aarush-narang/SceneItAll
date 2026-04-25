"""
Tests for /designs endpoints using pytest-anyio.

This approach properly handles async tests with Motor 3.x by using
pytest-anyio instead of pytest-asyncio with TestClient.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport


def get_db():
    """Get database for current event loop."""
    import motor.motor_asyncio as mo
    from backend.app.config import settings
    client = mo.AsyncIOMotorClient(settings.mongodb_uri)
    return client[settings.mongodb_db], client


@pytest.fixture
def sample_shell():
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


@pytest_asyncio.fixture(autouse=True)
async def reset_motor_client():
    """Reset Motor client before each test."""
    import backend.app.db as db_module
    # Close existing client if any
    if db_module._client is not None:
        try:
            db_module._client.close()
        except:
            pass
        db_module._client = None
    yield
    # Cleanup after test
    if db_module._client is not None:
        try:
            db_module._client.close()
        except:
            pass
        db_module._client = None


@pytest.mark.anyio
async def test_list_designs_route(sample_shell):
    """GET /designs?user_id=..."""
    furniture_id = "test-furniture-list-" + str(uuid.uuid4())[:8]
    design_id = str(uuid.uuid4())
    user_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)

    try:
        db, client_db = get_db()
        
        await db["furniture"].insert_one({
            "_id": furniture_id,
            "source": "ikea",
            "name": "Test Sofa",
            "category": "sofa",
            "price_usd": 499.99,
            "dimensions": {"width_m": 2.0, "height_m": 0.8, "depth_m": 0.9},
            "usdz_url": "https://example.com/sofa.usdz",
            "thumbnail_url": "https://example.com/sofa.jpg",
            "visual_embedding": [0.1] * 512,
            "text_embedding": [0.1] * 512,
            "created_at": now,
        })

        await db["designs"].insert_one({
            "_id": design_id,
            "user_id": user_id,
            "name": "Test Design",
            "shell": sample_shell,
            "placed_items": [],
            "created_at": now,
            "updated_at": now,
            "deleted_at": None,
        })

        from backend.app.main import app
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            response = await ac.get(f"/designs?user_id={user_id}")

        assert response.status_code == 200
        data = response.json()
        assert isinstance(data, list)
        assert any(d["id"] == design_id for d in data)
    finally:
        db, client_db = get_db()
        await db["furniture"].delete_many({"_id": furniture_id})
        await db["designs"].delete_many({"_id": design_id})
        client_db.close()


@pytest.mark.anyio
async def test_create_design_route(sample_shell):
    """POST /designs"""
    user_id = str(uuid.uuid4())
    payload = {
        "user_id": user_id,
        "name": "New Design",
        "preference_profile_id": None,
        "shell": sample_shell,
    }

    from backend.app.main import app
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.post("/designs", json=payload)

    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "New Design"

    # Cleanup
    db, client_db = get_db()
    await db["designs"].delete_many({"user_id": user_id})
    client_db.close()


@pytest.mark.anyio
async def test_get_design_route(sample_shell):
    """GET /designs/{id}"""
    furniture_id = "test-furniture-" + str(uuid.uuid4())[:8]
    design_id = str(uuid.uuid4())
    user_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)

    try:
        db, client_db = get_db()
        
        await db["furniture"].insert_one({
            "_id": furniture_id,
            "source": "ikea",
            "name": "Test Sofa",
            "category": "sofa",
            "dimensions": {"width_m": 2.0, "height_m": 0.8, "depth_m": 0.9},
            "created_at": now,
        })

        await db["designs"].insert_one({
            "_id": design_id,
            "user_id": user_id,
            "name": "Test Design",
            "shell": sample_shell,
            "placed_items": [],
            "created_at": now,
            "updated_at": now,
            "deleted_at": None,
        })

        from backend.app.main import app
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            response = await ac.get(f"/designs/{design_id}")

        assert response.status_code == 200
        data = response.json()
        assert data["id"] == design_id
    finally:
        db, client_db = get_db()
        await db["furniture"].delete_many({"_id": furniture_id})
        await db["designs"].delete_many({"_id": design_id})
        client_db.close()


@pytest.mark.anyio
async def test_get_design_route_not_found():
    """GET /designs/{id} returns 404 for non-existent design"""
    fake_id = str(uuid.uuid4())

    from backend.app.main import app
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.get(f"/designs/{fake_id}")

    assert response.status_code == 404


@pytest.mark.anyio
async def test_patch_design_route_rename(sample_shell):
    """PATCH /designs/{id} - rename design"""
    furniture_id = "test-furniture-" + str(uuid.uuid4())[:8]
    design_id = str(uuid.uuid4())
    user_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)

    try:
        db, client_db = get_db()
        
        await db["furniture"].insert_one({
            "_id": furniture_id,
            "source": "ikea",
            "name": "Test Sofa",
            "dimensions": {"width_m": 2.0, "height_m": 0.8, "depth_m": 0.9},
            "created_at": now,
        })

        await db["designs"].insert_one({
            "_id": design_id,
            "user_id": user_id,
            "name": "Test Design",
            "shell": sample_shell,
            "placed_items": [],
            "created_at": now,
            "updated_at": now,
            "deleted_at": None,
        })

        from backend.app.main import app
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            response = await ac.patch(f"/designs/{design_id}", json={"name": "Renamed"})

        assert response.status_code == 200
        data = response.json()
        assert data["name"] == "Renamed"
    finally:
        db, client_db = get_db()
        await db["furniture"].delete_many({"_id": furniture_id})
        await db["designs"].delete_many({"_id": design_id})
        client_db.close()


@pytest.mark.anyio
async def test_delete_design_route(sample_shell):
    """DELETE /designs/{id}"""
    furniture_id = "test-furniture-" + str(uuid.uuid4())[:8]
    design_id = str(uuid.uuid4())
    user_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)

    try:
        db, client_db = get_db()
        
        await db["furniture"].insert_one({
            "_id": furniture_id,
            "source": "ikea",
            "name": "Test Sofa",
            "dimensions": {"width_m": 2.0, "height_m": 0.8, "depth_m": 0.9},
            "created_at": now,
        })

        await db["designs"].insert_one({
            "_id": design_id,
            "user_id": user_id,
            "name": "Test Design",
            "shell": sample_shell,
            "placed_items": [],
            "created_at": now,
            "updated_at": now,
            "deleted_at": None,
        })

        from backend.app.main import app
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            response = await ac.delete(f"/designs/{design_id}")

        assert response.status_code == 204

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            response = await ac.get(f"/designs/{design_id}")

        assert response.status_code == 404
    finally:
        db, client_db = get_db()
        await db["furniture"].delete_many({"_id": furniture_id})
        await db["designs"].delete_many({"_id": design_id})
        client_db.close()


@pytest.mark.anyio
async def test_delete_design_route_not_found():
    """DELETE /designs/{id} returns 404 for non-existent design"""
    fake_id = str(uuid.uuid4())

    from backend.app.main import app
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.delete(f"/designs/{fake_id}")

    assert response.status_code == 404


@pytest.mark.anyio
async def test_validate_placed_item_outside_polygon(sample_shell):
    """Test that placing item outside floor polygon returns 422."""
    furniture_id = "test-furniture-outside-" + str(uuid.uuid4())[:8]
    design_id = str(uuid.uuid4())
    user_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)

    try:
        db, client_db = get_db()
        
        await db["furniture"].insert_one({
            "_id": furniture_id,
            "source": "ikea",
            "name": "Test Sofa",
            "category": "sofa",
            "price_usd": 499.99,
            "dimensions": {"width_m": 1.0, "height_m": 1.0, "depth_m": 1.0},
            "usdz_url": "https://example.com/sofa.usdz",
            "created_at": now,
        })

        await db["designs"].insert_one({
            "_id": design_id,
            "user_id": user_id,
            "name": "Test Design",
            "shell": sample_shell,
            "placed_items": [],
            "created_at": now,
            "updated_at": now,
            "deleted_at": None,
        })
        client_db.close()

        # Place item outside the room (x=10, z=10 is outside 5x4 room)
        payload = {
            "add_items": [{
                "instance_id": str(uuid.uuid4()),
                "item_id": furniture_id,
                "position": {"x": 10.0, "y": 0.0, "z": 10.0},
                "rotation": {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0},
                "placed_by": "user",
                "rationale": None,
            }]
        }

        from backend.app.main import app
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            response = await ac.patch(f"/designs/{design_id}", json=payload)

        assert response.status_code == 422
        assert "outside the room floor polygon" in response.json()["detail"]
    finally:
        db, client_db = get_db()
        await db["furniture"].delete_many({"_id": furniture_id})
        await db["designs"].delete_many({"_id": design_id})
        client_db.close()


@pytest.mark.anyio
async def test_validate_placed_item_exceeds_ceiling(sample_shell):
    """Test that placing item that exceeds ceiling height returns 422."""
    furniture_id = "test-furniture-tall-" + str(uuid.uuid4())[:8]
    design_id = str(uuid.uuid4())
    user_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)

    try:
        db, client_db = get_db()
        
        # Item that is 5m tall (room ceiling is at y=3)
        await db["furniture"].insert_one({
            "_id": furniture_id,
            "source": "ikea",
            "name": "Very Tall Cabinet",
            "category": "cabinet",
            "price_usd": 299.99,
            "dimensions": {"width_m": 1.0, "height_m": 5.0, "depth_m": 1.0},
            "usdz_url": "https://example.com/cabinet.usdz",
            "created_at": now,
        })

        await db["designs"].insert_one({
            "_id": design_id,
            "user_id": user_id,
            "name": "Test Design",
            "shell": sample_shell,
            "placed_items": [],
            "created_at": now,
            "updated_at": now,
            "deleted_at": None,
        })
        client_db.close()

        # Place item on floor but it's too tall
        payload = {
            "add_items": [{
                "instance_id": str(uuid.uuid4()),
                "item_id": furniture_id,
                "position": {"x": 2.5, "y": 0.0, "z": 2.0},
                "rotation": {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0},
                "placed_by": "user",
                "rationale": None,
            }]
        }

        from backend.app.main import app
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            response = await ac.patch(f"/designs/{design_id}", json=payload)

        assert response.status_code == 422
        assert "exceeds ceiling" in response.json()["detail"]
    finally:
        db, client_db = get_db()
        await db["furniture"].delete_many({"_id": furniture_id})
        await db["designs"].delete_many({"_id": design_id})
        client_db.close()


@pytest.mark.anyio
async def test_validate_placed_item_bounding_box_outside(sample_shell):
    """Test that item extending outside room (bounding box) returns 422."""
    furniture_id = "test-furniture-large-" + str(uuid.uuid4())[:8]
    design_id = str(uuid.uuid4())
    user_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)

    try:
        db, client_db = get_db()
        
        # Large item (3m wide) placed near room edge
        await db["furniture"].insert_one({
            "_id": furniture_id,
            "source": "ikea",
            "name": "Large Sofa",
            "category": "sofa",
            "price_usd": 899.99,
            "dimensions": {"width_m": 3.0, "height_m": 1.0, "depth_m": 1.0},
            "usdz_url": "https://example.com/sofa.usdz",
            "created_at": now,
        })

        await db["designs"].insert_one({
            "_id": design_id,
            "user_id": user_id,
            "name": "Test Design",
            "shell": sample_shell,  # Room is 5x4
            "placed_items": [],
            "created_at": now,
            "updated_at": now,
            "deleted_at": None,
        })
        client_db.close()

        # Place item at edge - 3m wide centered at x=4 means extends from x=2.5 to x=5.5 (outside!)
        payload = {
            "add_items": [{
                "instance_id": str(uuid.uuid4()),
                "item_id": furniture_id,
                "position": {"x": 4.0, "y": 0.0, "z": 2.0},
                "rotation": {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0},
                "placed_by": "user",
                "rationale": None,
            }]
        }

        from backend.app.main import app
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            response = await ac.patch(f"/designs/{design_id}", json=payload)

        assert response.status_code == 422
        assert "outside the room floor polygon" in response.json()["detail"]
    finally:
        db, client_db = get_db()
        await db["furniture"].delete_many({"_id": furniture_id})
        await db["designs"].delete_many({"_id": design_id})
        client_db.close()


@pytest.mark.anyio
async def test_validate_placed_item_not_found(sample_shell):
    """Test that placing non-existent furniture item returns 422."""
    design_id = str(uuid.uuid4())
    user_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)

    try:
        db, client_db = get_db()
        
        await db["designs"].insert_one({
            "_id": design_id,
            "user_id": user_id,
            "name": "Test Design",
            "shell": sample_shell,
            "placed_items": [],
            "created_at": now,
            "updated_at": now,
            "deleted_at": None,
        })
        client_db.close()

        # Try to place non-existent item
        payload = {
            "add_items": [{
                "instance_id": str(uuid.uuid4()),
                "item_id": "non-existent-item-id",
                "position": {"x": 2.5, "y": 0.0, "z": 2.0},
                "rotation": {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0},
                "placed_by": "user",
                "rationale": None,
            }]
        }

        from backend.app.main import app
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            response = await ac.patch(f"/designs/{design_id}", json=payload)

        assert response.status_code == 422
        assert "not found" in response.json()["detail"]
    finally:
        db, client_db = get_db()
        await db["designs"].delete_many({"_id": design_id})
        client_db.close()


@pytest.mark.anyio
async def test_validate_placed_item_valid_placement(sample_shell):
    """Test that valid placement succeeds."""
    furniture_id = "test-furniture-valid-" + str(uuid.uuid4())[:8]
    design_id = str(uuid.uuid4())
    user_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)

    try:
        db, client_db = get_db()
        
        await db["furniture"].insert_one({
            "_id": furniture_id,
            "source": "ikea",
            "name": "Test Chair",
            "category": "chair",
            "price_usd": 199.99,
            "dimensions": {"width_m": 1.0, "height_m": 1.0, "depth_m": 1.0},
            "usdz_url": "https://example.com/chair.usdz",
            "created_at": now,
        })

        await db["designs"].insert_one({
            "_id": design_id,
            "user_id": user_id,
            "name": "Test Design",
            "shell": sample_shell,
            "placed_items": [],
            "created_at": now,
            "updated_at": now,
            "deleted_at": None,
        })
        client_db.close()

        # Place item in valid position (center of room)
        payload = {
            "add_items": [{
                "instance_id": str(uuid.uuid4()),
                "item_id": furniture_id,
                "position": {"x": 2.5, "y": 0.0, "z": 2.0},
                "rotation": {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0},
                "placed_by": "user",
                "rationale": None,
            }]
        }

        from backend.app.main import app
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            response = await ac.patch(f"/designs/{design_id}", json=payload)

        assert response.status_code == 200
        data = response.json()
        assert len(data["placed_items"]) == 1
        assert data["placed_items"][0]["item_id"] == furniture_id
    finally:
        db, client_db = get_db()
        await db["furniture"].delete_many({"_id": furniture_id})
        await db["designs"].delete_many({"_id": design_id})
        client_db.close()