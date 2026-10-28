// Package foodapi is the Go client for the Studio93 Food API (v2): food search with typo tolerance, autocomplete,
// barcode lookups and detailed nutrition for each serving.
//
// Create one Client and share it; it keeps connections open between requests and retries what is safe to retry:
//
//	client := foodapi.New(os.Getenv("FOOD_API_KEY"), foodapi.WithUserAgent("my-app/1.0"))
//
//	page, err := client.Search(ctx, "greek yogurt", nil)
//	if err != nil {
//		return err
//	}
//	for _, food := range page.Foods {
//		kcal, _ := food.Servings[0].Nutrients.Get(foodapi.Calories)
//		fmt.Println(food.Name, kcal)
//	}
//
//	food, err := client.FoodByBarcode(ctx, "3017624010701")
//	if errors.Is(err, foodapi.ErrNotFound) {
//		// No source knows this barcode: an answer, not a failure
//	}
//
// Errors from the API are *APIError values, which match ErrNotFound, ErrRateLimited, ErrUnavailable and the other
// sentinels with errors.Is. Cancel a call with its context, for example to drop a search the user has typed past.
//
// The API reference is at https://api.studio93.io/food/docs.
package foodapi
