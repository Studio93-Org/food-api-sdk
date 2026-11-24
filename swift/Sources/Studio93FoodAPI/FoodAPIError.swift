import Foundation

/// Every failure of a Food API call. Switch on it to tell "not found" apart from "try again later":
///
/// ```swift
/// do {
///     let food = try await foodAPI.foodByBarcode(scanned)
/// } catch FoodAPIError.notFound {
///     showNotFound() // No source knows this barcode: an answer, not a failure
/// } catch FoodAPIError.cancelled {
///     // Superseded by a newer search
/// } catch {
///     showError(error)
/// }
/// ```
public enum FoodAPIError: Error, Sendable, Hashable {
    /// 400: a parameter is missing or invalid.
    case badRequest(message: String)
    /// 401: the API key is missing, invalid or revoked.
    case unauthorized(message: String)
    /// 403: the key can't use this call, for example a key issued for another API version.
    case forbidden(message: String)
    /// 404: no such food or barcode. An answer, not a failure: show "not found".
    case notFound(message: String)
    /// 429: too many requests; slow down and retry after `retryAfter`, when the API said.
    case rateLimited(message: String, retryAfter: TimeInterval?)
    /// 503: busy or briefly unavailable; retry after `retryAfter`, when the API said.
    case unavailable(message: String, retryAfter: TimeInterval?)
    /// Any other error status (5xx, or an unexpected 4xx), or an answer the SDK couldn't read (status 200).
    case server(statusCode: Int, message: String, retryAfter: TimeInterval?)
    /// The API couldn't be reached: no connection, DNS failure, connection reset. `URLError.code` says which.
    case network(URLError)
    /// An attempt took longer than the client's timeout.
    case timeout
    /// The call was cancelled: its task was cancelled, or a newer search in the same `FoodSearchSession` replaced
    /// it. Usually safe to ignore.
    case cancelled
    /// The arguments were invalid; nothing was sent.
    case invalidInput(String)

    /// The HTTP status of an error response, or nil for errors that had none.
    public var statusCode: Int? {
        switch self {
        case .badRequest: 400
        case .unauthorized: 401
        case .forbidden: 403
        case .notFound: 404
        case .rateLimited: 429
        case .unavailable: 503
        case .server(let status, _, _): status
        case .network, .timeout, .cancelled, .invalidInput: nil
        }
    }

    /// The API's explanation, or a description of what went wrong.
    public var message: String {
        switch self {
        case .badRequest(let m), .unauthorized(let m), .forbidden(let m), .notFound(let m): m
        case .rateLimited(let m, _), .unavailable(let m, _), .server(_, let m, _): m
        case .network(let error): error.localizedDescription
        case .timeout: "no answer in time"
        case .cancelled: "cancelled"
        case .invalidInput(let m): m
        }
    }

    /// How long the API asked to wait before retrying (its Retry-After header), or nil.
    public var retryAfter: TimeInterval? {
        switch self {
        case .rateLimited(_, let r), .unavailable(_, let r), .server(_, _, let r): r
        default: nil
        }
    }

    /// Whether the device couldn't reach the API or it didn't answer in time: worth an "offline" message.
    public var isOffline: Bool {
        switch self {
        case .network, .timeout: true
        default: false
        }
    }

    static func from(status: Int, message: String, retryAfter: TimeInterval?) -> FoodAPIError {
        switch status {
        case 400: .badRequest(message: message)
        case 401: .unauthorized(message: message)
        case 403: .forbidden(message: message)
        case 404: .notFound(message: message)
        case 429: .rateLimited(message: message, retryAfter: retryAfter)
        case 503: .unavailable(message: message, retryAfter: retryAfter)
        default: .server(statusCode: status, message: message, retryAfter: retryAfter)
        }
    }

    /// Whether the request may succeed when sent again.
    var isRetryable: Bool {
        switch self {
        case .network, .timeout, .rateLimited, .unavailable: true
        case .server(let status, _, _): status == 502 || status == 504
        default: false
        }
    }
}

extension FoodAPIError: LocalizedError {
    public var errorDescription: String? {
        if let status = statusCode {
            return "Food API: \(status) \(HTTPURLResponse.localizedString(forStatusCode: status)): \(message)"
        }
        return "Food API: \(message)"
    }
}
