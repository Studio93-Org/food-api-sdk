package foodapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/rand/v2"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Version is the SDK version, sent in the User-Agent header.
const Version = "0.1.0"

// DefaultBaseURL is the Food API.
const DefaultBaseURL = "https://api.studio93.io"

const (
	defaultTimeout    = 15 * time.Second
	defaultMaxRetries = 2
	// The longest Retry-After the client waits for itself; a longer one is returned to the caller as an APIError
	maxRetryWait = 10 * time.Second
	// Limits the API enforces, checked before sending
	maxQueryRunes = 200
	maxPage       = 1000
	maxLimit      = 50
	maxSuggest    = 20
)

// Client calls the Food API's v2 endpoints. Create one and share it: it keeps connections open between requests,
// which saves a TCP and TLS handshake (one or two network round trips) on every request after the first. It is safe
// for concurrent use.
type Client struct {
	baseURL    *url.URL
	apiKey     string
	http       *http.Client
	maxRetries int
	userAgent  string
	wait       func(ctx context.Context, d time.Duration) error // Replaced in tests
}

// Option configures a Client.
type Option func(*Client)

// WithBaseURL sends requests to another server, such as a test server.
func WithBaseURL(baseURL string) Option {
	return func(c *Client) {
		if u, err := url.Parse(strings.TrimRight(baseURL, "/")); err == nil {
			c.baseURL = u
		}
	}
}

// WithHTTPClient uses your own http.Client. Keep it long-lived so connections are reused.
func WithHTTPClient(hc *http.Client) Option { return func(c *Client) { c.http = hc } }

// WithTimeout limits how long one attempt may take (default 15 s). Use a context deadline to limit a call overall.
func WithTimeout(d time.Duration) Option { return func(c *Client) { c.http.Timeout = d } }

// WithMaxRetries sets how many times a failed request is retried (default 2; 0 turns retries off). Only network
// errors and 429, 502, 503 and 504 responses are retried.
func WithMaxRetries(n int) Option { return func(c *Client) { c.maxRetries = max(n, 0) } }

// WithUserAgent adds your app's name and version to the User-Agent header ("my-app/1.4").
func WithUserAgent(product string) Option {
	return func(c *Client) { c.userAgent = product + " " + c.userAgent }
}

// New creates a client with an API key issued by Studio93.
func New(apiKey string, opts ...Option) *Client {
	base, _ := url.Parse(DefaultBaseURL)
	transport := http.DefaultTransport.(*http.Transport).Clone() // HTTP/2, keep-alive and gzip
	transport.MaxIdleConnsPerHost = 16
	c := &Client{
		baseURL:    base,
		apiKey:     apiKey,
		http:       &http.Client{Transport: transport, Timeout: defaultTimeout},
		maxRetries: defaultMaxRetries,
		userAgent:  "studio93-food-api-go/" + Version,
		wait:       sleep,
	}
	for _, opt := range opts {
		opt(c)
	}
	return c
}

// SearchOptions selects a page of search results.
type SearchOptions struct {
	Page  int // Zero-based, 0 to 1000
	Limit int // Results per page, 1 to 50; 0 means 20
}

// Search finds foods matching a query, typos and all ("chiken brest"). A query nothing matches returns an empty
// page, not an error.
func (c *Client) Search(ctx context.Context, query string, opts *SearchOptions) (*SearchPage, error) {
	if err := checkQuery(query); err != nil {
		return nil, err
	}
	params := url.Values{"q": {query}}
	if opts != nil {
		if opts.Page < 0 || opts.Page > maxPage {
			return nil, fmt.Errorf("%w: page must be between 0 and %d", ErrInvalidInput, maxPage)
		}
		if opts.Limit < 0 || opts.Limit > maxLimit {
			return nil, fmt.Errorf("%w: limit must be between 1 and %d", ErrInvalidInput, maxLimit)
		}
		if opts.Page > 0 {
			params.Set("page", strconv.Itoa(opts.Page))
		}
		if opts.Limit > 0 {
			params.Set("limit", strconv.Itoa(opts.Limit))
		}
	}
	var page struct {
		Data []Food `json:"data"`
		Meta struct {
			Query  string `json:"query"`
			Page   int    `json:"page"`
			Limit  int    `json:"limit"`
			Total  int64  `json:"total"`
			Source string `json:"source"`
		} `json:"meta"`
	}
	cached, err := c.get(ctx, "/v2/foods/search", params, &page)
	if err != nil {
		return nil, err
	}
	return &SearchPage{Foods: nonNil(page.Data), Query: page.Meta.Query, Page: page.Meta.Page, Limit: page.Meta.Limit,
		Total: page.Meta.Total, Source: page.Meta.Source, Cached: cached}, nil
}

// Autocomplete suggests foods for what has been typed so far; the last word matches as a prefix ("chick" finds
// Chicken). limit is 1 to 20; 0 means 8. It never asks outside providers, so it is fast enough for every keystroke.
func (c *Client) Autocomplete(ctx context.Context, query string, limit int) (*Autocomplete, error) {
	if err := checkQuery(query); err != nil {
		return nil, err
	}
	if limit < 0 || limit > maxSuggest {
		return nil, fmt.Errorf("%w: limit must be between 1 and %d", ErrInvalidInput, maxSuggest)
	}
	params := url.Values{"q": {query}}
	if limit > 0 {
		params.Set("limit", strconv.Itoa(limit))
	}
	var result struct {
		Data []Suggestion `json:"data"`
		Meta struct {
			Query string `json:"query"`
			Limit int    `json:"limit"`
			Total int64  `json:"total"`
		} `json:"meta"`
	}
	cached, err := c.get(ctx, "/v2/foods/autocomplete", params, &result)
	if err != nil {
		return nil, err
	}
	return &Autocomplete{Suggestions: nonNil(result.Data), Query: result.Meta.Query, Limit: result.Meta.Limit,
		Total: result.Meta.Total, Cached: cached}, nil
}

// Food returns a food by its catalog ID. An unknown ID is ErrNotFound.
func (c *Client) Food(ctx context.Context, id string) (*Food, error) {
	if strings.TrimSpace(id) == "" {
		return nil, fmt.Errorf("%w: empty food id", ErrInvalidInput)
	}
	var result struct {
		Data Food `json:"data"`
	}
	if _, err := c.get(ctx, "/v2/foods/"+url.PathEscape(id), nil, &result); err != nil {
		return nil, err
	}
	return &result.Data, nil
}

// FoodByBarcode returns the food for a barcode: 6 to 14 digits, or what a scanner read from a 2D code (a GS1 code
// such as "(01)03017624010701", or a GS1 Digital Link). A barcode no source knows is ErrNotFound.
func (c *Client) FoodByBarcode(ctx context.Context, barcode string) (*Food, error) {
	barcode = strings.TrimSpace(barcode)
	if barcode == "" {
		return nil, fmt.Errorf("%w: empty barcode", ErrInvalidInput)
	}
	var result struct {
		Data Food `json:"data"`
	}
	if _, err := c.get(ctx, "/v2/foods/barcode/"+url.PathEscape(barcode), nil, &result); err != nil {
		return nil, err
	}
	return &result.Data, nil
}

// NutrientStats returns what a food's source says about each of its nutrient values: samples, spread and how each
// was obtained. Foods whose source gives no such details have none.
func (c *Client) NutrientStats(ctx context.Context, foodID string) (*NutrientStats, error) {
	if strings.TrimSpace(foodID) == "" {
		return nil, fmt.Errorf("%w: empty food id", ErrInvalidInput)
	}
	var result struct {
		Data NutrientStats `json:"data"`
	}
	if _, err := c.get(ctx, "/v2/foods/"+url.PathEscape(foodID)+"/nutrient-stats", nil, &result); err != nil {
		return nil, err
	}
	if result.Data.Nutrients == nil {
		result.Data.Nutrients = map[string]NutrientStat{}
	}
	return &result.Data, nil
}

// Nutrients lists every nutrient key a serving can have, with its name and unit.
func (c *Client) Nutrients(ctx context.Context) (*NutrientList, error) {
	var result struct {
		Data NutrientList `json:"data"`
	}
	if _, err := c.get(ctx, "/v2/nutrients", nil, &result); err != nil {
		return nil, err
	}
	return &result.Data, nil
}

func checkQuery(q string) error {
	if strings.TrimSpace(q) == "" {
		return fmt.Errorf("%w: empty query", ErrInvalidInput)
	}
	if len([]rune(q)) > maxQueryRunes {
		return fmt.Errorf("%w: query longer than %d characters", ErrInvalidInput, maxQueryRunes)
	}
	return nil
}

// get sends a GET request, retrying what is safe to retry, and decodes the response into out. It reports whether
// the API answered from its cache.
// path is already escaped (url.PathEscape), so encoded slashes in a barcode link stay encoded.
func (c *Client) get(ctx context.Context, path string, params url.Values, out any) (cached bool, err error) {
	rawURL := strings.TrimRight(c.baseURL.String(), "/") + path
	if len(params) > 0 {
		rawURL += "?" + params.Encode()
	}

	for attempt := 0; ; attempt++ {
		cached, retryAfter, err := c.once(ctx, rawURL, out)
		if err == nil || attempt >= c.maxRetries || !retryable(err) || ctx.Err() != nil {
			return cached, err
		}
		delay := retryAfter
		if delay == 0 {
			delay = backoff(attempt)
		}
		if delay > maxRetryWait {
			return false, err // Not worth waiting here; the caller can decide
		}
		if werr := c.wait(ctx, delay); werr != nil {
			return false, err
		}
	}
}

// once sends one request. retryAfter is the API's Retry-After, when it gave one.
func (c *Client) once(ctx context.Context, rawURL string, out any) (cached bool, retryAfter time.Duration, err error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return false, 0, err
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", c.userAgent)

	resp, err := c.http.Do(req)
	if err != nil {
		return false, 0, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 32<<20))
	if err != nil {
		return false, 0, err
	}
	if resp.StatusCode != http.StatusOK {
		apiErr := &APIError{StatusCode: resp.StatusCode, Message: errorMessage(body, resp.Status),
			RetryAfter: parseRetryAfter(resp.Header.Get("Retry-After"))}
		return false, apiErr.RetryAfter, apiErr
	}
	if err := json.Unmarshal(body, out); err != nil {
		return false, 0, fmt.Errorf("food api: invalid response: %w", err)
	}
	return resp.Header.Get("X-Cache") == "HIT", 0, nil
}

func errorMessage(body []byte, status string) string {
	var e struct {
		Message string `json:"message"`
	}
	if json.Unmarshal(body, &e) == nil && e.Message != "" {
		return e.Message
	}
	return status
}

// retryable reports whether a failed request may succeed when sent again.
func retryable(err error) bool {
	var apiErr *APIError
	if errors.As(err, &apiErr) {
		switch apiErr.StatusCode {
		case http.StatusTooManyRequests, http.StatusBadGateway, http.StatusServiceUnavailable, http.StatusGatewayTimeout:
			return true
		}
		return false
	}
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		return false
	}
	var netErr net.Error
	var urlErr *url.Error
	return errors.As(err, &netErr) || errors.As(err, &urlErr) || errors.Is(err, io.ErrUnexpectedEOF)
}

// parseRetryAfter reads a Retry-After header: seconds, or an HTTP date.
func parseRetryAfter(v string) time.Duration {
	if v == "" {
		return 0
	}
	if s, err := strconv.Atoi(strings.TrimSpace(v)); err == nil && s >= 0 {
		return time.Duration(s) * time.Second
	}
	if t, err := http.ParseTime(v); err == nil {
		return max(time.Until(t), 0)
	}
	return 0
}

// backoff is the wait before retry attempt+1 when the API didn't say: 0.5 s, 1 s, … with jitter.
func backoff(attempt int) time.Duration {
	d := 500 * time.Millisecond << attempt
	return d/2 + time.Duration(rand.Int64N(int64(d/2)+1))
}

func sleep(ctx context.Context, d time.Duration) error {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-t.C:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func nonNil[T any](s []T) []T {
	if s == nil {
		return []T{}
	}
	return s
}
