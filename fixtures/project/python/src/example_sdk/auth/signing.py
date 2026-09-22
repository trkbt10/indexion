"""
Request signing for the Example API.

Signing lives beside token auth because both decorate an outgoing request,
but a signature is derived from the request itself rather than handed out
by a provider.
"""
import hashlib
import hmac

from ..models import User
from .token import TokenProvider


class SigningError(Exception):
    """Raised when a request cannot be signed."""


class RequestSigner:
    """
    Signs outgoing requests with an HMAC of their canonical form.

    The signer wraps a :class:`TokenProvider` so the same object can both
    authenticate and sign; ``header_name`` is the header the signature is
    written to.
    """

    header_name = "X-Example-Signature"

    class Canonical:
        """The parts of a request that take part in the signature."""

        def __init__(self, method: str, path: str) -> None:
            self.method = method
            self.path = path

        def render(self) -> str:
            """Joins the parts into the string that is actually hashed."""
            return f"{self.method.upper()}\n{self.path}"

    def __init__(self, secret: str, provider: TokenProvider) -> None:
        self._secret = secret.encode("utf-8")
        self._provider = provider

    @property
    def provider(self) -> TokenProvider:
        """The token provider this signer authenticates with."""
        return self._provider

    @staticmethod
    def canonicalize(method: str, path: str) -> "RequestSigner.Canonical":
        """Builds the canonical form for a method and path."""
        return RequestSigner.Canonical(method, path)

    @classmethod
    def for_user(cls, user: User, secret: str, provider: TokenProvider) -> "RequestSigner":
        """Builds a signer whose secret is scoped to a single user."""
        return cls(f"{secret}:{user.id}", provider)

    def sign(self, method: str, path: str) -> str:
        """
        Returns the hex digest for the given request.

        Raises :class:`SigningError` when the path is empty, because an
        empty path would make two different requests hash alike.
        """
        if not path:
            raise SigningError("cannot sign an empty path")
        canonical = self.canonicalize(method, path).render()
        return hmac.new(self._secret, canonical.encode("utf-8"), hashlib.sha256).hexdigest()
