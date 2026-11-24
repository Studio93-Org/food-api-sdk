# food-api (Kotlin)

Kotlin client for the [Studio93 Food API](https://api.studio93.io/food/docs) (v2), for Android apps and JVM servers:
typo-tolerant food search, autocomplete, barcode lookups and detailed nutrition. You need a v2 API key from Studio93;
a v1 key gets a 403 error.

## Install

Releases are built by [JitPack](https://jitpack.io/#Studio93-Org/food-api-sdk) from this repository's git tags
(`kotlin-v…`). Add the JitPack repository, in `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven("https://jitpack.io")
    }
}
```

and the dependency, in your module's `build.gradle.kts`:

```kotlin
dependencies {
    implementation("com.github.Studio93-Org:food-api-sdk:kotlin-v0.4.0")
}
```

JitPack builds a tag the first time someone asks for it, which takes a few minutes, so the first sync after a new
release can time out: sync again. To upgrade, change the version to a newer `kotlin-v…` tag.

### Without JitPack

Build it from a checkout of the tag and publish it to your machine's Maven repository:

```bash
git clone --branch kotlin-v0.4.0 https://github.com/Studio93-Org/food-api-sdk.git
cd food-api-sdk/kotlin && ./gradlew publishToMavenLocal
```

Then use `mavenLocal()` as a repository and `implementation("io.studio93:food-api:0.4.0")`. `./gradlew jar` builds
just the JAR (`build/libs/food-api-0.4.0.jar`); if you copy that into your project, add its dependencies yourself
(the three listed below).

## Requirements

| | |
|---|---|
| Kotlin | 2.3 or newer |
| Android | `minSdk` 24 or newer, with the `INTERNET` permission |
| JVM | Java 11 or newer |

It depends on [OkHttp](https://square.github.io/okhttp/) 5 (Android has no `java.net.http`; OkHttp pools connections
and speaks HTTP/2 and gzip on both), kotlinx-coroutines and kotlinx-serialization-json. The SDK is a plain JVM
library, so Android apps use the same artifact. It looks its serializers up without reflection, and
kotlinx-serialization ships its own R8 rules, so it needs no keep rules of its own.

## Create one client for the whole app

```kotlin
import io.studio93.foodapi.*

val foodApi = FoodApiClient(apiKey = apiKey, userAgent = "my-app/1.4.0")
```

Create it once (in your dependency injection or as a singleton) and share it. A shared client keeps connections open,
so only the first request pays for connecting; a client per request pays for it every time. It is safe to use from
any thread or coroutine. Load the API key from your app's configuration (for example Remote Config) and don't
commit it.

Every call is a `suspend` function. OkHttp does the network work on its own threads, so you can call them from
`Dispatchers.Main`. Cancelling the coroutine (for example when a `viewModelScope` ends) cancels the HTTP request and
any wait before a retry.

To share your app's `OkHttpClient` (its connections, interceptors and certificate pinning), pass it as
`httpClient =`; the SDK derives its own client from it with `newBuilder()`, and leaves it open when you call
`foodApi.close()`.

## Search

```kotlin
val page = foodApi.search("greek yogurt") // Typos are fine: "chiken brest" works
for (food in page.foods) {
    println("${food.name}: ${food.servings.first().nutrients.calories} kcal")
}
```

`search` takes `page` (zero-based, 0 to 1000) and `limit` (1 to 50, default 20). A query nothing matches returns an
empty page. With a key that has regional ranking, `page.region` is the country whose foods came first: the user's
(the API finds it from the device's address) or one set on the key. When the query names a brand ("coke"),
`page.brand` is that brand ("Coca-Cola"), whose foods ranked first.

| Call | Returns |
|---|---|
| `search(query, page = 0, limit = 20)` | a `SearchPage` of foods, with `region` and `brand` |
| `autocomplete(query, limit = 8)` | `AutocompleteResult`: suggestions for what has been typed so far (`limit` 1 to 20) |
| `food(id)` | one `Food` by its catalog ID |
| `foodByBarcode(scanned)` | the `Food` for a barcode, GS1 code or GS1 Digital Link |
| `nutrientStats(foodId)` | `NutrientStats`: how each of a food's nutrient values was obtained |
| `nutrients()` | `NutrientList`: every nutrient key, with its name and unit |
| `images()` | `ImageSet`: every food image, with its label, group and URL |
| `session()` | a `FoodSearchSession` for search as the user types |
| `withClientIP(ip)` | a client for calls made for one of your users (servers) |

### As the user types

Use one `FoodSearchSession` per search screen. A new search cancels the one still in flight, so a slow answer for
"app" can never replace the results for "apple". The replaced call throws `FoodApiCancelledException`, which is a
`CancellationException`: a coroutine that doesn't catch it just ends.

```kotlin
val session = foodApi.session()

fun onQueryChanged(text: String) {
    viewModelScope.launch {
        val page = session.search(text) // A newer search ends this coroutine here
        results.value = page.foods
    }
}

// Next page of the same query
val more = session.search(text, page = 1)

// When the screen closes (cancelling the scope does it too)
session.cancel()
```

Debounce the text field as usual (250 to 500 ms). For a type-ahead list, `session.autocomplete(text)` works the same
way and is fast enough for every keystroke; look a picked suggestion up with `foodApi.food(suggestion.id)`.

With a `Flow` of the text, `mapLatest` does the same job without a session:
`queries.debounce(300).mapLatest { foodApi.search(it) }` (both operators need an opt-in to preview coroutines APIs).

## Barcodes

Pass whatever the scanner read: a plain barcode, a GS1 code or a GS1 Digital Link.

```kotlin
try {
    showFood(foodApi.foodByBarcode(scanned))
} catch (e: FoodApiNotFound) {
    showNotFound() // No source knows this barcode
}
```

## Errors

Every failure is a `FoodApiException` (a sealed class), except cancellation. Use `when` to show the right message:

```kotlin
try {
    val page = foodApi.search(text)
} catch (e: FoodApiException) {
    when (e) {
        is FoodApiNotFound -> showNotFound()
        is FoodApiRateLimited, is FoodApiUnavailable -> showTryAgainSoon(e.retryAfter) // Already retried
        is FoodApiNetworkException, is FoodApiTimeoutException -> showOffline()
        is FoodApiUnauthorized, is FoodApiForbidden -> reportBadKey() // A missing, revoked or v1 key
        else -> showError(e.message)
    }
}
```

| Exception | When |
|---|---|
| `FoodApiBadRequest` | 400: a parameter is missing or invalid |
| `FoodApiUnauthorized` | 401: the API key is missing, invalid or revoked |
| `FoodApiForbidden` | 403: the key may not call this, for example a v1 key |
| `FoodApiNotFound` | 404: no such food or barcode; an answer, not a failure |
| `FoodApiRateLimited` | 429: slow down; `retryAfter` says how long |
| `FoodApiUnavailable` | 503: busy or briefly down; `retryAfter` says how long |
| `FoodApiServerError` | any other status, or an answer the SDK couldn't read |
| `FoodApiNetworkException` | the API couldn't be reached |
| `FoodApiTimeoutException` | an attempt took longer than the timeout |
| `FoodApiInvalidInput` | invalid arguments; nothing was sent |

HTTP errors are `FoodApiHttpException`s, with `statusCode`, the API's `message` and `retryAfter`. Temporary failures
(network errors, timeouts, and 429, 502, 503 and 504 responses) are retried twice before they reach you, waiting as
long as the API's `Retry-After` header asks (up to 10 seconds; a longer wait is thrown to you). Change this with
`FoodApiClient(maxRetries = …)`, and the time limit per attempt with `timeout =` (default 15 seconds).

## Calling for your users

When your server calls the API for its users, make each call through `withClientIP` with the user's IP address.
Search then ranks for the user's country instead of your server's (when your key has regional ranking), and
`page.region` says which country's foods came first:

```kotlin
val page = foodApi.withClientIP(userIp).search("cheddar cheese") // The user's address, e.g. from your load balancer
```

`withClientIP` returns a light client that shares the original's connections; create one per user request. The
address is sent as the `X-Client-IP` header. Rate limits still apply to your server's own address. An address that
isn't IPv4 or IPv6 throws `FoodApiInvalidInput` without a request. Apps that call the API from the user's device
don't need it.

## Nutrition

Every serving has its nutrients as numbers, null when unknown. The 17 core nutrients have properties; read any other
key by name. `foodApi.nutrients()` lists every key with its name and unit.

```kotlin
val n = food.servings.first().nutrients // The source's first serving
println("${n.calories} kcal, ${n.protein} g protein, ${n["magnesium"]} mg magnesium")
```

A food's servings start with its source's own and end with generic ones (`serving.generic`): 100 g and 1 oz for
solids, plus 1 cup or 1 tbsp and 1 tsp where the source measures the food that way; 100 ml, 1 fl oz, 1 cup, 1 tbsp
and 1 tsp for liquids. A food measured only by volume ("1/2 cup") gets the other volumes but no weights; one
measured by neither ("1 serving") gets none.

Some values aren't plain measurements. Show them the way the label meant them:

```kotlin
fun sugarText(food: Food, grams: Double): String = when (food.flag(Nutrients.SUGAR)) {
    NutrientFlag.UPPER_BOUND -> "< %.1f g".format(grams) // The label said "less than"
    NutrientFlag.APPROXIMATE -> "~%.1f g".format(grams)
    else -> "%.1f g".format(grams)
}
```

`food.alternateNames` has the other names a source gives the food, and `foodApi.nutrientStats(food.id)` the details
behind each value (samples, spread, how it was obtained) where the source gives them.

## Images

Every food comes with a picture, `food.image` (null in answers from before the API had images): a 256 px JPEG at a
public URL that needs no API key and never changes, so cache it for good. `match` says how close it is:
`ImageMatch.VARIANT` or `ImageMatch.FOOD` show this food, `ImageMatch.CATEGORY` the kind of food (cheese for a
gouda), and `ImageMatch.FALLBACK` a generic plate or drink when nothing fitted, which you may prefer to hide:

```kotlin
val image = food.image
if (image != null && !image.isFallback) {
    AsyncImage(model = image.url, contentDescription = food.name) // Coil, Glide or any image loader
}
```

`foodApi.images()` lists the whole set (each image's key, label, group, tier and URL), for example to prefetch it;
`set.image(key)` finds one. Values newer than the SDK parse as `ImageMatch.UNKNOWN` and `ImageTier.UNKNOWN`.

## Models

The models are Kotlin data classes marked `@Serializable` (kotlinx.serialization), so an app can store them, for
example a food the user logged, with `Json.encodeToString(Food.serializer(), food)`. Parsing is lenient: JSON keys
the SDK doesn't know are ignored and newer enum values parse as `UNKNOWN`, so newer API versions keep working with
older SDKs. `SDK_VERSION` is the SDK's version, sent in the `User-Agent` header with your app's `userAgent`.

## Testing your app

Point the client at a fake server with `baseUrl =`, for example OkHttp's `MockWebServer`:

```kotlin
val foodApi = FoodApiClient(apiKey = "test", baseUrl = server.url("/").toString(), maxRetries = 0)
```

The SDK's own tests:

```bash
./gradlew build                                       # compile and unit tests
FOOD_API_KEY=... ./gradlew test --tests '*LiveTest*'  # against the API
```
