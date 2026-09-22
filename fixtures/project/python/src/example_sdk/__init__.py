"""
Example SDK — a thin, typed client for the Example API.

Importing this package is enough for the common case; the submodules are
public too, for callers that want to build the pieces themselves.
"""
from .auth import RequestSigner, StaticToken, TokenProvider
from .client import Client
from .models import Page, Project, User

__all__ = [
    "Client",
    "Page",
    "Project",
    "RequestSigner",
    "StaticToken",
    "TokenProvider",
    "User",
]
__version__ = "0.3.1"


def create_client(api_key: str) -> Client:
    """Builds a client with the default options and static-token auth."""
    return Client(api_key=api_key)
