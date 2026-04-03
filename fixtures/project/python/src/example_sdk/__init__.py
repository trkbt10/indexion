from .client import Client
from .models import User, Project

__all__ = ["Client", "User", "Project"]
__version__ = "0.3.1"


def create_client(api_key: str) -> Client:
    return Client(api_key=api_key)
