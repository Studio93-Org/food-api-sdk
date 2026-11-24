"""The Food API client."""

import copy
import email.utils
import gzip
import ipaddress
import json
import random
import time
from datetime import datetime, timezone
from types import TracebackType
from typing import Any, Callable, Dict, List, Mapping, Optional, Tuple, Type, TypeVar
from urllib.parse import quote, urlencode

from ._transport import Transport
from .errors import (
    FoodApiError,
    FoodApiHTTPError,
    FoodApiInvalidInput,
    FoodApiNetworkError,
    FoodApiRateLimited,
    FoodApiServerError,
    FoodApiTimeoutError,
    FoodApiUnavailable,
)
from .models import (
    AutocompleteResult,
    Food,
    ImageSet,
    NutrientList,
    NutrientStats,
    SearchPage,
    Suggestion,
)

__all__ = ["VERSION", "DEFAULT_BASE_URL", "FoodApiClient"]

#: The SDK version, sent in the User-Agent header.
VERSION = "0.4.0"

#: The Food API.
DEFAULT_BASE_URL = "https://api.studio93.io"

# Limits the API enforces, checked before sending
_MAX_QUERY_LENGTH = 200
_MAX_PAGE = 1000
_MAX_LIMIT = 50
_MAX_SUGGESTIONS = 20

# The longest Retry-After the client waits for itself; a longer one is raised to the caller
_MAX_RETRY_WAIT = 10.0

# Characters left as they are in a path segment, as Go's url.PathEscape does; "/" is encoded
_PATH_SAFE = "$&+:=@"

_Client = TypeVar("_Client", bound="FoodApiClient")


class FoodApiClient:
    """Calls the Food API's v2 endpoints.

    Create one for the whole app and share it: it keeps connections open between requests, which saves a TCP and
    TLS handshake (one or two network round trips) on every request after the first. It is safe to use from many
    threads at once.

    ``api_key`` is issued by Studio93. ``timeout`` limits each attempt, in seconds; ``max_retries`` is how often a
    request that failed for a temporary reason (network error, timeout, 429, 502, 503, 504) is sent again.
    ``user_agent`` names your app ("my-service/1.4") in front of the SDK's own User-Agent.

    Every call also takes ``client_ip=`` (the address of the user you are calling for, see :meth:`with_client_ip`)
    and ``timeout=`` (seconds the whole call may take, retries included).
    """

    def __init__(
        self,
        api_key: str,
        *,
        base_url: str = DEFAULT_BASE_URL,
        timeout: float = 15.0,
        max_retries: int = 2,
        user_agent: Optional[str] = None,
        max_idle_connections: int = 16,
    ) -> None:
        if not isinstance(api_key, str) or _has_control_chars(api_key):
            raise FoodApiInvalidInput("api_key must be a string without line breaks")
        if user_agent is not None and (not isinstance(user_agent, str) or _has_control_chars(user_agent)):
            raise FoodApiInvalidInput("user_agent must be a string without line breaks")
        attempt_timeout = _check_timeout(timeout)
        if attempt_timeout is None:
            raise FoodApiInvalidInput("timeout must be a positive number of seconds")
        if isinstance(max_retries, bool) or not isinstance(max_retries, int):
            raise FoodApiInvalidInput("max_retries must be an int")
        self._api_key = api_key
        self._transport = Transport(base_url.strip(), max_idle_connections)
        self._timeout = attempt_timeout
        self._max_retries = max(max_retries, 0)
        self._user_agent = " ".join(p for p in (user_agent, "studio93-food-api-python/" + VERSION) if p)
        self._client_ip: Optional[str] = None
        self._sleep: Callable[[float], None] = time.sleep  # Replaced in tests

    @property
    def timeout(self) -> float:
        """Seconds each attempt may take."""
        return self._timeout

    @property
    def max_retries(self) -> int:
        """How often a request that failed for a temporary reason is sent again."""
        return self._max_retries

    def __repr__(self) -> str:
        t = self._transport
        host = "[%s]" % t.host if ":" in t.host else t.host
        port = ":%d" % t.port if t.port else ""
        ip = ", client_ip=%r" % self._client_ip if self._client_ip else ""
        return "FoodApiClient(base_url=%r%s)" % ("%s://%s%s%s" % (t.scheme, host, port, t.base_path), ip)

    def with_client_ip(self: _Client, ip: str) -> _Client:
        """A client for calls made for one of your users, sending that user's IP address.

        When your server calls the API for its users, pass each user's address this way: search ranks for the
        user's country rather than your server's (with a key that has regional ranking), and usage by country
        counts the user's. The returned client shares this one's connections and is cheap to make per request.
        Apps that call the API from the user's own device don't need it. An address that isn't IPv4 or IPv6 raises
        :class:`FoodApiInvalidInput`.
        """
        view = copy.copy(self)
        view._client_ip = _check_ip(ip)
        return view

    def search(
        self,
        query: str,
        page: int = 0,
        limit: Optional[int] = None,
        *,
        client_ip: Optional[str] = None,
        timeout: Optional[float] = None,
    ) -> SearchPage:
        """Finds foods matching a query, typos and all ("chiken brest"). ``page`` is zero-based (0 to 1000),
        ``limit`` is 1 to 50 (None: the API's default, 20). A query nothing matches returns an empty page, not an
        error."""
        _check_query(query)
        _check_int("page", page, 0, _MAX_PAGE)
        params: Dict[str, str] = {"q": query}
        if page > 0:
            params["page"] = str(page)
        if limit is not None:
            _check_int("limit", limit, 1, _MAX_LIMIT)
            params["limit"] = str(limit)
        body, cached = self._get("/v2/foods/search", params, client_ip, timeout)
        meta = _meta(body)

        def build() -> SearchPage:
            region = meta.get("region")
            brand = meta.get("brand")
            return SearchPage(
                foods=[Food.from_json(f) for f in _data_list(body)],
                query=_meta_str(meta, "query", query),
                page=_meta_int(meta, "page", page),
                limit=_meta_int(meta, "limit", limit or 20),
                total=_meta_int(meta, "total", 0),
                source=_meta_str(meta, "source", "catalog"),
                region=region if isinstance(region, str) and region else None,
                brand=brand if isinstance(brand, str) and brand else None,
                cached=cached,
            )

        return _parse(build)

    def autocomplete(
        self,
        query: str,
        limit: Optional[int] = None,
        *,
        client_ip: Optional[str] = None,
        timeout: Optional[float] = None,
    ) -> AutocompleteResult:
        """Suggests foods for what has been typed so far; the last word matches as a prefix ("chick" finds Chicken).
        ``limit`` is 1 to 20 (None: the API's default, 8). It never asks outside providers, so it is fast enough for
        every keystroke."""
        _check_query(query)
        params: Dict[str, str] = {"q": query}
        if limit is not None:
            _check_int("limit", limit, 1, _MAX_SUGGESTIONS)
            params["limit"] = str(limit)
        body, cached = self._get("/v2/foods/autocomplete", params, client_ip, timeout)
        meta = _meta(body)
        return _parse(
            lambda: AutocompleteResult(
                suggestions=[Suggestion.from_json(s) for s in _data_list(body)],
                query=_meta_str(meta, "query", query),
                limit=_meta_int(meta, "limit", limit or 8),
                total=_meta_int(meta, "total", 0),
                cached=cached,
            )
        )

    def food(self, id: str, *, client_ip: Optional[str] = None, timeout: Optional[float] = None) -> Food:
        """The food with a catalog ID. An unknown ID raises :class:`FoodApiNotFound`."""
        path = "/v2/foods/" + _segment(id, "food id")
        body, _ = self._get(path, None, client_ip, timeout)
        return _parse(lambda: Food.from_json(body.get("data")))

    def food_by_barcode(
        self, barcode: str, *, client_ip: Optional[str] = None, timeout: Optional[float] = None
    ) -> Food:
        """The food for a barcode: 6 to 14 digits, or what a scanner read from a 2D code (a GS1 code such as
        "(01)03017624010701", or a GS1 Digital Link), passed as read. A barcode no source knows raises
        :class:`FoodApiNotFound`."""
        path = "/v2/foods/barcode/" + _segment(barcode, "barcode")
        body, _ = self._get(path, None, client_ip, timeout)
        return _parse(lambda: Food.from_json(body.get("data")))

    def nutrient_stats(
        self, food_id: str, *, client_ip: Optional[str] = None, timeout: Optional[float] = None
    ) -> NutrientStats:
        """What a food's source says about each of its nutrient values: samples, spread and how each was obtained.
        Foods whose source gives no such details have none."""
        path = "/v2/foods/" + _segment(food_id, "food id") + "/nutrient-stats"
        body, _ = self._get(path, None, client_ip, timeout)
        return _parse(lambda: NutrientStats.from_json(body.get("data")))

    def nutrients(self, *, client_ip: Optional[str] = None, timeout: Optional[float] = None) -> NutrientList:
        """Every nutrient key a serving can have, with its name and unit."""
        body, _ = self._get("/v2/nutrients", None, client_ip, timeout)
        return _parse(lambda: NutrientList.from_json(body.get("data")))

    def images(self, *, client_ip: Optional[str] = None, timeout: Optional[float] = None) -> ImageSet:
        """Every food image, with its label, group and URL, for apps that bundle or prefetch them. Foods carry their
        own ``Food.image``, so showing a food's picture needs no call to this."""
        body, _ = self._get("/v2/images", None, client_ip, timeout)
        return _parse(lambda: ImageSet.from_json(body.get("data")))

    def close(self) -> None:
        """Closes the open connections (shared with clients made by :meth:`with_client_ip`). The client stays
        usable: a later call opens a new connection."""
        self._transport.close()

    def __enter__(self: _Client) -> _Client:
        return self

    def __exit__(
        self,
        exc_type: Optional[Type[BaseException]],
        exc: Optional[BaseException],
        tb: Optional[TracebackType],
    ) -> None:
        self.close()

    def _get(
        self,
        path: str,
        params: Optional[Mapping[str, str]],
        client_ip: Optional[str],
        timeout: Optional[float],
    ) -> Tuple[Dict[str, Any], bool]:
        """Sends a GET request, retrying what is safe to retry. Returns the decoded body and whether the API
        answered from its cache. ``path`` is already escaped, so encoded slashes in a barcode link stay encoded."""
        ip = _check_ip(client_ip) if client_ip is not None else self._client_ip
        overall = _check_timeout(timeout)
        deadline = time.monotonic() + overall if overall is not None else None
        target = self._transport.base_path + path
        if params:
            target += "?" + urlencode(params)
        headers = {
            "Authorization": "Bearer " + self._api_key,
            "Accept": "application/json",
            "Accept-Encoding": "gzip",
            "User-Agent": self._user_agent,
        }
        if ip:
            headers["X-Client-IP"] = ip

        attempt = 0
        while True:
            try:
                return self._once(target, headers, deadline, overall)
            except FoodApiError as e:
                if attempt >= self._max_retries or not _retryable(e):
                    raise
                retry_after = e.retry_after if isinstance(e, FoodApiHTTPError) else None
                delay = retry_after if retry_after else _backoff(attempt)
                if delay > _MAX_RETRY_WAIT:
                    raise  # Not worth waiting here; the caller can decide
                if deadline is not None and time.monotonic() + delay >= deadline:
                    raise  # No time left for another attempt
                self._sleep(delay)
                attempt += 1

    def _once(
        self, target: str, headers: Mapping[str, str], deadline: Optional[float], overall: Optional[float]
    ) -> Tuple[Dict[str, Any], bool]:
        timeout = self._timeout
        if deadline is not None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise FoodApiTimeoutError("no answer within %g s" % overall)
            timeout = min(timeout, remaining)
        try:
            resp = self._transport.get(target, headers, timeout)
        except FoodApiTimeoutError:
            if deadline is not None and time.monotonic() >= deadline:
                raise FoodApiTimeoutError("no answer within %g s" % overall) from None
            raise FoodApiTimeoutError("no answer within %g s" % self._timeout) from None

        body = resp.body
        if (resp.headers.get("Content-Encoding") or "").strip().lower() == "gzip":
            try:
                body = gzip.decompress(body)
            except (OSError, EOFError) as e:
                raise FoodApiServerError(resp.status, "invalid gzip response: %s" % e) from e
        if resp.status != 200:
            raise FoodApiHTTPError.from_status(
                resp.status,
                _error_message(body, resp.status, resp.reason),
                retry_after=_parse_retry_after(resp.headers.get("Retry-After")),
            )
        try:
            decoded = json.loads(body)
        except ValueError as e:  # Includes UnicodeDecodeError
            raise FoodApiServerError(200, "invalid response: %s" % e) from e
        if not isinstance(decoded, dict):
            raise FoodApiServerError(200, "invalid response: not a JSON object")
        return decoded, resp.headers.get("X-Cache") == "HIT"


_T = TypeVar("_T")


def _parse(build: Callable[[], _T]) -> _T:
    """Builds models from a response, turning a malformed one into FoodApiServerError."""
    try:
        return build()
    except (ValueError, TypeError, AttributeError, KeyError) as e:
        raise FoodApiServerError(200, "invalid response: %s" % e) from e


def _retryable(e: FoodApiError) -> bool:
    if isinstance(e, (FoodApiNetworkError, FoodApiTimeoutError, FoodApiRateLimited, FoodApiUnavailable)):
        return True
    return isinstance(e, FoodApiServerError) and e.status_code in (502, 504)


def _backoff(attempt: int) -> float:
    """The wait before retry attempt+1 when the API didn't say: 0.5 s, 1 s, ... with jitter."""
    d = 0.5 * (1 << attempt)
    return random.uniform(d / 2, d)


def _parse_retry_after(value: Optional[str]) -> Optional[float]:
    """Reads a Retry-After header: seconds, or an HTTP date."""
    if not value or not value.strip():
        return None
    value = value.strip()
    if value.isdigit():
        return float(int(value))
    try:
        when = email.utils.parsedate_to_datetime(value)
    except (TypeError, ValueError, IndexError):
        return None
    if when is None:
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    return max((when - datetime.now(timezone.utc)).total_seconds(), 0.0)


def _error_message(body: bytes, status: int, reason: str) -> str:
    try:
        decoded = json.loads(body)
    except ValueError:
        decoded = None
    if isinstance(decoded, dict) and isinstance(decoded.get("message"), str) and decoded["message"]:
        return str(decoded["message"])
    return reason or "HTTP %d" % status


def _check_query(query: Any) -> None:
    if not isinstance(query, str) or not query.strip():
        raise FoodApiInvalidInput("empty query")
    if len(query) > _MAX_QUERY_LENGTH:
        raise FoodApiInvalidInput("query longer than %d characters" % _MAX_QUERY_LENGTH)


def _check_int(name: str, value: Any, low: int, high: int) -> None:
    if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
        raise FoodApiInvalidInput("%s must be between %d and %d" % (name, low, high))


def _check_timeout(value: Any) -> Optional[float]:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not value > 0:
        raise FoodApiInvalidInput("timeout must be a positive number of seconds, not %r" % (value,))
    return float(value)


def _check_ip(ip: Any) -> Optional[str]:
    if not isinstance(ip, str):
        raise FoodApiInvalidInput("client IP must be a string")
    ip = ip.strip()
    if not ip:
        return None
    try:
        ipaddress.ip_address(ip)
    except ValueError:
        raise FoodApiInvalidInput("client IP %r is not an IPv4 or IPv6 address" % ip) from None
    return ip


def _segment(value: Any, what: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise FoodApiInvalidInput("empty " + what)
    return quote(value.strip(), safe=_PATH_SAFE)


def _has_control_chars(value: str) -> bool:
    return any(ord(c) < 0x20 or ord(c) == 0x7F for c in value)


def _meta(body: Mapping[str, Any]) -> Dict[str, Any]:
    meta = body.get("meta")
    return meta if isinstance(meta, dict) else {}


def _meta_str(meta: Mapping[str, Any], key: str, default: str) -> str:
    value = meta.get(key)
    return value if isinstance(value, str) else default


def _meta_int(meta: Mapping[str, Any], key: str, default: int) -> int:
    value = meta.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return default
    return int(value)


def _data_list(body: Mapping[str, Any]) -> List[Any]:
    data = body.get("data")
    if data is None:
        return []
    if not isinstance(data, list):
        raise ValueError("data is not a list")
    return data
