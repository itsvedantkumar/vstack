import sys
from src.when import to_epoch

ok = (
    to_epoch("2024-01-01T10:00:00+02:00") == 1704096000
    and to_epoch("2024-01-01T00:00:00-05:00") == 1704085200
    and to_epoch("2024-06-15T12:30:00+05:30") == 1718434800
)
sys.exit(0 if ok else 1)
