"""Errors the client raises.

Every failure is a :class:`FoodApiError`, so one ``except FoodApiError`` catches them all; catch the subclasses to
tell "not found" apart from "try again later".
"""

from typing import Callable, Dict, Optional

__all__ = [
    "FoodApiError",
    "FoodApiHTTPError",
    "FoodApiBadRequest",
    "FoodApiUnauthorized",
    "FoodApiForbidden",
    "FoodApiNotFound",
    "FoodApiRateLimited",
    "FoodApiUnavailable",
    "FoodApiServerError",
    "FoodApiNetworkError",
    "FoodApiTimeoutError",
    "FoodApiInvalidInput",
]


class FoodApiError(Exception):
    """Any failure of a Food API call."""

    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


class FoodApiHTTPError(FoodApiError):
    """An error response from the API."""

    def __init__(self, status_code: int, message: str, retry_after: Optional[float] = None) -> None:
        super().__init__(message)
        self.status_code = status_code
        #: Seconds the API said to wait before retrying (its Retry-After header), or None.
        self.retry_after = retry_after

    def __str__(self) -> str:
        return "food api: %d: %s" % (self.status_code, self.message)

    @staticmethod
    def from_status(status_code: int, message: str, retry_after: Optional[float] = None) -> "FoodApiHTTPError":
        """Builds the error for an error status."""
        cls = _BY_STATUS.get(status_code)
        if cls is not None:
            return cls(message, retry_after=retry_after)
        return FoodApiServerError(status_code, message, retry_after=retry_after)


class FoodApiBadRequest(FoodApiHTTPError):
    """400: a parameter is missing or invalid."""

    def __init__(self, message: str, retry_after: Optional[float] = None) -> None:
        super().__init__(400, message, retry_after)


class FoodApiUnauthorized(FoodApiHTTPError):
    """401: the API key is missing, invalid or revoked."""

    def __init__(self, message: str, retry_after: Optional[float] = None) -> None:
        super().__init__(401, message, retry_after)


class FoodApiForbidden(FoodApiHTTPError):
    """403: the key may not make this call, for example a v1 key on the v2 API."""

    def __init__(self, message: str, retry_after: Optional[float] = None) -> None:
        super().__init__(403, message, retry_after)


class FoodApiNotFound(FoodApiHTTPError):
    """404: no such food or barcode. An answer, not a failure: show "not found"."""

    def __init__(self, message: str, retry_after: Optional[float] = None) -> None:
        super().__init__(404, message, retry_after)


class FoodApiRateLimited(FoodApiHTTPError):
    """429: too many requests; slow down and retry after :attr:`retry_after`."""

    def __init__(self, message: str, retry_after: Optional[float] = None) -> None:
        super().__init__(429, message, retry_after)


class FoodApiUnavailable(FoodApiHTTPError):
    """503: busy or briefly unavailable; retry after :attr:`retry_after`."""

    def __init__(self, message: str, retry_after: Optional[float] = None) -> None:
        super().__init__(503, message, retry_after)


class FoodApiServerError(FoodApiHTTPError):
    """Any other error status (5xx, or an unexpected 4xx), or an answer the SDK couldn't read."""


class FoodApiNetworkError(FoodApiError):
    """The API couldn't be reached (no connection, DNS failure, connection reset)."""

    def __init__(self, message: str, cause: Optional[BaseException] = None) -> None:
        super().__init__(message)
        self.cause = cause


class FoodApiTimeoutError(FoodApiError):
    """An attempt took longer than the client's timeout, or the call longer than its ``timeout=``."""


class FoodApiInvalidInput(FoodApiError, ValueError):
    """The arguments were invalid; nothing was sent."""


_BY_STATUS: Dict[int, Callable[..., FoodApiHTTPError]] = {
    400: FoodApiBadRequest,
    401: FoodApiUnauthorized,
    403: FoodApiForbidden,
    404: FoodApiNotFound,
    429: FoodApiRateLimited,
    503: FoodApiUnavailable,
}
