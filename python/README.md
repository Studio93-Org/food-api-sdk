# studio93-food-api (Python)

Python client for the [Studio93 Food API](https://api.studio93.io/food/docs) (v2): typo-tolerant food search,
autocomplete, barcode lookups and detailed nutrition. Made for servers, scripts and AI agents. You need a v2 API key
from Studio93; a v1 key gets a 403 error.

## Install

It is installed from this repository (public, so no credentials are needed) by tag. With pip:

```bash
pip install "studio93-food-api @ git+https://github.com/Studio93-Org/food-api-sdk.git@py-v0.4.0#subdirectory=python"
```

In `requirements.txt`:

```text
studio93-food-api @ git+https://github.com/Studio93-Org/food-api-sdk.git@py-v0.4.0#subdirectory=python
```

The same line works in `pyproject.toml` dependencies, and with Poetry or uv. It needs Python 3.9 or newer and has no
dependencies beyond the standard library. To upgrade, change the tag to a newer `py-v…` one.

## Use

```python
import os
from studio93_food_api import FoodApiClient

# Create one client and share it: it keeps connections open and is safe to use from many threads
client = FoodApiClient(os.environ["FOOD_API_KEY"], user_agent="my-service/1.0")

page = client.search("greek yogurt")  # Typos are fine: "chiken brest" works
for food in page.foods:
    print(food.name, food.servings[0].nutrients.calories)
```

| Call | Returns |
|---|---|
| `client.search(query, page=0, limit=None)` | a `SearchPage` of foods (`page` is zero-based, `limit` 1 to 50, default 20); `region` is the country ranked first and `brand` the brand the query names ("Coca-Cola" for "coke"), if any |
| `client.autocomplete(query, limit=None)` | an `AutocompleteResult`: suggestions for what has been typed so far (`limit` 1 to 20, default 8) |
| `client.food(id)` | one `Food` by its catalog ID |
| `client.food_by_barcode(scanned)` | the `Food` for a barcode, GS1 code or GS1 Digital Link, passed as read |
| `client.nutrient_stats(id)` | `NutrientStats`: how each of a food's nutrient values was obtained |
| `client.nutrients()` | a `NutrientList`: every nutrient key, with its name and unit |
| `client.images()` | the `ImageSet`: every food image, with its label, group and URL |
| `client.with_client_ip(ip)` | a client for calls made for one of your users (see below) |

Every call also takes `client_ip=` (the user's address, see below) and `timeout=` (seconds the whole call may take,
retries included). A query nothing matches returns an empty page. Invalid arguments raise `FoodApiInvalidInput`
(a `ValueError`) without a request.

The client is one object for the whole process: create it at startup (a module-level variable, your app's
settings or dependency injection) rather than per request, so only the first request pays for the TCP and TLS
handshake. `client.close()`, or `with FoodApiClient(...) as client:`, closes its connections. After a fork (for
example gunicorn workers) each process opens its own connections. `FoodApiClient(...)` also takes `base_url=`,
`timeout=` (per attempt, default 15 seconds), `max_retries=` (default 2) and `max_idle_connections=` (default 16).

## Calling for your users

When your server calls the API for its users, pass each user's IP address. Search then ranks for the user's country
instead of your server's (when your key has regional ranking), and `page.region` says which country's foods came
first:

```python
page = client.search("cheddar cheese", client_ip=user_ip)  # The user's address, e.g. from your load balancer

# Or a client for one user, for every call made while handling their request; it shares the connections
user_client = client.with_client_ip(user_ip)
page = user_client.search("cheddar cheese")
```

It is sent as the `X-Client-IP` header. Rate limits still apply to your server's own address. An address that
isn't IPv4 or IPv6 raises `FoodApiInvalidInput` without a request.

## Search as you type

Python has no way to stop a blocking call from outside, so the SDK has no cancellation. Give a search a short
`timeout=` instead (it covers retries too) and drop answers to queries the user has typed past:

```python
latest = text
page = client.autocomplete(text, timeout=2)
if text == latest:
    show(page.suggestions)
```

`autocomplete` never asks outside providers, so it is fast enough for every keystroke; look a picked suggestion up
with `client.food(suggestion.id)`. In asyncio code, run calls in a thread (`await asyncio.to_thread(client.search,
text)`); cancelling the task drops the answer, and the request ends within its timeout.

## Errors

Every failure is a `FoodApiError` with a `message`. Catch the subclasses to show the right message:

```python
from studio93_food_api import (FoodApiError, FoodApiNetworkError, FoodApiNotFound, FoodApiRateLimited,
                               FoodApiTimeoutError, FoodApiUnavailable)

try:
    food = client.food_by_barcode(scanned)
except FoodApiNotFound:
    ...  # No source knows this barcode: an answer, not a failure
except (FoodApiRateLimited, FoodApiUnavailable) as e:
    ...  # Already retried; e.retry_after says when to try again (seconds, or None)
except (FoodApiNetworkError, FoodApiTimeoutError):
    ...  # The API couldn't be reached
except FoodApiError as e:
    raise RuntimeError(e.message) from e
```

| Error | When |
|---|---|
| `FoodApiBadRequest` | 400: a parameter is missing or invalid |
| `FoodApiUnauthorized` | 401: the API key is missing, invalid or revoked |
| `FoodApiForbidden` | 403: the key may not make the call (for example a v1 key) |
| `FoodApiNotFound` | 404: no such food or barcode |
| `FoodApiRateLimited` | 429: too many requests |
| `FoodApiUnavailable` | 503: busy or briefly down |
| `FoodApiServerError` | any other error status, or an answer the SDK couldn't read |
| `FoodApiNetworkError` | no connection, DNS failure, connection reset |
| `FoodApiTimeoutError` | an attempt, or the call's `timeout=`, ran out |
| `FoodApiInvalidInput` | invalid arguments; nothing was sent |

The HTTP ones are `FoodApiHTTPError`s, with `status_code`, `message` (the API's explanation) and `retry_after`.
Network errors, timeouts and 429, 502, 503 and 504 responses are retried twice, waiting as long as the API's
`Retry-After` asks (up to 10 seconds; a longer wait is raised to you). A kept-alive connection the server has closed
is replaced at once without counting as a retry.

## Nutrition

Each serving's nutrients are a dict of numbers, None when unknown. The 17 core nutrients have properties; read any
other key with `get`. `client.nutrients()` lists every key with its name and unit.

```python
n = food.servings[0].nutrients  # The source's first serving
print(n.calories, n.protein, n.get("magnesium"))

if food.flag("sugar") is NutrientFlag.UPPER_BOUND:
    ...  # The label said "less than": show "< x g"
```

A food's servings start with its source's own and end with generic ones (`serving.generic`): 100 g and 1 oz for
solids, plus 1 cup or 1 tbsp and 1 tsp where the source measures the food that way; 100 ml, 1 fl oz, 1 cup, 1 tbsp
and 1 tsp for liquids. A food measured only by volume ("1/2 cup") gets the other volumes but no weights; one
measured by neither ("1 serving") gets none.

Flags mark values that aren't plain measurements: `NutrientFlag.UPPER_BOUND`, `APPROXIMATE` and `ASSUMED_ZERO`.
`food.alternate_names` has the other names a source gives the food, and `client.nutrient_stats(food.id)` the
details behind each value (samples, spread, how it was obtained) where the source gives them.

## Images

Every food comes with a picture, `food.image` (None in answers from before the API had images): a 256 px JPEG at a
public URL that needs no API key and never changes, so cache it for good. `match` says how close it is:
`ImageMatch.VARIANT` or `ImageMatch.FOOD` show this food, `ImageMatch.CATEGORY` the kind of food (cheese for a
gouda), and `ImageMatch.FALLBACK` a generic plate or drink when nothing fitted, which you may prefer to hide:

```python
if food.image is not None and not food.image.is_fallback:
    show_picture(food.image.url)
```

`client.images()` lists the whole set (each `ImageEntry`'s key, label, group, tier and URL, and the `ImageGroup`s),
for example to prefetch it; `image_set.image(key)` finds one. Values newer than the SDK parse as
`ImageMatch.UNKNOWN`, `ImageTier.UNKNOWN`, `FoodType.UNKNOWN` and `NutrientFlag.UNKNOWN`.

## Models as data

Every model is a frozen dataclass, fully type-hinted (the package ships `py.typed`). For JSON, for example to hand a
food to an AI agent's tool result:

```python
import dataclasses, json

json.dumps(dataclasses.asdict(food))
```

## Tests

```bash
python3 -m unittest                                   # unit tests against a local fake server
FOOD_API_KEY=... python3 -m unittest tests.test_live  # against the API
```
