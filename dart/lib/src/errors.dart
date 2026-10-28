/// Errors the client throws. Every failure is a [FoodApiException], so one `on FoodApiException` catches them all;
/// switch on the subtype to tell "not found" apart from "try again later".
library;

/// Any failure of a Food API call.
sealed class FoodApiException implements Exception {
  const FoodApiException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// An error response from the API.
sealed class FoodApiHttpException extends FoodApiException {
  const FoodApiHttpException(this.statusCode, super.message, {this.retryAfter});

  final int statusCode;

  /// When the API said to retry (its Retry-After header), or null.
  final Duration? retryAfter;

  /// Builds the exception for an error status.
  static FoodApiHttpException fromStatus(int status, String message, {Duration? retryAfter}) => switch (status) {
    400 => FoodApiBadRequest(message),
    401 => FoodApiUnauthorized(message),
    404 => FoodApiNotFound(message),
    429 => FoodApiRateLimited(message, retryAfter: retryAfter),
    503 => FoodApiUnavailable(message, retryAfter: retryAfter),
    _ => FoodApiServerError(status, message, retryAfter: retryAfter),
  };
}

/// 400: a parameter is missing or invalid.
final class FoodApiBadRequest extends FoodApiHttpException {
  const FoodApiBadRequest(String message) : super(400, message);
}

/// 401: the API key is missing, invalid or revoked.
final class FoodApiUnauthorized extends FoodApiHttpException {
  const FoodApiUnauthorized(String message) : super(401, message);
}

/// 404: no such food or barcode. An answer, not a failure: show "not found".
final class FoodApiNotFound extends FoodApiHttpException {
  const FoodApiNotFound(String message) : super(404, message);
}

/// 429: too many requests; slow down and retry.
final class FoodApiRateLimited extends FoodApiHttpException {
  const FoodApiRateLimited(String message, {super.retryAfter}) : super(429, message);
}

/// 503: busy or briefly unavailable; retry after [retryAfter].
final class FoodApiUnavailable extends FoodApiHttpException {
  const FoodApiUnavailable(String message, {super.retryAfter}) : super(503, message);
}

/// Any other error status (5xx, or an unexpected 4xx).
final class FoodApiServerError extends FoodApiHttpException {
  const FoodApiServerError(super.statusCode, super.message, {super.retryAfter});
}

/// The API couldn't be reached (no connection, DNS failure, connection reset).
final class FoodApiNetworkException extends FoodApiException {
  const FoodApiNetworkException(super.message, [this.cause]);

  final Object? cause;
}

/// An attempt took longer than the client's timeout.
final class FoodApiTimeoutException extends FoodApiException {
  const FoodApiTimeoutException(super.message);
}

/// The call was cancelled, for example by a newer search in the same FoodSearchSession. Usually safe to ignore.
final class FoodApiCancelledException extends FoodApiException {
  const FoodApiCancelledException() : super('cancelled');
}

/// The arguments were invalid; nothing was sent.
final class FoodApiInvalidInput extends FoodApiException {
  const FoodApiInvalidInput(super.message);
}
