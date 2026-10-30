# Studio93 Food API SDKs

Client libraries for the [Studio93 Food API](https://api.studio93.io/food/docs) (v2): typo-tolerant food search,
autocomplete, barcode lookups (plain barcodes, GS1 codes and GS1 Digital Links) and detailed nutrition for every
serving.

| SDK | Folder | Requirements | Guide |
|---|---|---|---|
| Flutter / Dart | [`dart/`](dart) | Flutter 3.38+, iOS 15+, macOS 12+, Android `minSdk` 24, web | [dart/README.md](dart/README.md) |
| Go | [`go/`](go) | Go 1.23+, no dependencies | [go/README.md](go/README.md) |

You need a v2 API key issued by Studio93 (keys are issued per API version, and a v1 key gets a 403 error). The
SDKs don't include one: load yours from your app's configuration and
don't commit it.

## Install

Flutter, in `pubspec.yaml`:

```yaml
dependencies:
  studio93_food_api:
    git:
      url: https://github.com/Studio93-Org/food-api-sdk.git
      path: dart
      ref: dart-v0.2.0
```

Go:

```bash
go get github.com/Studio93-Org/food-api-sdk/go@v0.2.0
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
- **Nutrition as numbers.** Nutrients are numbers, null when unknown, with flags for values that aren't plain
  measurements: `upper_bound` (the label said "less than"), `approximate` and `assumed_zero`.

## Versions

Both SDKs follow the API's v2 and are released together as git tags: `dart-v0.2.0` for Flutter (the git
dependency's `ref`) and `go/v0.2.0` for Go (installed as `@v0.2.0`). Changes are listed in
[dart/CHANGELOG.md](dart/CHANGELOG.md).

## License

MIT, see [LICENSE](LICENSE). Using the API itself needs a v2 API key from Studio93.
