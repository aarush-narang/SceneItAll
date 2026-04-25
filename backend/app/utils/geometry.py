"""Shared geometry utilities for room/furniture validation."""

from math import sqrt


def point_in_polygon(px: float, pz: float, polygon: list[dict]) -> bool:
    """Ray-casting test for a 2D point (xz plane) inside a polygon.
    
    Args:
        px: X coordinate of point
        pz: Z coordinate of point  
        polygon: List of points with 'x' and 'z' keys
        
    Returns:
        True if point is inside polygon, False otherwise
    """
    n = len(polygon)
    if n < 3:
        return False
    
    inside = False
    j = n - 1
    for i in range(n):
        xi, zi = polygon[i]["x"], polygon[i]["z"]
        xj, zj = polygon[j]["x"], polygon[j]["z"]
        
        # Check if edge crosses the horizontal ray from the point
        if (zi > pz) != (zj > pz):
            # Calculate x coordinate of edge intersection with horizontal line at pz
            if px < (xj - xi) * (pz - zi) / (zj - zi) + xi:
                inside = not inside
        j = i
    return inside


def get_item_bounding_box(
    position: dict,
    dimensions: dict,
) -> tuple[tuple[float, float], tuple[float, float], tuple[float, float]]:
    """Get the axis-aligned bounding box of an item.
    
    Args:
        position: {'x': float, 'y': float, 'z': float}
        dimensions: {'width_m': float, 'height_m': float, 'depth_m': float}
        
    Returns:
        ((x_min, x_max), (y_min, y_max), (z_min, z_max))
    """
    x_min = position["x"] - dimensions["width_m"] / 2
    x_max = position["x"] + dimensions["width_m"] / 2
    y_min = position["y"]
    y_max = position["y"] + dimensions["height_m"]
    z_min = position["z"] - dimensions["depth_m"] / 2
    z_max = position["z"] + dimensions["depth_m"] / 2
    return (x_min, x_max), (y_min, y_max), (z_min, z_max)


def check_item_fits_in_room(
    position: dict,
    dimensions: dict,
    floor_polygon: list[dict],
    bbox_max: dict,
) -> tuple[bool, str]:
    """Check if an item fits within the room bounds.
    
    Args:
        position: {'x': float, 'y': float, 'z': float}
        dimensions: {'width_m': float, 'height_m': float, 'depth_m': float}
        floor_polygon: List of floor points with 'x' and 'z' keys
        bbox_max: Room ceiling {'x': float, 'y': float, 'z': float}
        
    Returns:
        (is_valid, error_message) - tuple of (True, None) if valid, else (False, error_msg)
    """
    # Check ceiling height
    item_top = position["y"] + dimensions["height_m"]
    if item_top > bbox_max["y"]:
        return False, f"Item height {dimensions['height_m']}m at y={position['y']} exceeds ceiling at y={bbox_max['y']}"
    
    # Check all 4 corners are within floor polygon
    corners = [
        (position["x"] - dimensions["width_m"] / 2, position["z"] - dimensions["depth_m"] / 2),
        (position["x"] + dimensions["width_m"] / 2, position["z"] - dimensions["depth_m"] / 2),
        (position["x"] - dimensions["width_m"] / 2, position["z"] + dimensions["depth_m"] / 2),
        (position["x"] + dimensions["width_m"] / 2, position["z"] + dimensions["depth_m"] / 2),
    ]
    
    for cx, cz in corners:
        if not point_in_polygon(cx, cz, floor_polygon):
            return False, f"Position ({position['x']}, {position['z']}) with dimensions is outside the room floor polygon"
    
    return True, None