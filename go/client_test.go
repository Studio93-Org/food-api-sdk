package foodapi

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

const foodJSON = `{"id":"01a163d2-bfdc-7912-878d-4020b11915ab","name":"Cola","brand":null,"type":"generic","barcodes":[],
 "servings":[{"description":"100 g","measurement":"g","metric_amount":100,"metric_unit":"g","units":100,
   "nutrients":{"calories":37,"protein":0,"sugar":0.5,"fiber":null,"cnf_409":0.01}},
  {"description":"1 fl oz","measurement":"fl oz","metric_amount":29.57,"metric_unit":"ml","units":1,"generic":true,
   "nutrients":{"calories":10.94}}],
 "source":{"provider":"CNF","id":"2920"},"ingredients":null,"category":"Beverages",
 "attributes":{"alternate_names":"pop, soda, soft drink"},"nutrient_flags":{"sugar":"upper_bound"}}`

// testClient returns a client for a test server and the waits its retries asked for.
func testClient(t *testing.T, handler http.HandlerFunc, opts ...Option) (*Client, *[]time.Duration) {
	t.Helper()
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	c := New("test-key", append([]Option{WithBaseURL(srv.URL)}, opts...)...)
	var waits []time.Duration
	c.wait = func(ctx context.Context, d time.Duration) error {
		waits = append(waits, d)
		return ctx.Err()
	}
	return c, &waits
}

func TestSearch(t *testing.T) {
	c, _ := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v2/foods/search" || r.URL.Query().Get("q") != "Cola  Zero" || r.URL.Query().Get("page") != "2" || r.URL.Query().Get("limit") != "5" {
			t.Errorf("request = %s", r.URL)
		}
		if r.Header.Get("Authorization") != "Bearer test-key" || !strings.HasPrefix(r.Header.Get("User-Agent"), "my-app/1.0 studio93-food-api-go/") {
			t.Errorf("headers = %v", r.Header)
		}
		w.Header().Set("X-Cache", "HIT")
		w.Write([]byte(`{"data":[` + foodJSON + `],"meta":{"query":"cola zero","page":2,"limit":5,"total":11,"source":"catalog"}}`))
	}, WithUserAgent("my-app/1.0"))

	page, err := c.Search(context.Background(), "Cola  Zero", &SearchOptions{Page: 2, Limit: 5})
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Foods) != 1 || page.Query != "cola zero" || page.Total != 11 || page.Source != "catalog" || !page.Cached {
		t.Fatalf("page = %+v", page)
	}
	f := page.Foods[0]
	n := f.Servings[0].Nutrients
	if kcal, ok := n.Get(Calories); !ok || kcal != 37 {
		t.Errorf("calories = %v %v", kcal, ok)
	}
	if _, ok := n.Get(Fiber); ok {
		t.Error("fiber is unknown (null) and should say so")
	}
	if v, ok := n.Get("cnf_409"); !ok || v != 0.01 {
		t.Errorf("other nutrients should be readable by key: %v", v)
	}
	if f.Servings[0].Generic || !f.Servings[1].Generic || f.Servings[1].Description != "1 fl oz" {
		t.Errorf("generic flags = %v, %v", f.Servings[0].Generic, f.Servings[1].Generic)
	}
	if f.Flag(Sugar) != FlagUpperBound || f.Flag(Protein) != "" {
		t.Errorf("flags = %v", f.NutrientFlags)
	}
	if names := f.AlternateNames(); len(names) != 3 || names[1] != "soda" {
		t.Errorf("alternate names = %q", names)
	}
}

func TestEmptyResultsAreEmptyNotNil(t *testing.T) {
	c, _ := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "autocomplete") {
			w.Write([]byte(`{"data":null,"meta":{"query":"xq","limit":8,"total":0}}`))
			return
		}
		w.Write([]byte(`{"data":[],"meta":{"query":"xqzw","page":0,"limit":20,"total":0,"source":"catalog"}}`))
	})
	page, err := c.Search(context.Background(), "xqzw", nil)
	if err != nil || page.Foods == nil || len(page.Foods) != 0 {
		t.Errorf("search: %+v, %v", page, err)
	}
	ac, err := c.Autocomplete(context.Background(), "xq", 0)
	if err != nil || ac.Suggestions == nil {
		t.Errorf("autocomplete: %+v, %v", ac, err)
	}
}

func TestBarcodeLinksAreEscaped(t *testing.T) {
	c, _ := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.EscapedPath() != "/v2/foods/barcode/https:%2F%2Fid.gs1.org%2F01%2F03017624010701" {
			t.Errorf("path = %s", r.URL.EscapedPath())
		}
		w.Write([]byte(`{"data":` + foodJSON + `}`))
	})
	if _, err := c.FoodByBarcode(context.Background(), " https://id.gs1.org/01/03017624010701 "); err != nil {
		t.Fatal(err)
	}
}

func TestErrors(t *testing.T) {
	for status, want := range map[int]error{
		400: ErrBadRequest, 401: ErrUnauthorized, 404: ErrNotFound, 429: ErrRateLimited, 503: ErrUnavailable, 500: ErrServer, 502: ErrServer,
	} {
		c, _ := testClient(t, func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(status)
			w.Write([]byte(`{"message":"explained","data":{}}`))
		}, WithMaxRetries(0))
		_, err := c.Food(context.Background(), "01a163d2-bfdc-7912-878d-4020b11915ab")
		var apiErr *APIError
		if !errors.Is(err, want) || !errors.As(err, &apiErr) || apiErr.StatusCode != status || apiErr.Message != "explained" {
			t.Errorf("%d: err = %v, want %v", status, err, want)
		}
		if status != 404 && errors.Is(err, ErrNotFound) {
			t.Errorf("%d matched ErrNotFound", status)
		}
	}
}

func TestRetriesHonourRetryAfter(t *testing.T) {
	var calls atomic.Int32
	c, waits := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if calls.Add(1) == 1 {
			w.Header().Set("Retry-After", "2")
			w.WriteHeader(http.StatusServiceUnavailable)
			w.Write([]byte(`{"message":"search is busy, please retry in a few seconds","data":{}}`))
			return
		}
		w.Write([]byte(`{"data":` + foodJSON + `}`))
	})
	if _, err := c.Food(context.Background(), "x"); err != nil {
		t.Fatal(err)
	}
	if calls.Load() != 2 || len(*waits) != 1 || (*waits)[0] != 2*time.Second {
		t.Errorf("calls %d, waits %v; want one retry after the 2 s the API asked for", calls.Load(), *waits)
	}
}

func TestRetryLimits(t *testing.T) {
	t.Run("gives up after max retries, backing off without Retry-After", func(t *testing.T) {
		var calls atomic.Int32
		c, waits := testClient(t, func(w http.ResponseWriter, r *http.Request) {
			calls.Add(1)
			w.WriteHeader(http.StatusTooManyRequests)
		})
		_, err := c.Food(context.Background(), "x")
		if !errors.Is(err, ErrRateLimited) || calls.Load() != 3 || len(*waits) != 2 || (*waits)[1] <= 0 {
			t.Errorf("err %v, calls %d, waits %v", err, calls.Load(), *waits)
		}
	})
	t.Run("a long Retry-After is left to the caller", func(t *testing.T) {
		var calls atomic.Int32
		c, waits := testClient(t, func(w http.ResponseWriter, r *http.Request) {
			calls.Add(1)
			w.Header().Set("Retry-After", "60")
			w.WriteHeader(http.StatusServiceUnavailable)
		})
		_, err := c.Food(context.Background(), "x")
		var apiErr *APIError
		if !errors.As(err, &apiErr) || apiErr.RetryAfter != time.Minute || calls.Load() != 1 || len(*waits) != 0 {
			t.Errorf("err %v, calls %d, waits %v", err, calls.Load(), *waits)
		}
	})
	t.Run("client errors aren't retried", func(t *testing.T) {
		var calls atomic.Int32
		c, _ := testClient(t, func(w http.ResponseWriter, r *http.Request) {
			calls.Add(1)
			w.WriteHeader(http.StatusNotFound)
		})
		if _, err := c.Food(context.Background(), "x"); !errors.Is(err, ErrNotFound) || calls.Load() != 1 {
			t.Errorf("err %v, calls %d", err, calls.Load())
		}
	})
	t.Run("a cancelled call stops", func(t *testing.T) {
		ctx, cancel := context.WithCancel(context.Background())
		var calls atomic.Int32
		c, _ := testClient(t, func(w http.ResponseWriter, r *http.Request) {
			calls.Add(1)
			cancel()
			w.WriteHeader(http.StatusServiceUnavailable)
		})
		if _, err := c.Food(ctx, "x"); err == nil || calls.Load() != 1 {
			t.Errorf("err %v, calls %d; want one attempt", err, calls.Load())
		}
	})
}

func TestInvalidInputSendsNothing(t *testing.T) {
	c, _ := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		t.Errorf("unexpected request %s", r.URL)
	})
	ctx := context.Background()
	if _, err := c.Search(ctx, "  ", nil); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("empty query: %v", err)
	}
	if _, err := c.Search(ctx, strings.Repeat("a", 201), nil); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("long query: %v", err)
	}
	if _, err := c.Search(ctx, "apple", &SearchOptions{Limit: 51}); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("limit: %v", err)
	}
	if _, err := c.Autocomplete(ctx, "app", 21); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("autocomplete limit: %v", err)
	}
	if _, err := c.FoodByBarcode(ctx, ""); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("barcode: %v", err)
	}
}

func TestNutrientStatsAndList(t *testing.T) {
	c, _ := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v2/foods/abc/nutrient-stats":
			w.Write([]byte(`{"data":{"id":"abc","per":"100 g","nutrients":{"protein":{"data_points":12,"min":3.12,"derivation":"A","derivation_description":"Analytical"}}}}`))
		case "/v2/nutrients":
			w.Write([]byte(`{"data":{"nutrients":[{"key":"calories","name":"Energy","unit":"kcal","group":"energy","core":true}],"other":[{"key":"usda_1018","name":"Ash","unit":"g","source":"USDA"}]}}`))
		default:
			t.Errorf("unexpected %s", r.URL)
		}
	})
	stats, err := c.NutrientStats(context.Background(), "abc")
	if err != nil || stats.Per != "100 g" || *stats.Nutrients["protein"].DataPoints != 12 || stats.Nutrients["protein"].DerivationDescription != "Analytical" {
		t.Errorf("stats = %+v, %v", stats, err)
	}
	list, err := c.Nutrients(context.Background())
	if err != nil || len(list.Nutrients) != 1 || !list.Nutrients[0].Core || list.Other[0].Key != "usda_1018" {
		t.Errorf("nutrients = %+v, %v", list, err)
	}
}

func TestParseRetryAfter(t *testing.T) {
	if parseRetryAfter("3") != 3*time.Second || parseRetryAfter("") != 0 || parseRetryAfter("soon") != 0 {
		t.Error("seconds form")
	}
	if d := parseRetryAfter(time.Now().Add(5 * time.Second).UTC().Format(http.TimeFormat)); d <= 0 || d > 5*time.Second {
		t.Errorf("date form = %v", d)
	}
}
