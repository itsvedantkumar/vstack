"""Pagination helpers for a listing endpoint."""


def paginate(items, page, page_size=20):
    """Return the slice of `items` for the given 1-indexed page."""
    start = (page - 1) * page_size
    end = start + page_size
    return items[start:end]


def total_pages(items, page_size=20):
    """Return the number of pages needed to cover all items."""
    return len(items) // page_size
