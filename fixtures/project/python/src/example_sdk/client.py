"""
HTTP client for the Example API.

The client owns a single :class:`httpx.Client`; every call goes through
``_auth`` so swapping the token provider swaps the whole auth scheme.
"""
import functools

import httpx
from tenacity import retry, stop_after_attempt

from .auth import StaticToken, TokenProvider
from .models import Page, Project, User


def raises_for_status(method):
    """
    Wraps a method so the response it returns is status-checked first.

    Written as a plain decorator rather than a base-class hook so it can be
    applied to exactly the calls that return a response.
    """

    @functools.wraps(method)
    def wrapper(self, *args, **kwargs):
        resp = method(self, *args, **kwargs)
        resp.raise_for_status()
        return resp

    return wrapper


class Client:
    """Talks to the Example API over HTTP."""

    class Options:
        """
        Per-client tunables that are not part of the request itself.

        Kept as a nested class so a caller reads ``Client.Options`` and does
        not have to import a second name.
        """

        def __init__(self, timeout: float = 10.0, retries: int = 3) -> None:
            self.timeout = timeout
            self.retries = retries

        @property
        def total_budget(self) -> float:
            """Worst-case wall time for one call, in seconds."""
            return self.timeout * self.retries

    def __init__(
        self,
        api_key: str,
        base_url: str = "https://api.example.com",
        auth: TokenProvider | None = None,
        options: "Client.Options | None" = None,
    ) -> None:
        self.api_key = api_key
        self.base_url = base_url
        self.options = options or Client.Options()
        self._auth = auth or StaticToken(api_key)
        self._http = httpx.Client(base_url=base_url, timeout=self.options.timeout)

    @raises_for_status
    def _send(self, method: str, path: str) -> httpx.Response:
        """Builds, authenticates and sends one request."""
        req = self._http.build_request(method, path)
        self._auth.apply(req)
        return self._http.send(req)

    @retry(stop=stop_after_attempt(3))
    def get_user(self, user_id: str) -> User:
        """Fetches one user by ID."""
        return User.model_validate(self._send("GET", f"/users/{user_id}").json())

    def list_projects(self) -> list[Project]:
        """Fetches every project visible to the current credentials."""
        return [Project.model_validate(p) for p in self._send("GET", "/projects").json()]

    def page_projects(self, cursor: str | None = None) -> Page:
        """Fetches one page of projects, continuing from ``cursor``."""
        path = "/projects" if cursor is None else f"/projects?cursor={cursor}"
        body = self._send("GET", path).json()
        return Page(items=body["items"], cursor=body.get("cursor"))
