import Foundation

/// Calls the Food API's v2 endpoints.
///
/// Create one for the whole app and share it: it keeps connections open between requests (URLSession, with HTTP/2
/// and HTTP/3 and gzip), which saves a TCP and TLS handshake (one or two network round trips) on every request after
/// the first. It is `Sendable`, so any task or actor can use it.
///
/// ```swift
/// let foodAPI = FoodAPIClient(apiKey: apiKey, userAgent: "my-app/1.4.0")
///
/// let page = try await foodAPI.search("greek yogurt")
/// for food in page.foods {
///     print(food.name, food.servings.first?.nutrients.calories ?? 0)
/// }
/// ```
///
/// Every call is `async throws` and throws only `FoodAPIError`. Cancelling the calling task cancels the request,
/// and any wait before a retry, with `FoodAPIError.cancelled`.
public final class FoodAPIClient: Sendable {
    /// The SDK version, sent in the User-Agent header.
    public static let sdkVersion = "0.4.0"

    /// The Food API.
    public static let defaultBaseURL = URL(string: "https://api.studio93.io")!

    /// Where requests go.
    public let baseURL: URL
    /// How long one attempt may take.
    public let timeout: TimeInterval
    /// How often a request that failed for a temporary reason (network error, timeout, 429, 502, 503, 504) is sent
    /// again.
    public let maxRetries: Int
    /// The end user's IP address sent with every call, set with `withClientIP(_:)`; nil for apps on the user's device.
    public let clientIP: String?

    private let apiKey: String
    private let userAgent: String
    private let transport: Transport
    private let wait: @Sendable (TimeInterval) async throws -> Void

    /// Creates a client with an API key issued by Studio93.
    ///
    /// - Parameters:
    ///   - baseURL: Another server, such as a test server.
    ///   - timeout: How long one attempt may take (default 15 s). Cancel the task to limit a call overall.
    ///   - maxRetries: How often a temporary failure is retried (default 2; 0 turns retries off).
    ///   - userAgent: Your app's name and version ("my-app/1.4.0"), put before the SDK's in the User-Agent header.
    ///   - urlSession: Your own session, for example with a custom configuration in tests. Keep it long-lived so
    ///     connections are reused; the client then leaves it open. By default the client creates one.
    public convenience init(
        apiKey: String,
        baseURL: URL = FoodAPIClient.defaultBaseURL,
        timeout: TimeInterval = 15,
        maxRetries: Int = 2,
        userAgent: String? = nil,
        urlSession: URLSession? = nil
    ) {
        self.init(
            apiKey: apiKey, baseURL: baseURL, timeout: timeout, maxRetries: maxRetries, userAgent: userAgent,
            urlSession: urlSession, wait: { try await Task.sleep(nanoseconds: UInt64(max($0, 0) * 1e9)) })
    }

    /// `wait` is replaced in tests, to see the waits between retries without sleeping.
    convenience init(
        apiKey: String,
        baseURL: URL,
        timeout: TimeInterval,
        maxRetries: Int,
        userAgent: String?,
        urlSession: URLSession?,
        wait: @escaping @Sendable (TimeInterval) async throws -> Void
    ) {
        let transport: Transport
        if let urlSession {
            transport = Transport(session: urlSession, owned: false)
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.httpMaximumConnectionsPerHost = 16
            transport = Transport(session: URLSession(configuration: configuration), owned: true)
        }
        self.init(
            apiKey: apiKey, baseURL: baseURL, timeout: timeout, maxRetries: max(maxRetries, 0),
            userAgent: [userAgent, "studio93-food-api-swift/\(Self.sdkVersion)"].compactMap { $0 }.joined(
                separator: " "),
            clientIP: nil, transport: transport, wait: wait)
    }

    private init(
        apiKey: String, baseURL: URL, timeout: TimeInterval, maxRetries: Int, userAgent: String, clientIP: String?,
        transport: Transport, wait: @escaping @Sendable (TimeInterval) async throws -> Void
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.timeout = timeout
        self.maxRetries = maxRetries
        self.userAgent = userAgent
        self.clientIP = clientIP
        self.transport = transport
        self.wait = wait
    }

    /// A client for calls made for one of your users, carrying that user's IP address, for servers that call the
    /// API for their users. Search then ranks for the user's country rather than your server's (with a key that has
    /// regional ranking), and usage by country counts the user's. It shares this client's connections, so make one
    /// per incoming request. Apps that call the API from the user's own device don't need it.
    ///
    /// The address is sent as the `X-Client-IP` header. One that isn't IPv4 or IPv6 makes each call throw
    /// `FoodAPIError.invalidInput` without a request. Rate limits still apply to your server's own address.
    public func withClientIP(_ ip: String) -> FoodAPIClient {
        let ip = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        return FoodAPIClient(
            apiKey: apiKey, baseURL: baseURL, timeout: timeout, maxRetries: maxRetries, userAgent: userAgent,
            clientIP: ip.isEmpty ? nil : ip, transport: transport, wait: wait)
    }

    /// Finds foods matching a query, typos and all ("chiken brest"). `page` is zero-based (0 to 1000), `limit` is 1
    /// to 50. A query nothing matches returns an empty page, not an error.
    public func search(_ query: String, page: Int = 0, limit: Int = 20) async throws -> SearchPage {
        try checkQuery(query)
        guard (0...Limits.page).contains(page) else {
            throw FoodAPIError.invalidInput("page must be between 0 and \(Limits.page)")
        }
        guard (1...Limits.limit).contains(limit) else {
            throw FoodAPIError.invalidInput("limit must be between 1 and \(Limits.limit)")
        }
        let (body, cached): (ListEnvelope<Food, SearchMeta>, Bool) = try await get(
            ["v2", "foods", "search"], query: [("q", query), ("page", "\(page)"), ("limit", "\(limit)")])
        let meta = body.meta
        return SearchPage(
            foods: body.data ?? [], query: meta?.query ?? query, page: meta?.page ?? page,
            limit: meta?.limit ?? limit, total: meta?.total ?? 0, source: meta?.source ?? "catalog",
            region: meta?.region.flatMap { $0.isEmpty ? nil : $0 }, cached: cached)
    }

    /// Suggests foods for what has been typed so far; the last word matches as a prefix ("chick" finds Chicken).
    /// `limit` is 1 to 20. It never asks outside providers, so it is fast enough for every keystroke.
    public func autocomplete(_ query: String, limit: Int = 8) async throws -> AutocompleteResult {
        try checkQuery(query)
        guard (1...Limits.suggestions).contains(limit) else {
            throw FoodAPIError.invalidInput("limit must be between 1 and \(Limits.suggestions)")
        }
        let (body, cached): (ListEnvelope<Suggestion, AutocompleteMeta>, Bool) = try await get(
            ["v2", "foods", "autocomplete"], query: [("q", query), ("limit", "\(limit)")])
        let meta = body.meta
        return AutocompleteResult(
            suggestions: body.data ?? [], query: meta?.query ?? query, limit: meta?.limit ?? limit,
            total: meta?.total ?? 0, cached: cached)
    }

    /// The food with a catalog ID. An unknown ID throws `FoodAPIError.notFound`.
    public func food(_ id: String) async throws -> Food {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw FoodAPIError.invalidInput("empty food id") }
        let (body, _): (DataEnvelope<Food>, Bool) = try await get(["v2", "foods", id])
        return body.data
    }

    /// The food for a barcode: 6 to 14 digits, or what a scanner read from a 2D code (a GS1 code such as
    /// "(01)03017624010701", or a GS1 Digital Link). A barcode no source knows throws `FoodAPIError.notFound`.
    public func foodByBarcode(_ barcode: String) async throws -> Food {
        let barcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !barcode.isEmpty else { throw FoodAPIError.invalidInput("empty barcode") }
        let (body, _): (DataEnvelope<Food>, Bool) = try await get(["v2", "foods", "barcode", barcode])
        return body.data
    }

    /// What a food's source says about each of its nutrient values: samples, spread and how each was obtained.
    /// Foods whose source gives no such details have none.
    public func nutrientStats(_ foodID: String) async throws -> NutrientStats {
        let foodID = foodID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !foodID.isEmpty else { throw FoodAPIError.invalidInput("empty food id") }
        let (body, _): (DataEnvelope<NutrientStats>, Bool) = try await get(["v2", "foods", foodID, "nutrient-stats"])
        return body.data
    }

    /// Every nutrient key a serving can have, with its name and unit.
    public func nutrients() async throws -> NutrientList {
        let (body, _): (DataEnvelope<NutrientList>, Bool) = try await get(["v2", "nutrients"])
        return body.data
    }

    /// Every food image, with its label, group and URL, for apps that bundle or prefetch them. Foods carry their own
    /// `Food.image`, so showing a food's picture needs no call to this.
    public func images() async throws -> ImageSet {
        let (body, _): (DataEnvelope<ImageSet>, Bool) = try await get(["v2", "images"])
        return body.data
    }

    /// A session that keeps only the latest search and the latest autocomplete: use one per search screen.
    public func session() -> FoodSearchSession { FoodSearchSession(client: self) }

    // MARK: - Requests

    private func checkQuery(_ query: String) throws {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw FoodAPIError.invalidInput("empty query")
        }
        if query.unicodeScalars.count > Limits.queryLength {
            throw FoodAPIError.invalidInput("query longer than \(Limits.queryLength) characters")
        }
    }

    /// Sends a GET request, retrying what is safe to retry, and decodes the response. It reports whether the API
    /// answered from its cache.
    private func get<T: Decodable>(_ path: [String], query: [(String, String)] = []) async throws -> (T, Bool) {
        if let clientIP, !isIPAddress(clientIP) {
            throw FoodAPIError.invalidInput("client IP \"\(clientIP)\" is not an IPv4 or IPv6 address")
        }
        let request = try makeRequest(path, query: query)

        var attempt = 0
        while true {
            if Task.isCancelled { throw FoodAPIError.cancelled }
            do {
                let (data, response) = try await send(request)
                guard response.statusCode == 200 else {
                    throw FoodAPIError.from(
                        status: response.statusCode, message: errorMessage(data, status: response.statusCode),
                        retryAfter: parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After")))
                }
                do {
                    let value = try JSONDecoder().decode(T.self, from: data)
                    return (value, response.value(forHTTPHeaderField: "X-Cache") == "HIT")
                } catch {
                    throw FoodAPIError.server(
                        statusCode: 200, message: "invalid response: \(error)", retryAfter: nil)
                }
            } catch let error as FoodAPIError {
                guard error != .cancelled, !Task.isCancelled, attempt < maxRetries, error.isRetryable else {
                    throw Task.isCancelled ? FoodAPIError.cancelled : error
                }
                let delay = error.retryAfter ?? backoff(attempt: attempt)
                if delay > Limits.retryWait { throw error }  // Not worth waiting here; the caller can decide
                do {
                    try await wait(delay)
                } catch {
                    throw FoodAPIError.cancelled
                }
                attempt += 1
            }
        }
    }

    private func makeRequest(_ path: [String], query: [(String, String)]) throws -> URLRequest {
        // Each segment is escaped on its own, so the slashes of a barcode link stay inside one segment (%2F)
        var text = baseURL.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        for segment in path {
            text += "/" + escape(segment, allowed: .pathSegment)
        }
        if !query.isEmpty {
            text +=
                "?"
                + query.map { "\(escape($0.0, allowed: .queryValue))=\(escape($0.1, allowed: .queryValue))" }
                .joined(separator: "&")
        }
        guard let url = URL(string: text) else { throw FoodAPIError.invalidInput("invalid URL \(text)") }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let clientIP { request.setValue(clientIP, forHTTPHeaderField: "X-Client-IP") }
        return request
    }

    /// Sends one request, aborting it after the client's timeout. URLSession's own timeout is reset by every byte
    /// received, so a slow answer could take much longer; this bounds the whole attempt.
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let session = transport.session
        let timeout = timeout
        do {
            return try await withThrowingTaskGroup(of: (Data, HTTPURLResponse).self) { group in
                group.addTask {
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw FoodAPIError.server(statusCode: 0, message: "not an HTTP response", retryAfter: nil)
                    }
                    return (data, http)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1e9))
                    throw FoodAPIError.timeout
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } catch let error as FoodAPIError {
            throw error
        } catch let error as URLError {
            if Task.isCancelled || error.code == .cancelled { throw FoodAPIError.cancelled }
            if error.code == .timedOut { throw FoodAPIError.timeout }
            throw FoodAPIError.network(error)
        } catch is CancellationError {
            throw FoodAPIError.cancelled
        } catch {
            if Task.isCancelled { throw FoodAPIError.cancelled }
            throw FoodAPIError.network(URLError(.unknown, userInfo: [NSUnderlyingErrorKey: error]))
        }
    }

    /// The wait before retry attempt+1 when the API didn't say: 0.5 s, 1 s, … with jitter.
    private func backoff(attempt: Int) -> TimeInterval {
        let base = 0.5 * Double(1 << min(attempt, 10))
        return base / 2 + Double.random(in: 0...(base / 2))
    }
}

/// Owns the URLSession the client and its `withClientIP` copies share, and closes it when the last one goes.
private final class Transport: Sendable {
    let session: URLSession
    let owned: Bool

    init(session: URLSession, owned: Bool) {
        self.session = session
        self.owned = owned
    }

    deinit {
        if owned { session.finishTasksAndInvalidate() }
    }
}

/// Limits the API enforces, checked before sending.
private enum Limits {
    static let queryLength = 200
    static let page = 1000
    static let limit = 50
    static let suggestions = 20
    /// The longest Retry-After the client waits for itself; a longer one is thrown to the caller.
    static let retryWait: TimeInterval = 10
}

private struct DataEnvelope<T: Decodable>: Decodable {
    let data: T
}

private struct ListEnvelope<T: Decodable, Meta: Decodable>: Decodable {
    let data: [T]?
    let meta: Meta?
}

private struct SearchMeta: Decodable {
    let query: String?
    let page: Int?
    let limit: Int?
    let total: Int?
    let source: String?
    let region: String?
}

private struct AutocompleteMeta: Decodable {
    let query: String?
    let limit: Int?
    let total: Int?
}

private func errorMessage(_ data: Data, status: Int) -> String {
    struct Body: Decodable { let message: String? }
    if let message = (try? JSONDecoder().decode(Body.self, from: data))?.message, !message.isEmpty {
        return message
    }
    return HTTPURLResponse.localizedString(forStatusCode: status)
}

/// Reads a Retry-After header: seconds, or an HTTP date.
func parseRetryAfter(_ value: String?, now: Date = Date()) -> TimeInterval? {
    guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
    if let seconds = Int(value), seconds >= 0 { return TimeInterval(seconds) }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    guard let date = formatter.date(from: value) else { return nil }
    return max(date.timeIntervalSince(now), 0)
}

func isIPAddress(_ text: String) -> Bool {
    var v4 = in_addr()
    var v6 = in6_addr()
    return text.withCString { inet_pton(AF_INET, $0, &v4) == 1 || inet_pton(AF_INET6, $0, &v6) == 1 }
}

private extension CharacterSet {
    /// Unreserved characters plus those a path segment may hold as they are; "/" is escaped.
    static let pathSegment = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~!$&'()*+=:@")
    /// Only unreserved characters, so "+", "&" and "=" in a query reach the API as typed.
    static let queryValue = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}

private func escape(_ text: String, allowed: CharacterSet) -> String {
    text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
}
