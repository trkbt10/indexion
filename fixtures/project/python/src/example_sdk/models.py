"""
Wire models for the Example API.

Every model is a pydantic model so the client can validate a response
without a hand-written parser; ``Page`` is generic over the row type it
carries.
"""
from dataclasses import dataclass, field

from pydantic import BaseModel


class User(BaseModel):
    id: str
    name: str
    email: str


class Project(BaseModel):
    id: str
    name: str
    owner_id: str


@dataclass
class Page:
    """
    One page of a paginated collection.

    ``cursor`` is opaque: it is handed back to the API verbatim to ask for
    the next page, and is ``None`` on the last one.
    """

    class Cursor:
        """An opaque position in a collection."""

        def __init__(self, token: str) -> None:
            self.token = token

        def __str__(self) -> str:
            return self.token

    items: list = field(default_factory=list)
    cursor: str | None = None

    @property
    def is_last(self) -> bool:
        """True when no further page follows this one."""
        return self.cursor is None

    def chunked(self, size: int) -> list:
        """
        Splits this page's items into runs of at most ``size``.

        The split is done by a local helper so the bounds arithmetic stays
        out of the public surface.
        """

        def bounds(start: int) -> tuple:
            return start, min(start + size, len(self.items))

        out = []
        for start in range(0, len(self.items), size):
            lo, hi = bounds(start)
            out.append(self.items[lo:hi])
        return out
