package foodapi

import (
	"errors"
	"fmt"
	"net/http"
	"time"
)

// Errors that APIError matches with errors.Is, by HTTP status.
var (
	ErrBadRequest   = errors.New("food api: bad request")   // 400: a parameter is missing or invalid
	ErrUnauthorized = errors.New("food api: unauthorized")  // 401: the API key is missing, invalid or revoked
	ErrNotFound     = errors.New("food api: not found")     // 404: no such food or barcode; an answer, not a failure
	ErrRateLimited  = errors.New("food api: rate limited")  // 429: slow down and retry
	ErrUnavailable  = errors.New("food api: unavailable")   // 503: busy or down for a moment; retry shortly
	ErrServer       = errors.New("food api: server error")  // other 5xx
	ErrInvalidInput = errors.New("food api: invalid input") // caught before sending a request
)

// APIError is an error response from the API.
type APIError struct {
	StatusCode int
	Message    string        // The API's explanation
	RetryAfter time.Duration // When the API said to retry (Retry-After), or 0
}

func (e *APIError) Error() string {
	return fmt.Sprintf("food api: %d %s: %s", e.StatusCode, http.StatusText(e.StatusCode), e.Message)
}

// Is matches the error to the sentinel for its status, so callers can write errors.Is(err, foodapi.ErrNotFound).
func (e *APIError) Is(target error) bool {
	switch target {
	case ErrBadRequest:
		return e.StatusCode == http.StatusBadRequest
	case ErrUnauthorized:
		return e.StatusCode == http.StatusUnauthorized
	case ErrNotFound:
		return e.StatusCode == http.StatusNotFound
	case ErrRateLimited:
		return e.StatusCode == http.StatusTooManyRequests
	case ErrUnavailable:
		return e.StatusCode == http.StatusServiceUnavailable
	case ErrServer:
		return e.StatusCode >= 500 && e.StatusCode != http.StatusServiceUnavailable
	}
	return false
}
