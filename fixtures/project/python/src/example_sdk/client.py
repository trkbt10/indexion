import httpx
from tenacity import retry, stop_after_attempt

from .auth import StaticToken, TokenProvider
from .models import Project, User


class Client:
    def __init__(
        self,
        api_key: str,
        base_url: str = "https://api.example.com",
        auth: TokenProvider | None = None,
    ) -> None:
        self.api_key = api_key
        self.base_url = base_url
        self._auth = auth or StaticToken(api_key)
        self._http = httpx.Client(base_url=base_url)

    @retry(stop=stop_after_attempt(3))
    def get_user(self, user_id: str) -> User:
        req = self._http.build_request("GET", f"/users/{user_id}")
        self._auth.apply(req)
        resp = self._http.send(req)
        resp.raise_for_status()
        return User.model_validate(resp.json())

    def list_projects(self) -> list[Project]:
        req = self._http.build_request("GET", "/projects")
        self._auth.apply(req)
        resp = self._http.send(req)
        resp.raise_for_status()
        return [Project.model_validate(p) for p in resp.json()]
