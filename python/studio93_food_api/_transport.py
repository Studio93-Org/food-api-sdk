"""Kept-alive HTTP connections to one server, shared by threads."""

import http.client
import os
import socket
import ssl
import threading
import time
from typing import List, Mapping, NamedTuple, Tuple, Union
from urllib.parse import urlsplit

from .errors import FoodApiInvalidInput, FoodApiNetworkError, FoodApiServerError, FoodApiTimeoutError

_Connection = Union[http.client.HTTPConnection, http.client.HTTPSConnection]

MAX_BODY = 32 << 20  # Larger answers are refused
_CHUNK = 64 << 10


class Response(NamedTuple):
    status: int
    reason: str
    headers: http.client.HTTPMessage
    body: bytes  # As received; possibly gzipped (see headers["Content-Encoding"])


class _Stale(Exception):
    """A kept-alive connection turned out to be closed by the server before it answered."""


class Transport:
    """A pool of kept-alive connections to one server. Each request takes an idle connection or opens a new one,
    and gives it back when the whole answer has been read, so threads never share a connection. At most
    ``max_idle`` connections are kept open between requests."""

    def __init__(self, base_url: str, max_idle: int) -> None:
        parts = urlsplit(base_url)
        if parts.scheme not in ("http", "https") or not parts.hostname:
            raise FoodApiInvalidInput("base_url must be an http or https URL, not %r" % base_url)
        self.scheme = parts.scheme
        self.host = parts.hostname
        self.port = parts.port
        self.base_path = parts.path.rstrip("/")
        self._ssl = ssl.create_default_context() if self.scheme == "https" else None
        self._max_idle = max(max_idle, 0)
        self._lock = threading.Lock()
        self._idle: List[_Connection] = []
        self._pid = os.getpid()

    def get(self, path: str, headers: Mapping[str, str], timeout: float) -> Response:
        """Sends a GET request and reads the whole answer within ``timeout`` seconds. A kept-alive connection the
        server has closed in the meantime is replaced and the request sent again at once."""
        deadline = time.monotonic() + timeout
        conn, reused = self._take()
        try:
            return self._send(conn, path, headers, deadline, reused)
        except _Stale:
            return self._send(self._new(), path, headers, deadline, False)

    def close(self) -> None:
        """Closes the idle connections. Later requests open new ones."""
        with self._lock:
            idle, self._idle = self._idle, []
        for conn in idle:
            conn.close()

    def _take(self) -> Tuple[_Connection, bool]:
        with self._lock:
            if self._pid != os.getpid():
                # A forked child must not share its parent's sockets: forget them (the parent keeps using them)
                self._idle, self._pid = [], os.getpid()
            if self._idle:
                return self._idle.pop(), True
        return self._new(), False

    def _give_back(self, conn: _Connection) -> None:
        if conn.sock is not None:
            with self._lock:
                if len(self._idle) < self._max_idle and self._pid == os.getpid():
                    self._idle.append(conn)
                    return
        conn.close()

    def _new(self) -> _Connection:
        if self._ssl is not None:
            return http.client.HTTPSConnection(self.host, self.port, context=self._ssl)
        return http.client.HTTPConnection(self.host, self.port)

    def _send(
        self, conn: _Connection, path: str, headers: Mapping[str, str], deadline: float, reused: bool
    ) -> Response:
        answered = False
        try:
            _set_timeout(conn, deadline)
            conn.request("GET", path, headers=dict(headers))
            _set_timeout(conn, deadline)
            resp = conn.getresponse()
            answered = True
            body = _read(conn, resp, deadline)
        except (socket.timeout, TimeoutError) as e:
            conn.close()
            raise FoodApiTimeoutError("no answer in time") from e
        except (ConnectionError, http.client.BadStatusLine) as e:
            conn.close()
            if reused and not answered:
                raise _Stale() from e
            raise FoodApiNetworkError(_describe(e), e) from e
        except (OSError, http.client.HTTPException) as e:
            conn.close()
            raise FoodApiNetworkError(_describe(e), e) from e
        except BaseException:
            conn.close()
            raise
        if resp.will_close:
            conn.close()
        else:
            self._give_back(conn)
        return Response(resp.status, resp.reason or "", resp.headers, body)


def _set_timeout(conn: _Connection, deadline: float) -> None:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise socket.timeout("timed out")
    conn.timeout = remaining  # Connecting (and the TLS handshake) use this
    if conn.sock is not None:
        conn.sock.settimeout(remaining)


def _read(conn: _Connection, resp: http.client.HTTPResponse, deadline: float) -> bytes:
    chunks: List[bytes] = []
    size = 0
    while True:
        _set_timeout(conn, deadline)
        chunk = resp.read(_CHUNK)
        if not chunk:
            return b"".join(chunks)
        size += len(chunk)
        if size > MAX_BODY:
            conn.close()
            raise FoodApiServerError(resp.status, "response larger than %d bytes" % MAX_BODY)
        chunks.append(chunk)


def _describe(e: BaseException) -> str:
    text = str(e)
    return "%s: %s" % (type(e).__name__, text) if text else type(e).__name__

