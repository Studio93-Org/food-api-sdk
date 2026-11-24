import dataclasses
import gzip
import json
import threading
import time
import unittest
from email.utils import formatdate
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable, Dict, List, Optional, Tuple
from urllib.parse import parse_qs, urlsplit

from studio93_food_api import (
    VERSION,
    FoodApiBadRequest,
    FoodApiClient,
    FoodApiError,
    FoodApiForbidden,
    FoodApiHTTPError,
    FoodApiInvalidInput,
    FoodApiNetworkError,
    FoodApiNotFound,
    FoodApiRateLimited,
    FoodApiServerError,
    FoodApiTimeoutError,
    FoodApiUnauthorized,
    FoodApiUnavailable,
    FoodType,
    ImageMatch,
    ImageTier,
    NutrientFlag,
)
from studio93_food_api.client import _parse_retry_after

FOOD: Dict[str, Any] = {
    "id": "01a163d2-bfdc-7912-878d-4020b11915ab",
    "name": "Cola",
    "brand": None,
    "type": "generic",
    "barcodes": [],
    "servings": [
        {
            "description": "100 g",
            "measurement": "g",
            "metric_amount": 100,
            "metric_unit": "g",
            "units": 100,
            "nutrients": {"calories": 37, "protein": 0, "sugar": 0.5, "fiber": None, "cnf_409": 0.01},
        },
        {
            "description": "1 fl oz",
            "measurement": "fl oz",
            "metric_amount": 29.57,
            "metric_unit": "ml",
            "units": 1,
            "generic": True,
            "nutrients": {"calories": 10.94},
        },
    ],
    "source": {"provider": "CNF", "id": "2920"},
    "ingredients": None,
    "category": "Beverages",
    "attributes": {"alternate_names": "pop, soda, soft drink"},
    "nutrient_flags": {"sugar": "upper_bound"},
}


def with_image(key: str, match: str) -> Dict[str, Any]:
    food = dict(FOOD)
    food["image"] = {"key": key, "url": "https://images.example.com/%s.jpg" % key, "match": match}
    return food


class Request:
    def __init__(self, h: BaseHTTPRequestHandler) -> None:
        parts = urlsplit(h.path)
        self.raw_path = parts.path
        self.query = {k: v[0] for k, v in parse_qs(parts.query).items()}
        self.raw_query = parts.query
        self.headers = h.headers
        self.port = h.client_address[1]


Handler = Callable[[BaseHTTPRequestHandler, Request], None]


def reply(
    h: BaseHTTPRequestHandler,
    status: int = 200,
    body: Any = None,
    headers: Optional[Dict[str, str]] = None,
    raw: Optional[bytes] = None,
) -> None:
    data = raw if raw is not None else json.dumps(body if body is not None else {}).encode()
    h.send_response(status)
    h.send_header("Content-Type", "application/json")
    h.send_header("Content-Length", str(len(data)))
    for k, v in (headers or {}).items():
        h.send_header(k, v)
    h.end_headers()
    h.wfile.write(data)


class FakeAPI:
    """A local HTTP/1.1 server with keep-alive that records requests and answers with a test's handler."""

    def __init__(self, handler: Handler) -> None:
        self.handler = handler
        self.requests: List[Request] = []
        self._lock = threading.Lock()
        api = self

        class H(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_GET(self) -> None:
                req = Request(self)
                with api._lock:
                    api.requests.append(req)
                api.handler(self, req)

            def log_message(self, format: str, *args: Any) -> None:
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, args=(0.02,), daemon=True)
        self.thread.start()
        self.url = "http://127.0.0.1:%d" % self.server.server_address[1]

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()


class ClientTest(unittest.TestCase):
    def serve(self, handler: Handler, **kwargs: Any) -> Tuple[FoodApiClient, FakeAPI, List[float]]:
        """A client for a fake API, and the waits its retries asked for (recorded, not slept)."""
        api = FakeAPI(handler)
        self.addCleanup(api.close)
        client = FoodApiClient("test-key", base_url=kwargs.pop("base_url", api.url), **kwargs)
        self.addCleanup(client.close)
        waits: List[float] = []
        client._sleep = waits.append
        return client, api, waits


class TestCalls(ClientTest):
    def test_search_sends_the_query_and_key_and_parses_the_page(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            reply(
                h,
                body={
                    "data": [FOOD],
                    "meta": {"query": "cola zero", "page": 2, "limit": 5, "total": 11, "source": "catalog"},
                },
                headers={"X-Cache": "HIT"},
            )

        client, api, _ = self.serve(handle, user_agent="my-app/1.0")
        page = client.search("Cola  Zero", page=2, limit=5)

        r = api.requests[0]
        self.assertEqual(r.raw_path, "/v2/foods/search")
        self.assertEqual(r.query, {"q": "Cola  Zero", "page": "2", "limit": "5"})
        self.assertEqual(r.headers["Authorization"], "Bearer test-key")
        self.assertEqual(r.headers["User-Agent"], "my-app/1.0 studio93-food-api-python/" + VERSION)
        self.assertEqual(r.headers["Accept"], "application/json")
        self.assertIn("gzip", r.headers["Accept-Encoding"])
        self.assertIsNone(r.headers.get("X-Client-IP"))

        self.assertEqual(
            (page.query, page.page, page.limit, page.total, page.source), ("cola zero", 2, 5, 11, "catalog")
        )
        self.assertTrue(page.cached)
        self.assertIsNone(page.region)
        self.assertIsNone(page.brand)
        food = page.foods[0]
        self.assertEqual(food.type, FoodType.GENERIC)
        self.assertEqual((food.source.provider, food.source.id), ("CNF", "2920"))
        self.assertEqual(food.category, "Beverages")
        self.assertIsNone(food.brand)
        self.assertIsNone(food.ingredients)
        n = food.servings[0].nutrients
        self.assertEqual(n.calories, 37.0)
        self.assertEqual(n.protein, 0.0)
        self.assertIsNone(n.fiber)  # Unknown (null)
        self.assertIsNone(n.vitamin_d)  # Absent
        self.assertEqual(n.get("cnf_409"), 0.01)
        self.assertEqual(food.servings[0].metric_amount, 100.0)
        self.assertFalse(food.servings[0].generic)
        self.assertTrue(food.servings[1].generic)
        self.assertEqual(food.servings[1].description, "1 fl oz")
        self.assertIs(food.flag("sugar"), NutrientFlag.UPPER_BOUND)
        self.assertIsNone(food.flag("protein"))
        self.assertEqual(food.alternate_names, ["pop", "soda", "soft drink"])
        self.assertIsNone(food.image)

    def test_search_defaults_send_only_the_query(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            reply(h, body={"data": [], "meta": {"query": "apple", "page": 0, "limit": 20, "total": 0}})

        client, api, _ = self.serve(handle)
        page = client.search("apple")
        self.assertEqual(api.requests[0].raw_query, "q=apple")
        self.assertEqual((page.page, page.limit, page.source, page.cached), (0, 20, "catalog", False))

    def test_search_reports_the_region_and_brand(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            reply(h, body={"data": [], "meta": {"query": "coke", "total": 0, "region": "GB", "brand": "Coca-Cola"}})

        client, _, _ = self.serve(handle)
        page = client.search("coke")
        self.assertEqual((page.region, page.brand), ("GB", "Coca-Cola"))

    def test_autocomplete(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            reply(
                h,
                body={
                    "data": [
                        {"id": "a", "name": "Chicken breast", "brand": None},
                        {"id": "b", "name": "Chick peas", "brand": "Acme"},
                    ],
                    "meta": {"query": "chick", "limit": 5, "total": 2},
                },
            )

        client, api, _ = self.serve(handle)
        result = client.autocomplete("chick", 5)
        self.assertEqual(api.requests[0].raw_path, "/v2/foods/autocomplete")
        self.assertEqual(api.requests[0].query, {"q": "chick", "limit": "5"})
        self.assertEqual([s.name for s in result.suggestions], ["Chicken breast", "Chick peas"])
        self.assertEqual(result.suggestions[1].brand, "Acme")
        self.assertEqual((result.query, result.limit, result.total), ("chick", 5, 2))

    def test_empty_results_are_empty_lists(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            reply(h, body={"data": None, "meta": {"query": "xq", "total": 0}})

        client, _, _ = self.serve(handle)
        self.assertEqual(client.search("xqzw").foods, [])
        self.assertEqual(client.autocomplete("xq").suggestions, [])

    def test_foods_carry_their_image(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            if r.raw_path == "/v2/foods/cheddar":
                reply(h, body={"data": with_image("dairy/cheddar", "food")})
            elif r.raw_path == "/v2/foods/barcode/3017624010701":
                reply(h, body={"data": with_image("generic/plate", "fallback")})
            else:
                reply(h, body={"data": with_image("dairy/cheese", "something_new")})

        client, _, _ = self.serve(handle)
        image = client.food("cheddar").image
        assert image is not None
        self.assertEqual(image.key, "dairy/cheddar")
        self.assertEqual(image.url, "https://images.example.com/dairy/cheddar.jpg")
        self.assertIs(image.match, ImageMatch.FOOD)
        self.assertFalse(image.is_fallback)

        fallback = client.food_by_barcode("3017624010701").image
        assert fallback is not None
        self.assertTrue(fallback.is_fallback)

        newer = client.food("gouda").image  # A match newer than the SDK still parses
        assert newer is not None
        self.assertIs(newer.match, ImageMatch.UNKNOWN)
        self.assertFalse(newer.is_fallback)

    def test_unknown_enum_values_are_tolerated(self) -> None:
        food = dict(FOOD, type="meal_kit", nutrient_flags={"sugar": "estimated_somehow"}, extra_field={"x": 1})

        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            reply(h, body={"data": food})

        client, _, _ = self.serve(handle)
        parsed = client.food("x")
        self.assertIs(parsed.type, FoodType.UNKNOWN)
        self.assertIs(parsed.flag("sugar"), NutrientFlag.UNKNOWN)

    def test_the_image_set_parses(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            reply(
                h,
                body={
                    "data": {
                        "version": 1,
                        "updated": "2026-11-17",
                        "fallback": "generic/plate",
                        "groups": [{"key": "dairy", "label": "Milk and dairy"}],
                        "images": [
                            {"key": "dairy/milk", "label": "Milk", "tier": "category", "group": "dairy",
                             "category": "dairy/milk", "url": "https://images.example.com/dairy/milk.jpg"},
                            {"key": "dairy/milk-whole", "label": "Whole milk", "tier": "variant", "group": "dairy",
                             "category": "dairy/milk", "parent": "dairy/milk",
                             "url": "https://images.example.com/dairy/milk-whole.jpg"},
                            {"key": "dairy/kefir", "label": "Kefir", "tier": "brand_new", "group": "dairy",
                             "category": "dairy/milk", "url": "https://images.example.com/dairy/kefir.jpg"},
                        ],
                    }
                },
            )

        client, api, _ = self.serve(handle)
        images = client.images()
        self.assertEqual(api.requests[0].raw_path, "/v2/images")
        self.assertEqual((images.version, images.updated, images.fallback), (1, "2026-11-17", "generic/plate"))
        self.assertEqual(images.groups[0].label, "Milk and dairy")
        whole = images.image("dairy/milk-whole")
        assert whole is not None
        self.assertIs(whole.tier, ImageTier.VARIANT)
        self.assertEqual(
            (whole.parent, whole.category, whole.group, whole.label),
            ("dairy/milk", "dairy/milk", "dairy", "Whole milk"),
        )
        milk = images.image("dairy/milk")
        assert milk is not None
        self.assertIs(milk.tier, ImageTier.CATEGORY)
        self.assertIsNone(milk.parent)
        self.assertEqual(milk.url, "https://images.example.com/dairy/milk.jpg")
        kefir = images.image("dairy/kefir")
        assert kefir is not None
        self.assertIs(kefir.tier, ImageTier.UNKNOWN)
        self.assertIsNone(images.image("dairy/yak-butter"))

    def test_an_empty_image_set_has_empty_lists(self) -> None:
        client, _, _ = self.serve(lambda h, r: reply(h, body={"data": {"version": 1, "groups": None}}))
        images = client.images()
        self.assertEqual((images.groups, images.images), ([], []))

    def test_barcode_links_are_escaped_into_the_path(self) -> None:
        client, api, _ = self.serve(lambda h, r: reply(h, body={"data": FOOD}))
        client.food_by_barcode(" https://id.gs1.org/01/03017624010701 ")
        client.food_by_barcode("(01)03017624010701")
        self.assertEqual(api.requests[0].raw_path, "/v2/foods/barcode/https:%2F%2Fid.gs1.org%2F01%2F03017624010701")
        self.assertEqual(api.requests[1].raw_path, "/v2/foods/barcode/%2801%2903017624010701")

    def test_nutrient_stats_and_the_nutrient_list_parse(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            if r.raw_path == "/v2/foods/abc/nutrient-stats":
                reply(h, body={"data": {"id": "abc", "per": "100 g", "nutrients": {"protein": {
                    "data_points": 12, "min": 3.12, "derivation": "A", "derivation_description": "Analytical"}}}})
            elif r.raw_path == "/v2/nutrients":
                reply(h, body={"data": {
                    "nutrients": [
                        {"key": "calories", "name": "Energy", "unit": "kcal", "group": "energy", "core": True}
                    ],
                    "other": [{"key": "usda_1018", "name": "Ash", "unit": "g", "source": "USDA"}]}})
            else:
                reply(h, 404, {"message": "unexpected"})

        client, _, _ = self.serve(handle)
        stats = client.nutrient_stats("abc")
        protein = stats.nutrients["protein"]
        self.assertEqual((stats.food_id, stats.per), ("abc", "100 g"))
        self.assertEqual((protein.data_points, protein.min, protein.derivation_description), (12, 3.12, "Analytical"))
        self.assertIsNone(protein.max)
        listed = client.nutrients()
        self.assertTrue(listed.nutrients[0].core)
        self.assertEqual(listed.nutrients[0].unit, "kcal")
        self.assertEqual(listed.other[0].key, "usda_1018")

    def test_a_base_url_with_a_path(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            reply(h, body={"data": FOOD})

        api = FakeAPI(handle)
        self.addCleanup(api.close)
        with FoodApiClient("k", base_url=api.url + "/proxy/") as client:
            client.food("x")
        self.assertEqual(api.requests[0].raw_path, "/proxy/v2/foods/x")

    def test_gzipped_answers_are_decoded(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            reply(h, raw=gzip.compress(json.dumps({"data": FOOD}).encode()), headers={"Content-Encoding": "gzip"})

        client, _, _ = self.serve(handle)
        self.assertEqual(client.food("x").name, "Cola")

    def test_models_convert_to_json(self) -> None:
        client, _, _ = self.serve(lambda h, r: reply(h, body={"data": with_image("dairy/cheddar", "food")}))
        data = json.loads(json.dumps(dataclasses.asdict(client.food("x"))))
        self.assertEqual(data["servings"][0]["nutrients"]["calories"], 37.0)
        self.assertEqual(data["image"]["match"], "food")
        self.assertEqual(data["nutrient_flags"], {"sugar": "upper_bound"})


class TestErrors(ClientTest):
    def test_error_statuses_become_typed_errors(self) -> None:
        cases = {
            400: FoodApiBadRequest,
            401: FoodApiUnauthorized,
            403: FoodApiForbidden,
            404: FoodApiNotFound,
            429: FoodApiRateLimited,
            503: FoodApiUnavailable,
            500: FoodApiServerError,
            502: FoodApiServerError,
            418: FoodApiServerError,
        }
        for status, cls in cases.items():
            with self.subTest(status=status):
                client, _, _ = self.serve(
                    lambda h, r, s=status: reply(h, s, {"message": "explained", "data": {}}), max_retries=0
                )
                with self.assertRaises(cls) as caught:
                    client.food("01a163d2-bfdc-7912-878d-4020b11915ab")
                err = caught.exception
                self.assertIsInstance(err, FoodApiHTTPError)
                self.assertIsInstance(err, FoodApiError)
                self.assertEqual((err.status_code, err.message), (status, "explained"))
                if status != 404:
                    self.assertNotIsInstance(err, FoodApiNotFound)

    def test_an_error_without_a_json_message_uses_the_reason(self) -> None:
        client, _, _ = self.serve(lambda h, r: reply(h, 404, raw=b"<html>nope</html>"))
        with self.assertRaises(FoodApiNotFound) as caught:
            client.food("x")
        self.assertEqual(caught.exception.message, "Not Found")

    def test_an_invalid_answer_is_a_server_error_and_not_retried(self) -> None:
        client, api, waits = self.serve(lambda h, r: reply(h, raw=b"not json"))
        with self.assertRaises(FoodApiServerError) as caught:
            client.food("x")
        self.assertEqual(caught.exception.status_code, 200)
        self.assertEqual((len(api.requests), waits), (1, []))

    def test_an_answer_missing_required_fields_is_a_server_error(self) -> None:
        client, _, _ = self.serve(lambda h, r: reply(h, body={"data": {"name": "no id"}}))
        with self.assertRaises(FoodApiServerError):
            client.food("x")


class TestRetries(ClientTest):
    def test_retries_honour_retry_after(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            if len(api.requests) == 1:
                reply(h, 503, {"message": "search is busy, please retry in a few seconds"}, {"Retry-After": "2"})
            else:
                reply(h, body={"data": FOOD})

        client, api, waits = self.serve(handle)
        self.assertEqual(client.food("x").name, "Cola")
        self.assertEqual((len(api.requests), waits), (2, [2.0]))

    def test_gives_up_after_max_retries_backing_off_without_retry_after(self) -> None:
        client, api, waits = self.serve(lambda h, r: reply(h, 429, {"message": "slow down"}))
        with self.assertRaises(FoodApiRateLimited):
            client.food("x")
        self.assertEqual(len(api.requests), 3)
        self.assertEqual(len(waits), 2)
        self.assertTrue(0.25 <= waits[0] <= 0.5 and 0.5 <= waits[1] <= 1.0, waits)

    def test_502_and_504_are_retried_500_is_not(self) -> None:
        for status, attempts in ((502, 3), (504, 3), (500, 1)):
            with self.subTest(status=status):
                client, api, _ = self.serve(lambda h, r, s=status: reply(h, s, {"message": "x"}))
                with self.assertRaises(FoodApiServerError):
                    client.food("x")
                self.assertEqual(len(api.requests), attempts)

    def test_a_long_retry_after_is_left_to_the_caller(self) -> None:
        client, api, waits = self.serve(lambda h, r: reply(h, 503, {"message": "down"}, {"Retry-After": "60"}))
        with self.assertRaises(FoodApiUnavailable) as caught:
            client.food("x")
        self.assertEqual(caught.exception.retry_after, 60.0)
        self.assertEqual((len(api.requests), waits), (1, []))

    def test_not_found_and_other_client_errors_are_not_retried(self) -> None:
        for status in (400, 401, 403, 404):
            with self.subTest(status=status):
                client, api, waits = self.serve(lambda h, r, s=status: reply(h, s, {"message": "x"}))
                with self.assertRaises(FoodApiHTTPError):
                    client.food("x")
                self.assertEqual((len(api.requests), waits), (1, []))

    def test_max_retries_zero_turns_retries_off(self) -> None:
        client, api, _ = self.serve(lambda h, r: reply(h, 503, {"message": "x"}), max_retries=0)
        with self.assertRaises(FoodApiUnavailable):
            client.food("x")
        self.assertEqual(len(api.requests), 1)

    def test_network_errors_are_retried_then_reported(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            h.close_connection = True  # Hang up without answering

        client, api, waits = self.serve(handle)
        with self.assertRaises(FoodApiNetworkError):
            client.food("x")
        self.assertEqual((len(api.requests), len(waits)), (3, 2))

    def test_a_connection_refused_is_a_network_error(self) -> None:
        api = FakeAPI(lambda h, r: None)
        url = api.url
        api.close()  # Nothing listens there now
        client = FoodApiClient("k", base_url=url, max_retries=1)
        waits: List[float] = []
        client._sleep = waits.append
        with self.assertRaises(FoodApiNetworkError):
            client.food("x")
        self.assertEqual(len(waits), 1)

    def test_parse_retry_after(self) -> None:
        self.assertEqual(_parse_retry_after("3"), 3.0)
        self.assertIsNone(_parse_retry_after(""))
        self.assertIsNone(_parse_retry_after(None))
        self.assertIsNone(_parse_retry_after("soon"))
        when = _parse_retry_after(formatdate(time.time() + 5, usegmt=True))
        assert when is not None
        self.assertTrue(0 < when <= 5, when)
        self.assertEqual(_parse_retry_after(formatdate(time.time() - 60, usegmt=True)), 0.0)


class TestConnections(ClientTest):
    def test_one_connection_is_kept_open_between_calls(self) -> None:
        client, api, _ = self.serve(lambda h, r: reply(h, body={"data": FOOD}))
        for _ in range(3):
            client.food("x")
        self.assertEqual(len({r.port for r in api.requests}), 1)

    def test_a_connection_the_server_closed_is_replaced_at_once(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            reply(h, body={"data": FOOD})
            h.close_connection = True  # Without saying so: the client keeps the connection

        client, api, waits = self.serve(handle)
        client.food("x")
        time.sleep(0.05)  # Let the server close it
        self.assertEqual(client.food("y").name, "Cola")
        self.assertEqual(len(api.requests), 2)
        self.assertEqual(waits, [])  # Reconnected without a retry
        self.assertEqual(len({r.port for r in api.requests}), 2)

    def test_concurrent_calls_from_many_threads(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            time.sleep(0.01)
            reply(h, body={"data": dict(FOOD, id=r.raw_path.rsplit("/", 1)[1])})

        client, api, _ = self.serve(handle)
        errors: List[BaseException] = []

        def work(n: int) -> None:
            try:
                for i in range(5):
                    food_id = "t%d-%d" % (n, i)
                    if client.food(food_id).id != food_id:
                        errors.append(AssertionError("crossed answers for " + food_id))
            except BaseException as e:  # noqa: B902
                errors.append(e)

        threads = [threading.Thread(target=work, args=(n,)) for n in range(8)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(errors, [])
        self.assertEqual(len(api.requests), 40)
        self.assertLessEqual(len({r.port for r in api.requests}), 16)

    def test_a_slow_attempt_times_out(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            time.sleep(0.5)
            reply(h, body={"data": FOOD})

        client, _, _ = self.serve(handle, timeout=0.1, max_retries=0)
        start = time.monotonic()
        with self.assertRaises(FoodApiTimeoutError):
            client.food("x")
        self.assertLess(time.monotonic() - start, 0.4)

    def test_attempt_timeouts_are_retried(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            if len(api.requests) == 1:
                time.sleep(0.5)
            reply(h, body={"data": FOOD})

        client, api, waits = self.serve(handle, timeout=0.1)
        self.assertEqual(client.food("x").name, "Cola")
        self.assertEqual(len(waits), 1)

    def test_a_call_timeout_limits_the_whole_call(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            time.sleep(1)
            reply(h, body={"data": FOOD})

        client, api, waits = self.serve(handle)
        start = time.monotonic()
        with self.assertRaises(FoodApiTimeoutError) as caught:
            client.search("apple", timeout=0.2)
        self.assertLess(time.monotonic() - start, 0.6)
        self.assertIn("0.2", caught.exception.message)
        self.assertEqual(waits, [])  # No time left to retry

    def test_a_call_timeout_stops_retries_that_would_outlast_it(self) -> None:
        client, api, waits = self.serve(lambda h, r: reply(h, 503, {"message": "busy"}, {"Retry-After": "1"}))
        with self.assertRaises(FoodApiUnavailable):
            client.food("x", timeout=0.5)
        self.assertEqual((len(api.requests), waits), (1, []))


class TestClientIP(ClientTest):
    def test_client_ip_is_sent_per_call_and_per_client(self) -> None:
        def handle(h: BaseHTTPRequestHandler, r: Request) -> None:
            reply(h, body={"data": [], "meta": {"query": "cheddar", "total": 0, "region": "GB"}})

        client, api, _ = self.serve(handle)
        self.assertEqual(client.search("cheddar", client_ip=" 81.2.69.160 ").region, "GB")
        client.search("cheddar")
        user = client.with_client_ip("2001:db8::1")
        user.autocomplete("ched")
        user.search("ched", client_ip="81.2.69.161")  # The call's address wins
        client.search("cheddar")  # The original client is unchanged
        sent = [r.headers.get("X-Client-IP") for r in api.requests]
        self.assertEqual(sent, ["81.2.69.160", None, "2001:db8::1", "81.2.69.161", None])
        self.assertEqual(len({r.port for r in api.requests}), 1)  # A per-user client shares the connections

    def test_an_invalid_address_fails_before_a_request(self) -> None:
        client, api, _ = self.serve(lambda h, r: reply(h, body={"data": FOOD}))
        with self.assertRaises(FoodApiInvalidInput):
            client.food("x", client_ip="81.2.69")
        with self.assertRaises(FoodApiInvalidInput):
            client.with_client_ip("not an address")
        with self.assertRaises(FoodApiInvalidInput):
            client.food("x", client_ip="81.2.69.160\r\nX-Evil: 1")
        self.assertEqual(api.requests, [])


class TestInvalidInput(ClientTest):
    def test_invalid_input_sends_nothing(self) -> None:
        client, api, _ = self.serve(lambda h, r: reply(h, body={}))
        calls: List[Callable[[], Any]] = [
            lambda: client.search("  "),
            lambda: client.search("a" * 201),
            lambda: client.search("apple", limit=51),
            lambda: client.search("apple", limit=0),
            lambda: client.search("apple", page=-1),
            lambda: client.search("apple", page=1001),
            lambda: client.search("apple", page="1"),  # type: ignore[arg-type]
            lambda: client.search(None),  # type: ignore[arg-type]
            lambda: client.autocomplete("app", 21),
            lambda: client.food(" "),
            lambda: client.food_by_barcode(""),
            lambda: client.nutrient_stats(""),
            lambda: client.food("x", timeout=0),
        ]
        for i, call in enumerate(calls):
            with self.subTest(i=i):
                with self.assertRaises(FoodApiInvalidInput):
                    call()
        self.assertEqual(api.requests, [])
        self.assertTrue(issubclass(FoodApiInvalidInput, ValueError))

    def test_a_200_character_query_is_allowed(self) -> None:
        client, api, _ = self.serve(lambda h, r: reply(h, body={"data": [], "meta": {}}))
        client.search("é" * 200)
        self.assertEqual(len(api.requests), 1)

    def test_constructor_checks(self) -> None:
        for kwargs in ({"base_url": "ftp://example.com"}, {"timeout": -1}, {"user_agent": "a\nb"}):
            with self.subTest(kwargs=kwargs):
                with self.assertRaises(FoodApiInvalidInput):
                    FoodApiClient("k", **kwargs)
        with self.assertRaises(FoodApiInvalidInput):
            FoodApiClient("key\r\nX-Evil: 1")

    def test_the_key_stays_out_of_repr(self) -> None:
        self.assertNotIn("secret", repr(FoodApiClient("secret-key")))


if __name__ == "__main__":
    unittest.main()
