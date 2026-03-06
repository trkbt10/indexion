import httpx
from tenacity import retry, stop_after_attempt

from .models import User, Project


class Client:
    def __init__(self, api_key: str, base_url: str = "https://api.example.com"):
        self.api_key = api_key
        self.base_url = base_url
        self._http = httpx.Client(
            base_url=base_url,
            headers={"Authorization": f"Bearer {api_key}"}
        )

    @retry(stop=stop_after_attempt(3))
    def get_user(self, user_id: str) -> User:
        resp = self._http.get(f"/users/{user_id}")
        resp.raise_for_status()
        return User.model_validate(resp.json())

    def list_projects(self) -> list[Project]:
        resp = self._http.get("/projects")
        resp.raise_for_status()
        return [Project.model_validate(p) for p in resp.json()]
