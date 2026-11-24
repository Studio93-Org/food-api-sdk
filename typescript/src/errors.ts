// Errors the client throws. Every failure is a FoodApiError, so one `instanceof FoodApiError` catches them all;
// check the subclass to tell "not found" apart from "try again later".

/** Any failure of a Food API call. `message` is the API's explanation when it gave one. */
export class FoodApiError extends Error {
  override name = 'FoodApiError';

  constructor(message: string, options?: { cause?: unknown }) {
    super(message);
    if (options && 'cause' in options) this.cause = options.cause;
  }
}

/** An error response from the API. */
export class FoodApiHttpError extends FoodApiError {
  override name = 'FoodApiHttpError';

  /** The HTTP status. */
  readonly statusCode: number;

  /** How long the API said to wait before retrying (its Retry-After header), in milliseconds, or null. */
  readonly retryAfter: number | null;

  constructor(statusCode: number, message: string, retryAfter: number | null = null) {
    super(message);
    this.statusCode = statusCode;
    this.retryAfter = retryAfter;
  }

  /** The error for an error status. */
  static fromStatus(statusCode: number, message: string, retryAfter: number | null = null): FoodApiHttpError {
    switch (statusCode) {
      case 400:
        return new FoodApiBadRequest(message);
      case 401:
        return new FoodApiUnauthorized(message);
      case 403:
        return new FoodApiForbidden(message);
      case 404:
        return new FoodApiNotFound(message);
      case 429:
        return new FoodApiRateLimited(message, retryAfter);
      case 503:
        return new FoodApiUnavailable(message, retryAfter);
      default:
        return new FoodApiServerError(statusCode, message, retryAfter);
    }
  }
}

/** 400: a parameter is missing or invalid. */
export class FoodApiBadRequest extends FoodApiHttpError {
  override name = 'FoodApiBadRequest';

  constructor(message: string) {
    super(400, message);
  }
}

/** 401: the API key is missing, invalid or revoked. */
export class FoodApiUnauthorized extends FoodApiHttpError {
  override name = 'FoodApiUnauthorized';

  constructor(message: string) {
    super(401, message);
  }
}

/** 403: the API key may not call this, for example a v1 key calling the v2 API. */
export class FoodApiForbidden extends FoodApiHttpError {
  override name = 'FoodApiForbidden';

  constructor(message: string) {
    super(403, message);
  }
}

/** 404: no such food or barcode. An answer, not a failure: show "not found". */
export class FoodApiNotFound extends FoodApiHttpError {
  override name = 'FoodApiNotFound';

  constructor(message: string) {
    super(404, message);
  }
}

/** 429: too many requests; slow down and retry after `retryAfter`. */
export class FoodApiRateLimited extends FoodApiHttpError {
  override name = 'FoodApiRateLimited';

  constructor(message: string, retryAfter: number | null = null) {
    super(429, message, retryAfter);
  }
}

/** 503: busy or briefly unavailable; retry after `retryAfter`. */
export class FoodApiUnavailable extends FoodApiHttpError {
  override name = 'FoodApiUnavailable';

  constructor(message: string, retryAfter: number | null = null) {
    super(503, message, retryAfter);
  }
}

/** Any other error status (5xx, or an unexpected 4xx), or an answer that isn't valid JSON. */
export class FoodApiServerError extends FoodApiHttpError {
  override name = 'FoodApiServerError';
}

/** The API couldn't be reached (offline, DNS failure, connection reset). */
export class FoodApiNetworkError extends FoodApiError {
  override name = 'FoodApiNetworkError';
}

/**
 * An attempt took longer than the client's `timeout`, or the call's signal timed out (for example
 * `AbortSignal.timeout(5000)`).
 */
export class FoodApiTimeoutError extends FoodApiError {
  override name = 'FoodApiTimeoutError';
}

/**
 * The call was cancelled through its AbortSignal, for example by a newer search in the same FoodSearchSession.
 * Usually safe to ignore. `cause` is the signal's reason.
 */
export class FoodApiCancelledError extends FoodApiError {
  override name = 'FoodApiCancelledError';

  constructor(options?: { cause?: unknown }) {
    super('cancelled', options);
  }
}

/** The arguments were invalid; nothing was sent. */
export class FoodApiInvalidInput extends FoodApiError {
  override name = 'FoodApiInvalidInput';
}
