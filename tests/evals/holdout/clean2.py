from dataclasses import dataclass

@dataclass(frozen=True)
class Point:
    x: float
    y: float

    def translated(self, dx: float, dy: float) -> "Point":
        """Return a new point moved by (dx, dy)."""
        return Point(self.x + dx, self.y + dy)


def centroid(points: list[Point]) -> Point:
    """Mean position of a non-empty list of points."""
    if not points:
        raise ValueError("centroid of an empty list is undefined")
    return Point(sum(p.x for p in points) / len(points),
                 sum(p.y for p in points) / len(points))
