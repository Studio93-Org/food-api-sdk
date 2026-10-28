# foodapi (Go)

Go client for the [Studio93 Food API](https://api.studio93.io/food/docs) (v2): typo-tolerant food search,
autocomplete, barcode lookups and detailed nutrition. You need an API key from Studio93.

## Install

```bash
go get github.com/Studio93-Org/food-api-sdk/go@v0.1.0
```

It needs Go 1.23 or newer and has no dependencies beyond the standard library. The module lives in the `go/` folder,
so its releases are tagged `go/v…`, but you install them by version (`@v0.1.0`, or `@latest`).

## Use

```go
import foodapi "github.com/Studio93-Org/food-api-sdk/go"

// Create one client and share it: it keeps connections open (HTTP/2) and is safe for concurrent use
client := foodapi.New(os.Getenv("FOOD_API_KEY"), foodapi.WithUserAgent("my-service/1.0"))

page, err := client.Search(ctx, "greek yogurt", nil) // Typos are fine: "chiken brest" works
if err != nil {
	return err
}
for _, food := range page.Foods {
	kcal, _ := food.Servings[0].Nutrients.Get(foodapi.Calories)
	fmt.Println(food.Name, kcal)
}
```

| Call | Returns |
|---|---|
| `Search(ctx, query, &SearchOptions{Page, Limit})` | a page of foods (`Page` is zero-based, `Limit` 1 to 50, default 20) |
| `Autocomplete(ctx, query, limit)` | suggestions for what has been typed so far (`limit` 1 to 20, default 8) |
| `Food(ctx, id)` | one food by its catalog ID |
| `FoodByBarcode(ctx, scanned)` | the food for a barcode, GS1 code or GS1 Digital Link |
| `NutrientStats(ctx, id)` | how each of a food's nutrient values was obtained |
| `Nutrients(ctx)` | every nutrient key, with its name and unit |

Cancel a call, or give it a deadline, with its context. For search as the user types, cancel the previous call's
context when a new one starts.

## Errors

API errors are `*foodapi.APIError` values that match sentinels with `errors.Is`:

```go
food, err := client.FoodByBarcode(ctx, scanned)
switch {
case errors.Is(err, foodapi.ErrNotFound):
	// No source knows this barcode: an answer, not a failure
case errors.Is(err, foodapi.ErrRateLimited), errors.Is(err, foodapi.ErrUnavailable):
	// Already retried; APIError.RetryAfter says when to try again
case err != nil:
	return err
}
```

Network errors and 429, 502, 503 and 504 responses are retried twice, waiting as long as the API's `Retry-After`
asks (up to 10 seconds; a longer wait is returned to you). Change this with `WithMaxRetries`, and the time limit per
attempt with `WithTimeout` (default 15 seconds). Invalid arguments return `ErrInvalidInput` without a request.

## Nutrition

Each serving's nutrients are a map of numbers, nil when unknown. The core nutrients have constants
(`foodapi.Calories`, `foodapi.Protein`, …); `Nutrients(ctx)` lists every key.

```go
n := food.Servings[0].Nutrients
if kcal, ok := n.Get(foodapi.Calories); ok {
	fmt.Printf("%.0f kcal\n", kcal)
}
if food.Flag(foodapi.Sugar) == foodapi.FlagUpperBound {
	// The label said "less than": show "< x g"
}
```

Flags mark values that aren't plain measurements: `FlagUpperBound`, `FlagApproximate` and `FlagAssumedZero`.
`food.AlternateNames()` has the other names a source gives the food.

## Tests

[example_test.go](example_test.go) has these snippets as examples that compile.

```bash
go test ./...                                 # unit tests
FOOD_API_KEY=... go test -run TestLive ./...  # against the API
```
