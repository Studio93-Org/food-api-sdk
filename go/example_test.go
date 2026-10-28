package foodapi_test

import (
	"context"
	"errors"
	"fmt"
	"os"

	foodapi "github.com/Studio93-Org/food-api-sdk/go"
)

// These examples are the ones in README.md; go vet compiles them, so the README stays correct.

func Example() {
	ctx := context.Background()
	// Create one client and share it: it keeps connections open and is safe for concurrent use
	client := foodapi.New(os.Getenv("FOOD_API_KEY"), foodapi.WithUserAgent("my-service/1.0"))

	page, err := client.Search(ctx, "greek yogurt", nil)
	if err != nil {
		fmt.Println(err)
		return
	}
	for _, food := range page.Foods {
		kcal, _ := food.Servings[0].Nutrients.Get(foodapi.Calories)
		fmt.Println(food.Name, kcal)
	}
}

func ExampleClient_FoodByBarcode() {
	ctx := context.Background()
	client := foodapi.New(os.Getenv("FOOD_API_KEY"))

	// Whatever the scanner read: a plain barcode, a GS1 code or a GS1 Digital Link
	food, err := client.FoodByBarcode(ctx, "https://id.gs1.org/01/03017624010701")
	switch {
	case errors.Is(err, foodapi.ErrNotFound):
		fmt.Println("not found") // No source knows this barcode: an answer, not a failure
	case errors.Is(err, foodapi.ErrRateLimited), errors.Is(err, foodapi.ErrUnavailable):
		fmt.Println("try again soon") // Already retried; APIError.RetryAfter says when
	case err != nil:
		fmt.Println(err)
	default:
		fmt.Println(food.Name)
	}
}

func ExampleClient_Search() {
	ctx := context.Background()
	client := foodapi.New(os.Getenv("FOOD_API_KEY"))

	// Typos are fine; page 0 is the first page
	page, err := client.Search(ctx, "chiken brest", &foodapi.SearchOptions{Page: 0, Limit: 10})
	if err != nil {
		fmt.Println(err)
		return
	}
	if len(page.Foods) == 0 {
		fmt.Println("no matches")
		return
	}
	food, err := client.Food(ctx, page.Foods[0].ID) // The same food again, by its ID
	if err != nil {
		fmt.Println(err)
		return
	}
	fmt.Println(food.Name, food.AlternateNames())
}

func ExampleNutrients_Get() {
	ctx := context.Background()
	client := foodapi.New(os.Getenv("FOOD_API_KEY"))
	food, err := client.Food(ctx, "01a163d2-bfdc-7912-878d-4020b11915ab")
	if err != nil {
		fmt.Println(err)
		return
	}

	n := food.Servings[0].Nutrients // The last serving is always 100 g (or 100 ml)
	if kcal, ok := n.Get(foodapi.Calories); ok {
		fmt.Printf("%.0f kcal\n", kcal)
	}
	if sugar, ok := n.Get(foodapi.Sugar); ok {
		switch food.Flag(foodapi.Sugar) {
		case foodapi.FlagUpperBound:
			fmt.Printf("< %.1f g sugar\n", sugar) // The label said "less than"
		case foodapi.FlagApproximate:
			fmt.Printf("~%.1f g sugar\n", sugar)
		default:
			fmt.Printf("%.1f g sugar\n", sugar)
		}
	}
	if mg, ok := n.Get("magnesium"); ok { // Any nutrient key Client.Nutrients lists
		fmt.Printf("%.0f mg magnesium\n", mg)
	}
}

func ExampleClient_Autocomplete() {
	ctx := context.Background()
	client := foodapi.New(os.Getenv("FOOD_API_KEY"))

	// Cancel the context when the user types on, so a stale request stops
	result, err := client.Autocomplete(ctx, "chick", 8)
	if err != nil {
		fmt.Println(err)
		return
	}
	for _, s := range result.Suggestions {
		fmt.Println(s.Name)
	}
}
