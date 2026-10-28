package foodapi

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"
)

// TestLive calls the real API. It runs only with an API key:
//
//	FOOD_API_KEY=... go test -run TestLive ./...
func TestLive(t *testing.T) {
	key := os.Getenv("FOOD_API_KEY")
	if key == "" {
		t.Skip("FOOD_API_KEY not set")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	c := New(key, WithUserAgent("food-api-sdk-tests"))

	page, err := c.Search(ctx, "whole milk", &SearchOptions{Page: 1, Limit: 5}) // Page 1: catalog only
	if err != nil || len(page.Foods) == 0 {
		t.Fatalf("search: %+v, %v", page, err)
	}
	if _, ok := page.Foods[0].Servings[0].Nutrients.Get(Calories); !ok {
		t.Errorf("first result has no calories: %+v", page.Foods[0])
	}
	food, err := c.Food(ctx, page.Foods[0].ID)
	if err != nil || food.ID != page.Foods[0].ID {
		t.Errorf("food by id: %v", err)
	}
	if ac, err := c.Autocomplete(ctx, "chick", 5); err != nil || len(ac.Suggestions) == 0 {
		t.Errorf("autocomplete: %+v, %v", ac, err)
	}
	if f, err := c.FoodByBarcode(ctx, "https://id.gs1.org/01/03017624010701"); err != nil || f.Name == "" {
		t.Errorf("barcode link: %+v, %v", f, err)
	}
	if _, err := c.Food(ctx, "01a163d2-0000-7000-8000-000000000000"); !errors.Is(err, ErrNotFound) {
		t.Errorf("unknown food: %v, want ErrNotFound", err)
	}
	if _, err := c.NutrientStats(ctx, page.Foods[0].ID); err != nil {
		t.Errorf("nutrient stats: %v", err)
	}
	if list, err := c.Nutrients(ctx); err != nil || len(list.Nutrients) < 17 {
		t.Errorf("nutrients: %v", err)
	}
	if _, err := New("not-a-key").Search(ctx, "apple", &SearchOptions{Page: 1}); !errors.Is(err, ErrUnauthorized) {
		t.Errorf("bad key: %v, want ErrUnauthorized", err)
	}
}
