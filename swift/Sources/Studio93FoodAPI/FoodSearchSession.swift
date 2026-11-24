import Foundation

/// Keeps only the latest search and the latest autocomplete for one search screen.
///
/// Starting a search cancels the search still in flight, and starting an autocomplete cancels the autocomplete
/// still in flight: their calls throw `FoodAPIError.cancelled`, which you can ignore. So a slow answer for "app" can
/// never replace the results for "apple", and abandoned requests stop using the network.
///
/// ```swift
/// let session = foodAPI.session()
///
/// func queryChanged(_ text: String) async {
///     do {
///         results = try await session.search(text).foods
///     } catch FoodAPIError.cancelled {
///         // The user typed on; a newer search is running
///     } catch {
///         showError(error)
///     }
/// }
/// ```
///
/// Cancelling the task that awaits a call cancels that call too.
public final class FoodSearchSession: @unchecked Sendable {
    // @unchecked: the mutable state is only touched under `lock`
    private let client: FoodAPIClient
    private let lock = NSLock()
    private var searchTask: Task<SearchPage, any Error>?
    private var autocompleteTask: Task<AutocompleteResult, any Error>?

    public init(client: FoodAPIClient) {
        self.client = client
    }

    /// Searches, cancelling this session's previous search. Loading the next page of the same query is a search too.
    public func search(_ query: String, page: Int = 0, limit: Int = 20) async throws -> SearchPage {
        let client = client
        let task = Task { try await client.search(query, page: page, limit: limit) }
        replace(\.searchTask, with: task)
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Suggests foods, cancelling this session's previous autocomplete.
    public func autocomplete(_ query: String, limit: Int = 8) async throws -> AutocompleteResult {
        let client = client
        let task = Task { try await client.autocomplete(query, limit: limit) }
        replace(\.autocompleteTask, with: task)
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Cancels whatever is in flight, for example when the screen closes.
    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        searchTask?.cancel()
        autocompleteTask?.cancel()
    }

    private func replace<T>(
        _ slot: ReferenceWritableKeyPath<FoodSearchSession, Task<T, any Error>?>, with task: Task<T, any Error>
    ) {
        lock.lock()
        defer { lock.unlock() }
        self[keyPath: slot]?.cancel()
        self[keyPath: slot] = task
    }
}
