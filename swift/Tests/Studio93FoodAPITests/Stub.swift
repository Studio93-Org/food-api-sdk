import Foundation

@testable import Studio93FoodAPI

/// A response for the stub transport to give.
struct StubResponse {
    var status: Int = 200
    var body: String
    var headers: [String: String] = [:]
}

/// Answers requests in place of the network. Each test server gets its own host, so tests can run in parallel.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> StubResponse

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    private var loading: Task<Void, Never>?

    static func register(host: String, handler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        handlers[host] = handler
    }

    private static func handler(for request: URLRequest) -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return request.url?.host.flatMap { handlers[$0] }
    }

    override class func canInit(with request: URLRequest) -> Bool { handler(for: request) != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler(for: request) else { return }
        let request = request
        loading = Task {
            do {
                let stub = try await handler(request)
                if Task.isCancelled { return }
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"].merging(stub.headers) { $1 })!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                if Task.isCancelled { return }
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() { loading?.cancel() }
}

/// A fake API: the requests it received, and a client pointed at it.
final class FakeAPI: @unchecked Sendable {
    private let lock = NSLock()
    private var received: [URLRequest] = []
    private var waited: [TimeInterval] = []
    let host = "\(UUID().uuidString.lowercased()).example.com"

    init(_ handler: @escaping @Sendable (URLRequest) async throws -> StubResponse) {
        StubProtocol.register(host: host) { [weak self] request in
            self?.record(request)
            return try await handler(request)
        }
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return received
    }

    /// The waits between retries the client asked for.
    var waits: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return waited
    }

    private func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        received.append(request)
    }

    private func recordWait(_ seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        waited.append(seconds)
    }

    /// A client for this fake API. Waits between retries are recorded and skipped, unless `realWaits`.
    func client(
        timeout: TimeInterval = 5, maxRetries: Int = 2, userAgent: String? = "my-app/1.0", realWaits: Bool = false
    ) -> FoodAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return FoodAPIClient(
            apiKey: "test-key", baseURL: URL(string: "https://\(host)")!, timeout: timeout, maxRetries: maxRetries,
            userAgent: userAgent, urlSession: URLSession(configuration: configuration),
            wait: { [weak self] seconds in
                self?.recordWait(seconds)
                if realWaits { try await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }
                try Task.checkCancellation()
            })
    }

    /// Waits until the fake API has received `count` requests.
    func waitForRequests(_ count: Int) async {
        for _ in 0..<500 where requests.count < count {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

func json(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> StubResponse {
    StubResponse(status: status, body: body, headers: headers)
}

/// Waits until the task is cancelled (the request was aborted), then throws.
func hang() async throws -> StubResponse {
    try await Task.sleep(nanoseconds: 60_000_000_000)
    throw CancellationError()
}

extension URLRequest {
    /// The query parameters, decoded.
    var queryItems: [String: String] {
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }) { $1 }
    }

    /// The path as sent, still percent-encoded.
    var encodedPath: String { URLComponents(url: url!, resolvingAgainstBaseURL: false)!.percentEncodedPath }
}

let foodJSON = """
    {"id":"01a163d2-bfdc-7912-878d-4020b11915ab","name":"Cola","brand":null,"type":"generic","barcodes":[],
     "servings":[{"description":"100 g","measurement":"g","metric_amount":100,"metric_unit":"g","units":100,
       "nutrients":{"calories":37,"protein":0,"sugar":0.5,"fiber":null,"cnf_409":0.01}},
      {"description":"1 fl oz","measurement":"fl oz","metric_amount":29.57,"metric_unit":"ml","units":1,"generic":true,
       "nutrients":{"calories":10.94}}],
     "source":{"provider":"CNF","id":"2920"},"ingredients":null,"category":"Beverages",
     "attributes":{"alternate_names":"pop, soda, soft drink"},"nutrient_flags":{"sugar":"upper_bound","fat":"something_new"}}
    """

func foodJSON(image: String) -> String {
    foodJSON.replacingOccurrences(of: "\"nutrient_flags\"", with: "\"image\":\(image),\"nutrient_flags\"")
}
