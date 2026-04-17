from abc import ABC, abstractmethod

import httpx


class TokenProvider(ABC):
    """Supplies an auth token for outgoing requests."""

    @abstractmethod
    def token(self) -> str:
        ...

    def apply(self, request: httpx.Request) -> None:
        request.headers["Authorization"] = f"Bearer {self.token()}"


class StaticToken(TokenProvider):
    def __init__(self, value: str) -> None:
        self._value = value

    def token(self) -> str:
        return self._value
