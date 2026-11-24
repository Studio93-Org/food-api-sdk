import Foundation
import Studio93FoodAPI
import Testing

/// Calls the real API. It runs only with an API key:
///
///     FOOD_API_KEY=... swift test --scratch-path swift/.build --filter LiveTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FOOD_API_KEY"] != nil, "FOOD_API_KEY not set"))
struct LiveTests {
    @Test(.timeLimit(.minutes(1)))
    func liveAPI() async throws {
        let key = ProcessInfo.processInfo.environment["FOOD_API_KEY"] ?? ""
        let client = FoodAPIClient(apiKey: key, userAgent: "food-api-sdk-tests")

        let page = try await client.search("whole milk", page: 1, limit: 5)  // Page 1: catalog only
        let first = try #require(page.foods.first)
        #expect(first.servings.first?.nutrients.calories != nil)

        let food = try await client.food(first.id)
        #expect(food.id == first.id)
        #expect(food.image != nil)

        #expect(try await !client.autocomplete("chick", limit: 5).suggestions.isEmpty)
        #expect(try await !client.foodByBarcode("https://id.gs1.org/01/03017624010701").name.isEmpty)
        let unknown = await #expect(throws: FoodAPIError.self) {
            try await client.food("01a163d2-0000-7000-8000-000000000000")
        }
        #expect(unknown?.statusCode == 404)
        _ = try await client.nutrientStats(first.id)
        #expect(try await client.nutrients().nutrients.count >= 17)

        let images = try await client.images()
        #expect(!images.images.isEmpty)
        #expect(images.image(images.fallback) != nil)

        let badKey = FoodAPIClient(apiKey: "not-a-key")
        let error = await #expect(throws: FoodAPIError.self) { try await badKey.search("apple", page: 1) }
        #expect(error?.statusCode == 401)
    }
}
