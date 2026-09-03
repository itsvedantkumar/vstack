import calendar
from datetime import datetime


def to_epoch(iso: str) -> int:
    """Parse an ISO-8601 timestamp and return Unix epoch seconds."""
    dt = datetime.strptime(iso[:19], "%Y-%m-%dT%H:%M:%S")
    return calendar.timegm(dt.timetuple())
