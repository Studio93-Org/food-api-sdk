# foodapi (Go)

Go client for the [Studio93 Food API](https://api.studio93.io/food/docs) (v2).

```bash
go get github.com/Studio93-Org/food-api-sdk/go
```

```go
import foodapi "github.com/Studio93-Org/food-api-sdk/go"

// Create one client and share it: it keeps connections open and is safe for concurrent use
client := foodapi.New(apiKey, foodapi.WithUserAgent("my-service/1.0"))

page, err := client.Search(ctx, "chiken brest", &foodapi.SearchOptions{Limit: 10})
food, err := client.Food(ctx, page.Foods[0].ID)
food, err = client.FoodByBarcode(ctx, "https://id.gs1.org/01/03017624010701")
suggestions, err := client.Autocomplete(ctx, "chick", 8)
stats, err := client.NutrientStats(ctx, food.ID)
list, err := client.Nutrients(ctx)
```

## Errors

API errors are `*foodapi.APIError` values that match sentinels with `errors.Is`:

```go
food, err := client.FoodByBarcode(ctx, scanned)
switch {
case errors.Is(err, foodapi.ErrNotFound):
	// No source knows this barcode: an answer, not a failure
case errors.Is(err, foodapi.ErrRateLimited), errors.Is(err, foodapi.ErrUnavailable):
	// Already retried; try again later (APIError.RetryAfter says when)
case err != nil:
	return err
}
```

Network errors and 429, 502, 503 and 504 responses are retried twice, waiting as long as the API's `Retry-After`
asks (up to 10 seconds; a longer wait is returned to you). Change it with `WithMaxRetries`, and the per-attempt
limit with `WithTimeout`. Cancel a call, or give it a deadline, with its context.

## Nutrition

```go
n := food.Servings[0].Nutrients
if kcal, ok := n.Get(foodapi.Calories); ok {
	fmt.Printf("%.0f kcal\n", kcal)
}
if food.Flag(foodapi.Sugar) == foodapi.FlagUpperBound {
	// The label said "less than": show "< x g"
}
```

## Tests

```bash
go test ./...                              # unit tests
FOOD_API_KEY=... go test -run TestLive ./... # against the API
```
