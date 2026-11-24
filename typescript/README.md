# @studio93/food-api (TypeScript / JavaScript)

Client for the [Studio93 Food API](https://api.studio93.io/food/docs) (v2) for browsers, React Native and Node:
typo-tolerant food search, autocomplete, barcode lookups and detailed nutrition. You need a v2 API key from
Studio93; a v1 key gets a 403 error.

## Install

Releases are attached to the repository's GitHub releases as npm tarballs. Install one by its URL:

```bash
npm install https://github.com/Studio93-Org/food-api-sdk/releases/download/ts-v0.4.0/studio93-food-api-0.4.0.tgz
```

Yarn and pnpm take the same URL (`yarn add <url>`, `pnpm add <url>`). Your `package.json` then pins that release;
to upgrade, install the tarball of a newer `ts-v…` release. The package is called `@studio93/food-api` either way:

```ts
import { FoodApiClient } from '@studio93/food-api';
```

## Requirements

| | |
|---|---|
| Node | 18 or newer |
| Browsers | any current browser (it uses `fetch` and `AbortController`) |
| React Native | any version with the global `fetch` and `AbortController` (0.60 and newer) |
| TypeScript | types included; `moduleResolution` `bundler`, `node16` or `nodenext` |

It has no dependencies: requests go through the platform's own `fetch`. The package is an ES module; from CommonJS,
load it with `await import('@studio93/food-api')` (or `require()` on Node 20.19 / 22.12 and newer).

In a web page, the API answers your page's cross-origin requests (CORS), errors included. A key in a web page can be
read by anyone who opens it, so call from your server when you can.

## Create one client for the whole app

```ts
import { FoodApiClient } from '@studio93/food-api';

export const foodApi = new FoodApiClient({ apiKey, userAgent: 'my-app/1.4.0' });
```

Create it once (a module-level constant, your dependency injection or a React context) and share it. Requests go
through `fetch`, which keeps connections open (HTTP/2 where the server offers it) and accepts gzip, so only the
first request pays for connecting. Load the API key from your app's configuration and don't commit it.

| Option | Default | |
|---|---|---|
| `apiKey` | required | your v2 API key |
| `userAgent` | | your app's name and version, put before the SDK's in the User-Agent header (not in browsers, which don't allow it) |
| `timeout` | `15000` | milliseconds each attempt may take |
| `maxRetries` | `2` | how often a temporary failure is retried; `0` turns retries off |
| `baseUrl` | `https://api.studio93.io` | another server, such as a test server |
| `fetch` | the global `fetch` | your own `fetch`, for example a mock in tests |

## Calls

Every call returns a promise and takes an options object last, with `signal` (an `AbortSignal`) and, on servers,
`clientIp`.

| Call | Returns |
|---|---|
| `foodApi.search(query, { page, limit })` | a `SearchPage` of foods (`page` zero-based, 0 to 1000; `limit` 1 to 50, default 20) |
| `foodApi.autocomplete(query, { limit })` | an `AutocompleteResult`: suggestions for what has been typed so far (`limit` 1 to 20, default 8) |
| `foodApi.food(id)` | one `Food` by its catalog ID |
| `foodApi.foodByBarcode(scanned)` | the `Food` for a barcode, GS1 code or GS1 Digital Link |
| `foodApi.nutrientStats(id)` | `NutrientStats`: how each of a food's nutrient values was obtained |
| `foodApi.nutrients()` | a `NutrientList`: every nutrient key, with its name and unit |
| `foodApi.images()` | the `ImageSet`: every food image, with its label, group and URL |
| `foodApi.session()` | a `FoodSearchSession` for search as you type |

## Search

```ts
const page = await foodApi.search('greek yogurt'); // Typos are fine: 'chiken brest' works
for (const food of page.foods) {
  console.log(`${food.name}: ${food.servings[0]?.nutrients.calories} kcal`);
}
```

A query nothing matches returns an empty page. `page.query` is the query as searched (lowercase, single spaces),
`page.total` how many foods match, and `page.cached` whether the API answered from its cache. With a key that has
regional ranking, `page.region` is the country whose foods came first (the user's, or one set on the key), and
`page.brand` is the brand the query names ("Coca-Cola" for "coke"), whose foods came first; both are null otherwise.

### As the user types

Use one `FoodSearchSession` per search screen. A new search cancels the one still in flight, so a slow answer for
"app" can never replace the results for "apple":

```ts
import { FoodApiCancelledError } from '@studio93/food-api';

const session = foodApi.session();

async function onQueryChanged(text: string) {
  try {
    const page = await session.search(text);
    setResults(page.foods);
  } catch (e) {
    if (e instanceof FoodApiCancelledError) return; // The user typed on; a newer search is running
    throw e;
  }
}

// Next page of the same query
const more = await session.search(text, { page: 1 });

// When the screen closes (in React, the effect's cleanup)
session.cancel();
```

Debounce the text field as usual (250 to 500 ms). For a type-ahead list, `session.autocomplete(text)` works the same
way and is fast enough for every keystroke; look a picked suggestion up with `foodApi.food(suggestion.id)`.

### Cancelling any call

Every call takes an `AbortSignal`. Aborting it aborts the request (and any retry wait), and the call rejects with
`FoodApiCancelledError`. A signal that times out gives a call an overall deadline, retries included, and rejects
with `FoodApiTimeoutError`:

```ts
const controller = new AbortController();
const food = foodApi.food(id, { signal: controller.signal });
controller.abort(); // food rejects with FoodApiCancelledError

const page = await foodApi.search('cheddar', { signal: AbortSignal.timeout(5000) });
```

## Barcodes

Pass whatever the scanner read: a plain barcode, a GS1 code or a GS1 Digital Link.

```ts
try {
  showFood(await foodApi.foodByBarcode(scanned));
} catch (e) {
  if (e instanceof FoodApiNotFound) showNotFound(); // No source knows this barcode
  else throw e;
}
```

## Errors

Every failure is a `FoodApiError`, so one `instanceof FoodApiError` catches them all; the subclass says what
happened:

| Error | When |
|---|---|
| `FoodApiNotFound` | 404: no such food or barcode. An answer, not a failure: show "not found" |
| `FoodApiRateLimited` | 429: too many requests (already retried) |
| `FoodApiUnavailable` | 503: busy or briefly down (already retried) |
| `FoodApiUnauthorized` | 401: the API key is missing, invalid or revoked |
| `FoodApiForbidden` | 403: the key may not call this, for example a v1 key |
| `FoodApiBadRequest` | 400: a parameter is invalid |
| `FoodApiServerError` | any other status, or an answer that isn't valid JSON |
| `FoodApiNetworkError` | the API couldn't be reached: offline, DNS failure, connection reset |
| `FoodApiTimeoutError` | an attempt took longer than `timeout`, or the call's signal timed out |
| `FoodApiCancelledError` | the call's signal was aborted, for example by a newer search in a session |
| `FoodApiInvalidInput` | the arguments were invalid; nothing was sent |

The HTTP ones extend `FoodApiHttpError`, with `statusCode` and `retryAfter` (milliseconds, or null). `message` is the
API's explanation.

```ts
function errorText(e: unknown): string | null {
  if (e instanceof FoodApiCancelledError) return null; // Superseded by a newer search
  if (e instanceof FoodApiNotFound) return 'Not found';
  if (e instanceof FoodApiRateLimited || e instanceof FoodApiUnavailable) return 'Try again in a moment';
  if (e instanceof FoodApiNetworkError || e instanceof FoodApiTimeoutError) return "You're offline";
  if (e instanceof FoodApiError) return e.message;
  throw e;
}
```

Temporary failures (network errors, timeouts, and 429, 502, 503 and 504 responses) are retried twice before they
reach you, waiting as long as the API's `Retry-After` header asks (up to 10 seconds; a longer wait is thrown to you
with `retryAfter` set) or backing off 0.5 s, then 1 s. Change this with the `maxRetries` and `timeout` options.

## Calling for your users (servers only)

When your server calls the API for its users, pass each user's IP address with `clientIp`. Search then ranks for
the user's country instead of your server's (when your key has regional ranking), and `page.region` says which
country's foods came first:

```ts
const page = await foodApi.search('cheddar cheese', { clientIp: userIp }); // e.g. from your load balancer
```

It is sent as the `X-Client-IP` header on that call; rate limits still apply to your server's own address. An
address that isn't IPv4 or IPv6 throws `FoodApiInvalidInput` without a request. Apps calling the API from the
user's device (browsers, React Native) leave it out: the API already sees the user's address.

## Nutrition

Every serving has its nutrients as numbers, null when unknown. The 17 core nutrients have getters; read any other key
with `get`. `foodApi.nutrients()` lists every key with its name and unit.

```ts
const n = food.servings[0]!.nutrients; // The source's first serving
console.log(`${n.calories} kcal, ${n.protein} g protein, ${n.get('magnesium')} mg magnesium`);
```

A food's servings start with its source's own and end with generic ones (`serving.generic`): 100 g and 1 oz for
solids, plus 1 cup or 1 tbsp and 1 tsp where the source measures the food that way; 100 ml, 1 fl oz, 1 cup, 1 tbsp
and 1 tsp for liquids. A food measured only by volume ("1/2 cup") gets the other volumes but no weights; one
measured by neither ("1 serving") gets none.

Some values aren't plain measurements. Show them the way the label meant them:

```ts
function sugarText(food: Food, grams: number): string {
  switch (food.flag('sugar')) {
    case NutrientFlag.upperBound:
      return `< ${grams.toFixed(1)} g`; // The label said "less than"
    case NutrientFlag.approximate:
      return `~${grams.toFixed(1)} g`;
    default:
      return `${grams.toFixed(1)} g`;
  }
}
```

The flags are `NutrientFlag.upperBound` (`'upper_bound'`), `approximate` and `assumedZero` (`'assumed_zero'`).
`food.alternateNames` has the other names a source gives the food, and `foodApi.nutrientStats(food.id)` the details
behind each value (samples, spread, how it was obtained) where the source gives them.

To store a food (a diary, an offline cache), `JSON.stringify(food)` writes it in the API's form and
`Food.fromJson(JSON.parse(text))` reads it back.

## Images

Every food comes with a picture, `food.image` (null in answers from before the API had images): a 256 px JPEG at a
public URL that needs no API key and never changes, so cache it for good. `match` says how close it is:
`ImageMatch.variant` or `ImageMatch.food` show this food, `ImageMatch.category` the kind of food (cheese for a
gouda), and `ImageMatch.fallback` a generic plate or drink when nothing fitted, which you may prefer to hide:

```ts
function pictureUrl(food: Food): string | null {
  const image = food.image;
  if (image === null || image.isFallback) return null;
  return image.url;
}
```

`foodApi.images()` lists the whole set (each image's key, label, group, tier and URL), for example to prefetch it;
`set.image(key)` finds one. Values newer than the SDK parse as `ImageMatch.unknown` (treat it like `category`) and
`ImageTier.unknown`.

## Testing your app

Pass your own `fetch` to the client, for example one that answers from fixtures:

```ts
const foodApi = new FoodApiClient({
  apiKey: 'test',
  maxRetries: 0,
  fetch: async (url) => new Response(JSON.stringify({ data: fixtureFood })),
});
```

Models can be built directly too: `new Food({ ... })`, or `Food.fromJson(apiJson)`.

## Developing the SDK

The built package (`dist/`) is committed, so release tarballs need no build step. After changing `src/`, rebuild
and commit `dist/` with it.

```bash
npm install                                    # TypeScript, Prettier and Node's types, for development only
npm test                                       # builds dist/, type-checks, runs the unit tests
npm run lint                                   # Prettier and the type checks
FOOD_API_KEY=... node --test test/live.test.ts # against the API
npm pack                                       # studio93-food-api-<version>.tgz, for the GitHub release
```

[example/example.ts](example/example.ts) has these snippets as code that type-checks.
