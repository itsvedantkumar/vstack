class NotFound(Exception):
    """No such record."""


class Forbidden(Exception):
    """The caller is not allowed to do this."""


class BadRequest(Exception):
    """The caller sent something the service will not accept."""
