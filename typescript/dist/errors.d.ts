/** Any failure of a Food API call. `message` is the API's explanation when it gave one. */
export declare class FoodApiError extends Error {
    name: string;
    constructor(message: string, options?: {
        cause?: unknown;
    });
}
/** An error response from the API. */
export declare class FoodApiHttpError extends FoodApiError {
    name: string;
    /** The HTTP status. */
    readonly statusCode: number;
    /** How long the API said to wait before retrying (its Retry-After header), in milliseconds, or null. */
    readonly retryAfter: number | null;
    constructor(statusCode: number, message: string, retryAfter?: number | null);
    /** The error for an error status. */
    static fromStatus(statusCode: number, message: string, retryAfter?: number | null): FoodApiHttpError;
}
/** 400: a parameter is missing or invalid. */
export declare class FoodApiBadRequest extends FoodApiHttpError {
    name: string;
    constructor(message: string);
}
/** 401: the API key is missing, invalid or revoked. */
export declare class FoodApiUnauthorized extends FoodApiHttpError {
    name: string;
    constructor(message: string);
}
/** 403: the API key may not call this, for example a v1 key calling the v2 API. */
export declare class FoodApiForbidden extends FoodApiHttpError {
    name: string;
    constructor(message: string);
}
/** 404: no such food or barcode. An answer, not a failure: show "not found". */
export declare class FoodApiNotFound extends FoodApiHttpError {
    name: string;
    constructor(message: string);
}
/** 429: too many requests; slow down and retry after `retryAfter`. */
export declare class FoodApiRateLimited extends FoodApiHttpError {
    name: string;
    constructor(message: string, retryAfter?: number | null);
}
/** 503: busy or briefly unavailable; retry after `retryAfter`. */
export declare class FoodApiUnavailable extends FoodApiHttpError {
    name: string;
    constructor(message: string, retryAfter?: number | null);
}
/** Any other error status (5xx, or an unexpected 4xx), or an answer that isn't valid JSON. */
export declare class FoodApiServerError extends FoodApiHttpError {
    name: string;
}
/** The API couldn't be reached (offline, DNS failure, connection reset). */
export declare class FoodApiNetworkError extends FoodApiError {
    name: string;
}
/**
 * An attempt took longer than the client's `timeout`, or the call's signal timed out (for example
 * `AbortSignal.timeout(5000)`).
 */
export declare class FoodApiTimeoutError extends FoodApiError {
    name: string;
}
/**
 * The call was cancelled through its AbortSignal, for example by a newer search in the same FoodSearchSession.
 * Usually safe to ignore. `cause` is the signal's reason.
 */
export declare class FoodApiCancelledError extends FoodApiError {
    name: string;
    constructor(options?: {
        cause?: unknown;
    });
}
/** The arguments were invalid; nothing was sent. */
export declare class FoodApiInvalidInput extends FoodApiError {
    name: string;
}
