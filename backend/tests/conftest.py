import pytest


@pytest.fixture(scope="session", autouse=True)
def setup_motor_client():
    from app.db import get_client
    client = get_client()
    yield
    try:
        client.close()
    except Exception:
        pass
