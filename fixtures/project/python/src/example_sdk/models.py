from pydantic import BaseModel


class User(BaseModel):
    id: str
    name: str
    email: str


class Project(BaseModel):
    id: str
    name: str
    owner_id: str
