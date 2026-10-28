# Studio93 Food API SDKs

Client libraries for the [Studio93 Food API](https://api.studio93.io/food/docs) (v2): typo-tolerant food search,
autocomplete, barcode lookups (plain barcodes, GS1 codes and GS1 Digital Links) and detailed nutrition for every
serving.

| SDK | Folder | Install |
|---|---|---|
| Flutter / Dart | [`dart/`](dart) | git dependency, see [dart/README.md](dart/README.md) |
| Go | [`go/`](go) | `go get github.com/Studio93-Org/food-api-sdk/go` |

You need an API key issued by Studio93. The SDKs don't include one: pass yours in from your app's configuration,
and don't commit it.

## What the SDKs take care of

- **Fast connections.** One client per app keeps connections open between requests, so only the first request pays
  for the TCP and TLS handshake (one or two network round trips, often 100 ms or more on mobile). The Flutter SDK
  uses the platform's own HTTP stack (URLSession on iOS, Cronet on Android), with HTTP/2 and HTTP/3.
- **Search as you type.** Newer searches cancel older ones still in flight, so a slow answer never replaces a newer
  one.
- **Safe retries.** Network errors, timeouts and 429, 502, 503 and 504 responses are retried a couple of times,
  waiting as long as the API's `Retry-After` header asks.
- **Typed errors.** "Not found" is an answer, not a failure; it's a different error from "rate limited" or
  "unavailable", so apps can show the right message.
- **Nutrition as numbers.** Nutrients are numbers, null when unknown, and flags mark values that aren't plain
  measurements: `upper_bound` (the label said "less than"), `approximate` and `assumed_zero`.

## Quick start

Flutter:

```dart
final client = FoodApiClient(apiKey: apiKey); // one for the whole app

final page = await client.search('greek yogurt');
for (final food in page.foods) {
  print('${food.name}: ${food.servings.first.nutrients.calories} kcal');
}
```

Go:

```go
client := foodapi.New(apiKey) // one for the whole app

page, err := client.Search(ctx, "greek yogurt", nil)
if err != nil {
	return err
}
for _, food := range page.Foods {
	kcal, _ := food.Servings[0].Nutrients.Get(foodapi.Calories)
	fmt.Println(food.Name, kcal)
}
```

## Versions

Both SDKs follow the API's v2 and are versioned together. Releases are git tags: `dart-v0.1.0` for Flutter (use
it as the git dependency's `ref`) and `go/v0.1.0` for Go, which you install as
`go get github.com/Studio93-Org/food-api-sdk/go@v0.1.0`.

## License

MIT, see [LICENSE](LICENSE). Using the API itself needs an API key from Studio93.
