# Studio93FoodAPI (Swift)

Swift client for the [Studio93 Food API](https://api.studio93.io/food/docs) (v2) on iOS and macOS: typo-tolerant food
search, autocomplete, barcode lookups and detailed nutrition. You need a v2 API key from Studio93; a v1 key gets a
403 error.

## Install

The package is installed from this repository by tag (Swift Package Manager reads the `Package.swift` at the
repository root, which builds the sources in `swift/`). Swift releases are tagged with plain versions: `0.4.0`.

In Xcode: **File > Add Package Dependencies…**, enter `https://github.com/Studio93-Org/food-api-sdk.git`, choose
**Up to Next Major Version** from `0.4.0` (or **Exact Version** `0.4.0`), and add the `Studio93FoodAPI` library to
your app target.

In a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Studio93-Org/food-api-sdk.git", from: "0.4.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "Studio93FoodAPI", package: "food-api-sdk"),
    ]),
]
```

Before 1.0, `from: "0.4.0"` accepts any `0.x` release; use `.upToNextMinor(from: "0.4.0")` or `exact: "0.4.0"` to
stay on 0.4. To upgrade, raise the version.

## Requirements

| | |
|---|---|
| Swift | 6.0 or newer (Xcode 16+), Swift 5 and 6 language modes |
| iOS | 15 or newer |
| macOS | 12 or newer, with the outgoing-connections entitlement (`com.apple.security.network.client`) in a sandboxed app |
| Dependencies | none: Foundation's `URLSession` |

## Create one client for the whole app

```swift
import Studio93FoodAPI

let foodAPI = FoodAPIClient(apiKey: apiKey, userAgent: "my-app/1.4.0")
```

Create it once (in your app's environment, dependency container or a `static let`) and share it. It keeps
connections open in its `URLSession` (HTTP/2 and HTTP/3, gzip), so only the first request pays for connecting; a
client per request pays for it every time. It is `Sendable`, so any task or actor can use it. Load the API key from
your app's configuration (for example Remote Config) and don't commit it.

| Call | Returns |
|---|---|
| `try await foodAPI.search(query, page: 0, limit: 20)` | a `SearchPage` of foods (`page` is zero-based, `limit` 1 to 50); `region` is the country ranked first, if any |
| `try await foodAPI.autocomplete(query, limit: 8)` | an `AutocompleteResult`: suggestions for what has been typed so far (`limit` 1 to 20) |
| `try await foodAPI.food(id)` | one `Food` by its catalog ID |
| `try await foodAPI.foodByBarcode(scanned)` | the `Food` for a barcode, GS1 code or GS1 Digital Link |
| `try await foodAPI.nutrientStats(id)` | `NutrientStats`: how each of a food's nutrient values was obtained |
| `try await foodAPI.nutrients()` | a `NutrientList`: every nutrient key, with its name and unit |
| `try await foodAPI.images()` | the `ImageSet`: every food image, with its label, group and URL |
| `foodAPI.session()` | a `FoodSearchSession` for search as the user types |
| `foodAPI.withClientIP(ip)` | a client for calls a server makes for one of its users |

The models are `Codable`, `Sendable` and `Hashable` structs, and `Food` and `Suggestion` are `Identifiable`, so they
work directly in SwiftUI lists and can be saved as JSON. `FoodAPIClient.sdkVersion` is the SDK's version.

## Search

```swift
let page = try await foodAPI.search("greek yogurt") // Typos are fine: "chiken brest" works
for food in page.foods {
    print(food.name, food.servings.first?.nutrients.calories ?? 0)
}
```

A query nothing matches returns an empty page. With a key that has regional ranking, `page.region` is the country
whose foods came first: the user's (the API finds it from the device's address) or one set on the key.

### As the user types

Cancel a call by cancelling its task: the request stops, and so does any wait before a retry, with
`FoodAPIError.cancelled`. SwiftUI's `.task(id:)` does this for you when the text changes:

```swift
.task(id: text) {
    try? await Task.sleep(nanoseconds: 300_000_000) // Debounce
    guard !Task.isCancelled, !text.isEmpty else { return }
    do {
        results = try await foodAPI.search(text).foods
    } catch FoodAPIError.cancelled {
        // The user typed on; a newer search is running
    } catch {
        showError(error)
    }
}
```

Elsewhere, use one `FoodSearchSession` per search screen. A new search cancels the one still in flight, so a slow
answer for "app" can never replace the results for "apple":

```swift
let session = foodAPI.session()

func queryChanged(_ text: String) async {
    do {
        results = try await session.search(text).foods
    } catch FoodAPIError.cancelled {
        // Superseded by a newer search
    } catch {
        showError(error)
    }
}

// Next page of the same query
let more = try await session.search(text, page: 1)

// When the screen closes
session.cancel()
```

Debounce the text field as usual (250 to 500 ms). For a type-ahead list, `session.autocomplete(text)` works the same
way (it cancels only the previous autocomplete) and is fast enough for every keystroke; look a picked suggestion up
with `foodAPI.food(suggestion.id)`.

## Barcodes

Pass whatever the scanner read: a plain barcode, a GS1 code or a GS1 Digital Link.

```swift
do {
    let food = try await foodAPI.foodByBarcode(scanned)
    showFood(food)
} catch FoodAPIError.notFound {
    showNotFound() // No source knows this barcode: an answer, not a failure
}
```

## Errors

Every call throws only `FoodAPIError`. Switch on it to show the right message:

```swift
do {
    let page = try await foodAPI.search(text)
} catch let error as FoodAPIError {
    switch error {
    case .notFound:
        showNotFound()
    case .rateLimited, .unavailable:
        showTryAgainSoon() // Already retried; error.retryAfter says when to try again
    case .network, .timeout:
        showOffline() // error.isOffline is true for both
    case .cancelled:
        break // Superseded by a newer search
    case .unauthorized, .forbidden:
        reportBadKey(error.message) // A missing, revoked or v1 key
    default:
        showError(error.message)
    }
}
```

| Case | When |
|---|---|
| `.badRequest(message:)` | 400: a parameter is missing or invalid |
| `.unauthorized(message:)` | 401: the API key is missing, invalid or revoked |
| `.forbidden(message:)` | 403: the key can't use this call, for example a v1 key |
| `.notFound(message:)` | 404: no such food or barcode |
| `.rateLimited(message:retryAfter:)` | 429: slow down |
| `.unavailable(message:retryAfter:)` | 503: busy or down for a moment |
| `.server(statusCode:message:retryAfter:)` | any other error status, or an answer the SDK couldn't read |
| `.network(URLError)` | the API couldn't be reached (no connection, DNS, connection reset) |
| `.timeout` | an attempt took longer than the client's `timeout` |
| `.cancelled` | the task was cancelled, or a newer search in the same session replaced it |
| `.invalidInput(String)` | invalid arguments; nothing was sent |

`error.message` is the API's explanation, `error.statusCode` the HTTP status (nil when there was none), and
`error.retryAfter` the wait the API asked for.

Temporary failures (network errors, timeouts, and 429, 502, 503 and 504 responses) are retried twice before they
reach you, waiting as long as the API's `Retry-After` header asks (up to 10 seconds; a longer wait is thrown to you).
Change this with `FoodAPIClient(apiKey:maxRetries:)`, and the time limit per attempt with `timeout:` (default 15
seconds).

## Calling for your users (servers)

When your server calls the API for its users, pass each user's IP address. Search then ranks for the user's country
instead of your server's (when your key has regional ranking), and `page.region` says which country's foods came
first:

```swift
let foodAPI = FoodAPIClient(apiKey: apiKey, userAgent: "my-service/1.0") // One for the whole server

// Per incoming request: the user's address, e.g. from your load balancer
let page = try await foodAPI.withClientIP(userIP).search("cheddar cheese")
```

`withClientIP` returns a client that shares the original's connections and sends the address as the `X-Client-IP`
header on every call. Rate limits still apply to your server's own address. An address that isn't IPv4 or IPv6
throws `FoodAPIError.invalidInput` without a request. Apps that call the API from the user's own device don't need
it.

## Nutrition

Every serving has its nutrients as numbers, nil when unknown. The 17 core nutrients have properties (and keys in
`NutrientKey`); read any other key by name. `foodAPI.nutrients()` lists every key with its name and unit.

```swift
let n = food.servings[0].nutrients // The source's first serving
print(n.calories ?? 0, "kcal,", n.protein ?? 0, "g protein,", n["magnesium"] ?? 0, "mg magnesium")
```

A food's servings start with its source's own and end with generic ones (`serving.generic`): 100 g and 1 oz for
solids, plus 1 cup or 1 tbsp and 1 tsp where the source measures the food that way; 100 ml, 1 fl oz, 1 cup, 1 tbsp
and 1 tsp for liquids. A food measured only by volume ("1/2 cup") gets the other volumes but no weights; one
measured by neither ("1 serving") gets none.

Some values aren't plain measurements. Show them the way the label meant them:

```swift
func sugarText(_ food: Food, grams: Double) -> String {
    let amount = String(format: "%.1f g", grams)
    switch food.flag(NutrientKey.sugar) {
    case .upperBound: return "< " + amount // The label said "less than"
    case .approximate: return "~" + amount
    default: return amount
    }
}
```

Flags are `.upperBound`, `.approximate` and `.assumedZero`. `food.alternateNames` has the other names a source gives
the food, and `foodAPI.nutrientStats(food.id)` the details behind each value (samples, spread, how it was obtained)
where the source gives them.

## Images

Every food comes with a picture, `food.image` (nil in answers from before the API had images): a 256 px JPEG at a
public URL that needs no API key and never changes, so cache it for good. `match` says how close it is: `.variant` or
`.food` show this food, `.category` the kind of food (cheese for a gouda), and `.fallback` a generic plate or drink
when nothing fitted, which you may prefer to hide:

```swift
if let image = food.image, !image.isFallback {
    AsyncImage(url: image.url) { $0.resizable() } placeholder: { Color.secondary.opacity(0.1) }
        .frame(width: 64, height: 64)
}
```

`foodAPI.images()` lists the whole set (each `ImageEntry`'s key, label, group, tier and URL, and the `ImageGroup`s),
for example to prefetch it; `set.image(key)` finds one. Values newer than the SDK parse as `.unknown(value)`: treat
an unknown match like `.category`.

## Testing your app

Pass your own `URLSession` as `urlSession:`, for example one whose configuration has a `URLProtocol` subclass in
`protocolClasses` that answers with fixtures; the client then leaves it open. The models have public initializers
for previews and fakes. The SDK's own tests run from the repository root (where the manifest is):

```bash
swift test --scratch-path swift/.build                                    # unit tests
FOOD_API_KEY=... swift test --scratch-path swift/.build --filter LiveTests # against the API
swift format lint --configuration swift/.swift-format -r swift/Sources swift/Tests Package.swift
```
