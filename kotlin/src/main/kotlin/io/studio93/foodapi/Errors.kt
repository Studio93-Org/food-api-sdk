package io.studio93.foodapi

import kotlinx.coroutines.CancellationException
import kotlin.time.Duration

/**
 * Any failure of a Food API call. Every failure the client throws is one, except cancellation, so one
 * `catch (e: FoodApiException)` catches them all; use `when` on the subtype to tell "not found" apart from "try
 * again later".
 */
public sealed class FoodApiException(
    /** The API's explanation, or what went wrong. */
    override val message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

/** An error response from the API. */
public sealed class FoodApiHttpException(
    /** The HTTP status. */
    public val statusCode: Int,
    message: String,
    /** When the API said to retry (its Retry-After header), or null. */
    public val retryAfter: Duration? = null,
) : FoodApiException(message) {
    override fun toString(): String = "${this::class.simpleName}: $statusCode $message"

    public companion object {
        /** The exception for an error status. */
        public fun fromStatus(statusCode: Int, message: String, retryAfter: Duration? = null): FoodApiHttpException =
            when (statusCode) {
                400 -> FoodApiBadRequest(message)
                401 -> FoodApiUnauthorized(message)
                403 -> FoodApiForbidden(message)
                404 -> FoodApiNotFound(message)
                429 -> FoodApiRateLimited(message, retryAfter)
                503 -> FoodApiUnavailable(message, retryAfter)
                else -> FoodApiServerError(statusCode, message, retryAfter)
            }
    }
}

/** 400: a parameter is missing or invalid. */
public class FoodApiBadRequest(message: String) : FoodApiHttpException(400, message)

/** 401: the API key is missing, invalid or revoked. */
public class FoodApiUnauthorized(message: String) : FoodApiHttpException(401, message)

/** 403: the API key may not call this, for example a v1 key calling the v2 API. */
public class FoodApiForbidden(message: String) : FoodApiHttpException(403, message)

/** 404: no such food or barcode. An answer, not a failure: show "not found". */
public class FoodApiNotFound(message: String) : FoodApiHttpException(404, message)

/** 429: too many requests; slow down and retry after [retryAfter]. */
public class FoodApiRateLimited(message: String, retryAfter: Duration? = null) :
    FoodApiHttpException(429, message, retryAfter)

/** 503: busy or briefly unavailable; retry after [retryAfter]. */
public class FoodApiUnavailable(message: String, retryAfter: Duration? = null) :
    FoodApiHttpException(503, message, retryAfter)

/** Any other error status (5xx, or an unexpected 4xx), or an answer the SDK couldn't read. */
public class FoodApiServerError(statusCode: Int, message: String, retryAfter: Duration? = null) :
    FoodApiHttpException(statusCode, message, retryAfter)

/** The API couldn't be reached (no connection, DNS failure, connection reset). */
public class FoodApiNetworkException(message: String, cause: Throwable? = null) : FoodApiException(message, cause) {
    override fun toString(): String = "FoodApiNetworkException: $message"
}

/** An attempt took longer than the client's timeout. */
public class FoodApiTimeoutException(message: String, cause: Throwable? = null) : FoodApiException(message, cause) {
    override fun toString(): String = "FoodApiTimeoutException: $message"
}

/** The arguments were invalid; nothing was sent. */
public class FoodApiInvalidInput(message: String) : FoodApiException(message) {
    override fun toString(): String = "FoodApiInvalidInput: $message"
}

/**
 * A call a [FoodSearchSession] cancelled, because a newer one replaced it or the session was cancelled. It is a
 * [CancellationException], so a coroutine that doesn't catch it just ends quietly; catch it only to tell it apart.
 */
public class FoodApiCancelledException(message: String = "cancelled") : CancellationException(message)
