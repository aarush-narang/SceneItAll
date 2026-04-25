"""
pytest configuration for backend tests.

This file configures pytest-asyncio to properly handle async tests
with Motor 3.x and FastAPI TestClient.
"""
import asyncio
import pytest


def pytest_configure(config):
    """Configure pytest settings."""
    config.addinivalue_line(
        "markers", "asyncio: mark test as an asyncio test"
    )


@pytest.fixture(scope="session")
def event_loop():
    """Create an event loop for the test session.
    
    This ensures all tests use the same event loop, avoiding the
    "attached to a different loop" issue with Motor 3.x.
    """
    policy = asyncio.get_event_loop_policy()
    loop = policy.new_event_loop()
    asyncio.set_event_loop(loop)
    yield loop
    loop.close()


@pytest.fixture(scope="session", autouse=True)
def setup_motor_client(event_loop):
    """Initialize the MongoDB client in the test session's event loop.
    
    This fixture runs once per test session and ensures the Motor
    client is created in the same event loop that will be used by tests.
    """
    # Import here to avoid circular imports and ensure client is created
    # in the correct event loop
    from backend.app.db import get_client
    
    # Create the client in the session's event loop
    # All subsequent calls to get_client() will reuse this client
    client = get_client()
    
    yield
    
    # Cleanup
    try:
        client.close()
    except Exception:
        pass