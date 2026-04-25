import pytest


@pytest.fixture(autouse=True)
def reset_motor_client():
    """Recreate the Motor client per test.

    Motor binds its internal executor to the asyncio event loop in use at
    creation time. anyio gives each async test its own loop, and TestClient's
    portal opens/closes one per `with` block, so a singleton client goes stale
    across tests. Reset before each test; close after.
    """
    import app.db as db_module

    db_module._client = None
    yield
    if db_module._client is not None:
        try:
            db_module._client.close()
        except Exception:
            pass
        db_module._client = None


@pytest.fixture
def anyio_backend():
    """Pin anyio tests to the asyncio backend — Motor requires asyncio."""
    return "asyncio"
