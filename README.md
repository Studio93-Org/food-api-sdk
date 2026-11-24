# Studio93 Food API SDKs

Client libraries for the [Studio93 Food API](https://api.studio93.io/food/docs) (v2): typo-tolerant food search,
autocomplete, barcode lookups (plain barcodes, GS1 codes and GS1 Digital Links) and detailed nutrition for every
serving.

| SDK | Folder | Requirements | Guide |
|---|---|---|---|
| Flutter / Dart | [`dart/`](dart) | Flutter 3.38+, iOS 15+, macOS 12+, Android `minSdk` 24, web | [dart/README.md](dart/README.md) |
| Go | [`go/`](go) | Go 1.23+, no dependencies | [go/README.md](go/README.md) |
| Swift (iOS, macOS) | [`swift/`](swift) | Swift 6, iOS 15+, macOS 12+, no dependencies | [swift/README.md](swift/README.md) |
| Kotlin (Android, JVM) | [`kotlin/`](kotlin) | Android `minSdk` 24 or JVM 11+, Kotlin 2.3+; OkHttp, kotlinx | [kotlin/README.md](kotlin/README.md) |
| TypeScript / JavaScript | [`typescript/`](typescript) | Browsers, React Native, Node 18+; no dependencies | [typescript/README.md](typescript/README.md) |
| Python | [`python/`](python) | Python 3.9+, no dependencies | [python/README.md](python/README.md) |

You need a v2 API key issued by Studio93 (keys are issued per API version, and a v1 key gets a 403 error). The
SDKs don't include one: load yours from your app's configuration and don't commit it.

## Install

Flutter, in `pubspec.yaml`:

```yaml
dependencies:
  studio93_food_api:
    git:
      url: https://github.com/Studio93-Org/food-api-sdk.git
      path: dart
      ref: dart-v0.4.0
```

Go:

```bash
go get github.com/Studio93-Org/food-api-sdk/go@v0.4.0
```

Swift: in Xcode, File > Add Package Dependencies with `https://github.com/Studio93-Org/food-api-sdk.git`, Up to
Next Major from `0.4.0`, and the `Studio93FoodAPI` library; or in `Package.swift`:

```swift
.package(url: "https://github.com/Studio93-Org/food-api-sdk.git", from: "0.4.0")
```

Kotlin, from JitPack (`maven("https://jitpack.io")` in your repositories):

```kotlin
implementation("com.github.Studio93-Org:food-api-sdk:kotlin-v0.4.0")
```

TypeScript / JavaScript, from the release tarball:

```bash
npm install https://github.com/Studio93-Org/food-api-sdk/releases/download/ts-v0.4.0/studio93-food-api-0.4.0.tgz
```

Python:

```bash
pip install "studio93-food-api @ git+https://github.com/Studio93-Org/food-api-sdk.git@py-v0.4.0#subdirectory=python"
```

## Quick start

Flutter:

```dart
import 'package:studio93_food_api/studio93_food_api.dart';

final foodApi = FoodApiClient(apiKey: apiKey); // One for the whole app

final page = await foodApi.search('greek yogurt');
for (final food in page.foods) {
  print('${food.name}: ${food.servings.first.nutrients.calories} kcal');
}
```

Go:

```go
import foodapi "github.com/Studio93-Org/food-api-sdk/go"

client := foodapi.New(apiKey) // One for the whole app

page, err := client.Search(ctx, "greek yogurt", nil)
if err != nil {
	return err
}
for _, food := range page.Foods {
	kcal, _ := food.Servings[0].Nutrients.Get(foodapi.Calories)
	fmt.Println(food.Name, kcal)
}
```

Swift:

```swift
import Studio93FoodAPI

let foodAPI = FoodAPIClient(apiKey: apiKey) // One for the whole app

let page = try await foodAPI.search("greek yogurt")
for food in page.foods {
    print(food.name, food.servings.first?.nutrients.calories ?? 0)
}
```

Kotlin:

```kotlin
import io.studio93.foodapi.*

val foodApi = FoodApiClient(apiKey = apiKey) // One for the whole app

val page = foodApi.search("greek yogurt") // In a coroutine
page.foods.forEach { println("${it.name}: ${it.servings.first().nutrients.calories} kcal") }
```

TypeScript:

```ts
import { FoodApiClient } from '@studio93/food-api';

const foodApi = new FoodApiClient({ apiKey }); // One for the whole app

const page = await foodApi.search('greek yogurt');
for (const food of page.foods) console.log(food.name, food.servings[0]?.nutrients.calories);
```

Python:

```python
from studio93_food_api import FoodApiClient

client = FoodApiClient(api_key)  # One for the whole service

page = client.search("greek yogurt")
for food in page.foods:
    print(food.name, food.servings[0].nutrients.calories)
```

## What the SDKs take care of

- **Fast connections.** One shared client keeps connections open between requests, so only the first request pays
  for the TCP and TLS handshake (one or two network round trips, often 100 ms or more on mobile). The Flutter SDK
  uses the platform's own HTTP stack (`URLSession` on iOS and macOS, Cronet on Android), with HTTP/2 and HTTP/3.
- **Search as you type.** A newer search cancels the one still in flight, so a slow answer never replaces a newer
  one (Flutter: `FoodSearchSession`; Go: cancel the context).
- **Safe retries.** Network errors, timeouts and 429, 502, 503 and 504 responses are retried twice, waiting as long
  as the API's `Retry-After` header asks.
- **Typed errors.** "Not found" is an answer, not a failure, and a different error from "rate limited",
  "unavailable" or "offline", so apps can show the right message.
- **Regional ranking.** With a key that has it, search puts one country's foods first among equally good matches:
  the user's country, or one set on the key. Apps calling from the user's device get it automatically; a Go server
  calling for its users passes each user's address with `WithClientIP`. The page's region says which country ranked
  first. A Go, Kotlin, TypeScript (Node) or Python server passes each user's address the same way (`withClientIP`,
  `clientIp`, `client_ip`).
- **Food images.** Every food comes with a picture (a 256 px JPEG at a public URL that never changes, so it can be
  cached for good) and how closely it shows the food: this food, its kind (cheese for a gouda), or a generic
  fallback apps may hide. The whole image set can be listed to bundle or prefetch it.
- **Nutrition as numbers.** Nutrients are numbers, null when unknown, with flags for values that aren't plain
  measurements: `upper_bound` (the label said "less than"), `approximate` and `assumed_zero`.

## Versions

The SDKs follow the API's v2 and are released together as git tags, one per SDK: `dart-v0.4.0` for Flutter (the
git dependency's `ref`), `go/v0.4.0` for Go (installed as `@v0.4.0`), `0.4.0` for Swift (Swift Package Manager
reads plain version tags), `kotlin-v0.4.0` for Kotlin (JitPack), `ts-v0.4.0` for TypeScript (a GitHub release
with the npm tarball) and `py-v0.4.0` for Python. Each SDK lists its changes in its own `CHANGELOG.md`.

## License

MIT, see [LICENSE](LICENSE). Using the API itself needs a v2 API key from Studio93.
