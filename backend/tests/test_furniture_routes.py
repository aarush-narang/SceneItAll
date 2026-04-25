import pytest
from fastapi.testclient import TestClient

from app.main import app

# A known IKEA item confirmed in the DB
KNOWN_ID = "00069768"
NONEXISTENT_ID = "does-not-exist-xyz"


@pytest.fixture(scope="module")
def client():
    """Module-scoped TestClient keeps the anyio event loop alive across all tests,
    preventing motor's executor from hitting a closed loop."""
    with TestClient(app) as c:
        yield c


# ---------------------------------------------------------------------------
# GET /furniture/{id}
# ---------------------------------------------------------------------------

def test_get_furniture_found(client):
    resp = client.get(f"/furniture/{KNOWN_ID}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["id"] == KNOWN_ID
    assert "name" in data
    assert "price" in data
    assert data["price"]["value"] > 0
    assert "dimensions_bbox" in data
    # embeddings must be stripped from the public response
    assert data.get("embeddings") is None


def test_get_furniture_not_found(client):
    resp = client.get(f"/furniture/{NONEXISTENT_ID}")
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# GET /furniture/search
# ---------------------------------------------------------------------------

def test_search_furniture_returns_results(client):
    resp = client.get("/furniture/search", params={"q": "shelf unit"})
    assert resp.status_code == 200
    items = resp.json()
    assert isinstance(items, list)
    assert len(items) > 0
    for item in items:
        assert "id" in item
        assert "name" in item
        assert "price" in item
        assert item.get("embeddings") is None


def test_search_furniture_category_filter(client):
    resp = client.get("/furniture/search", params={"q": "shelf", "category": "storage"})
    assert resp.status_code == 200
    items = resp.json()
    assert isinstance(items, list)
    for item in items:
        assert item["taxonomy_inferred"]["category"] == "storage"


def test_search_furniture_max_price_filter(client):
    max_price = 100.0
    resp = client.get("/furniture/search", params={"q": "table", "max_price": max_price})
    assert resp.status_code == 200
    items = resp.json()
    assert isinstance(items, list)
    for item in items:
        assert item["price"]["value"] <= max_price


def test_search_furniture_limit(client):
    resp = client.get("/furniture/search", params={"q": "chair", "limit": 3})
    assert resp.status_code == 200
    items = resp.json()
    assert len(items) <= 3


def test_search_furniture_missing_query(client):
    resp = client.get("/furniture/search")
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# GET /furniture/similar
# ---------------------------------------------------------------------------

def test_similar_furniture_returns_results(client):
    resp = client.get("/furniture/similar", params={"id": KNOWN_ID})
    assert resp.status_code == 200
    items = resp.json()
    assert isinstance(items, list)
    assert len(items) > 0
    # Source item must not appear in results
    ids = [item["id"] for item in items]
    assert KNOWN_ID not in ids
    for item in items:
        assert item.get("embeddings") is None


def test_similar_furniture_not_found(client):
    resp = client.get("/furniture/similar", params={"id": NONEXISTENT_ID})
    assert resp.status_code == 404


def test_similar_furniture_max_price_filter(client):
    max_price = 80.0
    resp = client.get("/furniture/similar", params={"id": KNOWN_ID, "max_price": max_price})
    assert resp.status_code == 200
    items = resp.json()
    assert isinstance(items, list)
    for item in items:
        assert item["price"]["value"] <= max_price


def test_similar_furniture_limit(client):
    resp = client.get("/furniture/similar", params={"id": KNOWN_ID, "limit": 3})
    assert resp.status_code == 200
    items = resp.json()
    assert len(items) <= 3
