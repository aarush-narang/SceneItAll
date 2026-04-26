"""Unit tests for app.services.placement.validate_placement.

Exercises the validator directly against in-memory design docs (so we control
the shell shape per test) plus the live furniture catalog for the existence
check. Uses anyio + the asyncio backend (pinned in conftest) so Motor calls
work the same way they do at runtime.
"""

import math
from uuid import uuid4

import pytest

from app.models.design import (
    FurnitureBoundingBox,
    FurnitureFiles,
    FurnitureSnapshot,
    PlacedObject,
    Placement,
)
from app.services.placement import validate_placement


KNOWN_FURNITURE_ID = "00069768"


def _polygon_4x4() -> list[list[float]]:
    return [[0.0, 0.0], [4.0, 0.0], [4.0, 4.0], [0.0, 4.0]]


def _wall_south() -> dict:
    return {
        "id": "wall_south",
        "center": [2.0, 1.5, 0.0],
        "start": [0.0, 0.0],
        "end": [4.0, 0.0],
        "width": 4.0,
        "height": 3.0,
        "rotation_radians": 0.0,
        "confidence": 0.9,
    }


def _wall_east() -> dict:
    return {
        "id": "wall_east",
        "center": [4.0, 1.5, 2.0],
        "start": [4.0, 0.0],
        "end": [4.0, 4.0],
        "width": 4.0,
        "height": 3.0,
        "rotation_radians": math.pi / 2,
        "confidence": 0.9,
    }


def _door_south() -> dict:
    return {
        "id": "door_1",
        "type": "door",
        "wall_id": "wall_south",
        "center": [2.0, 1.0, 0.0],
        "width": 1.0,
        "height": 2.0,
        "bottom_height": 0.0,
        "rotation_radians": 0.0,
        "confidence": 0.9,
        "is_open": False,
    }


def _opening_east() -> dict:
    return {
        "id": "opening_1",
        "type": "opening",
        "wall_id": "wall_east",
        "center": [4.0, 1.0, 2.0],
        "width": 0.7,
        "height": 2.0,
        "bottom_height": 0.0,
        "rotation_radians": math.pi / 2,
        "confidence": 0.9,
    }


def _shell(*, walls=(), openings=(), polygon=None) -> dict:
    return {
        "schema_version": "1.0",
        "units": "meters",
        "metadata": {"generated_at": "2026-04-25T17:54:17Z", "source_version": 2},
        "room": {
            "id": "test-room",
            "type": "bedroom",
            "story": 0,
            "ceiling_height": 3.0,
            "bounding_box": {"width": 4.0, "depth": 4.0},
            "floor_polygon": polygon or _polygon_4x4(),
        },
        "walls": list(walls),
        "openings": list(openings),
    }


def _design(*, objects=(), **shell_kwargs) -> dict:
    return {
        "_id": str(uuid4()),
        "user_id": "test-user",
        "name": "Test Design",
        "shell": _shell(**shell_kwargs),
        "objects": list(objects),
    }


def _placed_object(
    *,
    id_: str | None = None,
    catalog_id: str = KNOWN_FURNITURE_ID,
    position: tuple[float, float, float] = (2.0, 0.0, 2.0),
    euler_angles: tuple[float, float, float] = (0.0, 0.0, 0.0),
    width: float = 0.5,
    height: float = 0.8,
    depth: float = 0.5,
) -> PlacedObject:
    return PlacedObject(
        id=id_ or str(uuid4()),
        furniture=FurnitureSnapshot(
            id=catalog_id,
            name="Test Item",
            family_key=None,
            dimensions_bbox=FurnitureBoundingBox(width_m=width, height_m=height, depth_m=depth),
            files=FurnitureFiles(usdz_url="https://example.com/test.usdz"),
        ),
        placement=Placement(position=position, euler_angles=euler_angles, scale=(1.0, 1.0, 1.0)),
        added_at="2026-04-25T17:54:16Z",
        placed_by="user",
    )


def _placed_doc(item: PlacedObject) -> dict:
    return item.model_dump()


@pytest.mark.anyio
async def test_validate_catalog_missing():
    ok, msg = await validate_placement(_placed_object(catalog_id="not-a-real-id"), _design())
    assert not ok
    assert "not found" in msg


@pytest.mark.anyio
async def test_validate_outside_polygon():
    ok, msg = await validate_placement(
        _placed_object(position=(10.0, 0.0, 10.0)), _design()
    )
    assert not ok
    assert "floor polygon" in msg


@pytest.mark.anyio
async def test_validate_exceeds_ceiling():
    ok, msg = await validate_placement(_placed_object(height=4.0), _design())
    assert not ok
    assert "ceiling" in msg


@pytest.mark.anyio
async def test_validate_tilted():
    ok, msg = await validate_placement(
        _placed_object(euler_angles=(math.pi / 4, 0.0, 0.0)), _design()
    )
    assert not ok
    assert "upright" in msg


@pytest.mark.anyio
async def test_validate_upside_down():
    ok, msg = await validate_placement(
        _placed_object(euler_angles=(math.pi, 0.0, 0.0)), _design()
    )
    assert not ok
    assert "upright" in msg


@pytest.mark.anyio
async def test_validate_collides_with_existing():
    existing = _placed_object(position=(2.0, 0.0, 2.0))
    ok, msg = await validate_placement(
        _placed_object(position=(2.0, 0.0, 2.0)),
        _design(objects=[_placed_doc(existing)]),
    )
    assert not ok
    assert "collides" in msg


@pytest.mark.anyio
async def test_validate_blocks_door_clearance():
    """An item placed inside the inward 1m clearance zone of a door is rejected."""
    ok, msg = await validate_placement(
        _placed_object(position=(2.0, 0.0, 0.5)),  # 0.5m from south wall, in front of door
        _design(walls=[_wall_south()], openings=[_door_south()]),
    )
    assert not ok
    assert "clearance" in msg
    assert "door" in msg


@pytest.mark.anyio
async def test_validate_blocks_opening_clearance():
    """An item placed in the inward 1m clearance of an open passageway is rejected."""
    ok, msg = await validate_placement(
        _placed_object(position=(3.5, 0.0, 2.0)),  # 0.5m from east wall, in opening's path
        _design(walls=[_wall_east()], openings=[_opening_east()]),
    )
    assert not ok
    assert "clearance" in msg


@pytest.mark.anyio
async def test_validate_passes_just_outside_door_zone():
    """An item just past the door's 1m clearance zone (z=1.5) is accepted."""
    ok, msg = await validate_placement(
        _placed_object(position=(2.0, 0.0, 1.5)),
        _design(walls=[_wall_south()], openings=[_door_south()]),
    )
    assert ok, msg


@pytest.mark.anyio
async def test_validate_excludes_self_on_update():
    """When the validator sees an item with the same id already placed, it
    treats it as the same instance being updated and ignores self-collision."""
    instance_id = str(uuid4())
    existing = _placed_object(id_=instance_id, position=(2.0, 0.0, 2.0))
    moved = _placed_object(id_=instance_id, position=(2.0, 0.0, 2.0))  # no actual move
    ok, msg = await validate_placement(
        moved, _design(objects=[_placed_doc(existing)])
    )
    assert ok, msg


@pytest.mark.anyio
async def test_validate_valid_placement():
    ok, msg = await validate_placement(_placed_object(), _design())
    assert ok, msg
