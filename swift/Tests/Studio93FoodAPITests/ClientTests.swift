import Foundation
import Testing

@testable import Studio93FoodAPI

@Suite struct ClientTests {
    @Test func searchSendsTheQueryAndKeyAndParsesThePage() async throws {
        let api = FakeAPI { _ in
            json(
                #"{"data":[\#(foodJSON)],"meta":{"query":"cola zero","page":2,"limit":5,"total":11,"source":"catalog"}}"#,
                headers: ["X-Cache": "HIT"])
        }
        let page = try await api.client().search("Cola  Zero", page: 2, limit: 5)

        let request = try #require(api.requests.first)
        #expect(api.requests.count == 1)
        #expect(request.encodedPath == "/v2/foods/search")
        #expect(request.queryItems == ["q": "Cola  Zero", "page": "2", "limit": "5"])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(
            request.value(forHTTPHeaderField: "User-Agent")
                == "my-app/1.0 studio93-food-api-swift/\(FoodAPIClient.sdkVersion)")
        #expect(request.value(forHTTPHeaderField: "X-Client-IP") == nil)
        #expect(page.query == "cola zero")
        #expect(page.page == 2 && page.limit == 5 && page.total == 11)
        #expect(page.source == "catalog")
        #expect(page.cached)
        #expect(page.region == nil, "no country ranked first")

        let food = try #require(page.foods.first)
        #expect(food.id == "01a163d2-bfdc-7912-878d-4020b11915ab")
        #expect(food.type == .generic)
        #expect(food.brand == nil)
        #expect(food.category == "Beverages")
        #expect(food.source == FoodSource(provider: "CNF", id: "2920"))
        #expect(food.servings.map(\.generic) == [false, true])
        #expect(food.servings[0].metricAmount == 100)
        #expect(food.servings[1].metricUnit == "ml")
        let n = food.servings[0].nutrients
        #expect(n.calories == 37)
        #expect(n.protein == 0)
        #expect(n.fiber == nil, "unknown values are nil")
        #expect(n.values.keys.contains("fiber"), "an unknown core value still has its key")
        #expect(n["cnf_409"] == 0.01)
        #expect(n["magnesium"] == nil)
        #expect(food.flag(NutrientKey.sugar) == .upperBound)
        #expect(food.flag("fat") == .unknown("something_new"), "flags newer than the SDK still parse")
        #expect(food.flag(NutrientKey.protein) == nil)
        #expect(food.alternateNames == ["pop", "soda", "soft drink"])
        #expect(food.image == nil, "answers from before images still parse")
    }

    @Test func searchDefaultsAndRegion() async throws {
        let api = FakeAPI { _ in
            json(
                #"{"data":[],"meta":{"query":"cheddar","page":0,"limit":20,"total":0,"source":"catalog","region":"CA"}}"#
            )
        }
        let page = try await api.client(userAgent: nil).search("cheddar")
        #expect(page.region == "CA")
        #expect(page.foods.isEmpty)
        #expect(!page.cached)
        let request = try #require(api.requests.first)
        #expect(request.queryItems == ["q": "cheddar", "page": "0", "limit": "20"])
        #expect(
            request.value(forHTTPHeaderField: "User-Agent") == "studio93-food-api-swift/\(FoodAPIClient.sdkVersion)")
    }

    @Test func queriesAreEscaped() async throws {
        let api = FakeAPI { _ in json(#"{"data":[],"meta":{}}"#) }
        _ = try await api.client().search("m&m's + 1=1 crème")
        let request = try #require(api.requests.first)
        #expect(request.queryItems["q"] == "m&m's + 1=1 crème")
        #expect(request.url!.absoluteString.contains("q=m%26m%27s%20%2B%201%3D1%20cr%C3%A8me"))
    }

    @Test func autocomplete() async throws {
        let api = FakeAPI { _ in
            json(
                #"{"data":[{"id":"a1","name":"Chicken breast","brand":null},{"id":"b2","name":"Chick peas","brand":"Acme"}],"meta":{"query":"chick","limit":5,"total":42}}"#
            )
        }
        let result = try await api.client().autocomplete("chick", limit: 5)
        let request = try #require(api.requests.first)
        #expect(request.encodedPath == "/v2/foods/autocomplete")
        #expect(request.queryItems == ["q": "chick", "limit": "5"])
        #expect(
            result.suggestions == [
                Suggestion(id: "a1", name: "Chicken breast"), Suggestion(id: "b2", name: "Chick peas", brand: "Acme"),
            ])
        #expect(result.query == "chick" && result.limit == 5 && result.total == 42 && !result.cached)
    }

    @Test func autocompleteDefaultLimit() async throws {
        let api = FakeAPI { _ in json(#"{"data":null,"meta":{"total":0}}"#) }
        let result = try await api.client().autocomplete("xq")
        #expect(api.requests.first?.queryItems["limit"] == "8")
        #expect(result.suggestions.isEmpty)
        #expect(result.query == "xq")
    }

    @Test func emptyResultsAreEmptyLists() async throws {
        let api = FakeAPI { _ in json(#"{"data":null,"meta":{"total":0}}"#) }
        let client = api.client()
        #expect(try await client.search("xqzw").foods.isEmpty)
        #expect(try await client.autocomplete("xq").suggestions.isEmpty)
    }

    @Test func foodByID() async throws {
        let api = FakeAPI { _ in json(#"{"data":\#(foodJSON)}"#) }
        let food = try await api.client().food(" 01a163d2-bfdc-7912-878d-4020b11915ab ")
        #expect(food.name == "Cola")
        #expect(api.requests.first?.encodedPath == "/v2/foods/01a163d2-bfdc-7912-878d-4020b11915ab")
    }

    @Test(arguments: [
        ("3017624010701", "/v2/foods/barcode/3017624010701"),
        (" https://id.gs1.org/01/03017624010701 ", "/v2/foods/barcode/https:%2F%2Fid.gs1.org%2F01%2F03017624010701"),
        ("(01)03017624010701", "/v2/foods/barcode/(01)03017624010701"),
        ("]d201030176240107011", "/v2/foods/barcode/%5Dd201030176240107011"),
    ])
    func barcodesArePassedAsGiven(barcode: String, path: String) async throws {
        let api = FakeAPI { _ in json(#"{"data":\#(foodJSON)}"#) }
        _ = try await api.client().foodByBarcode(barcode)
        #expect(api.requests.first?.encodedPath == path)
    }

    @Test func foodsCarryTheirImage() async throws {
        let api = FakeAPI { request in
            switch request.url!.path {
            case "/v2/foods/cheddar":
                json(
                    #"{"data":\#(foodJSON(image: #"{"key":"dairy/cheddar","url":"https://images.example.com/dairy/cheddar.jpg","match":"food"}"#))}"#
                )
            case "/v2/foods/barcode/3017624010701":
                json(
                    #"{"data":\#(foodJSON(image: #"{"key":"generic/plate","url":"https://images.example.com/generic/plate.jpg","match":"fallback"}"#))}"#
                )
            case "/v2/foods/broken":
                json(#"{"data":\#(foodJSON(image: #"{"key":"dairy/cheese","match":"food"}"#))}"#)
            default:
                json(
                    #"{"data":\#(foodJSON(image: #"{"key":"dairy/cheese","url":"https://images.example.com/dairy/cheese.jpg","match":"something_new"}"#))}"#
                )
            }
        }
        let client = api.client()

        let image = try #require(try await client.food("cheddar").image)
        #expect(image.key == "dairy/cheddar")
        #expect(image.url == URL(string: "https://images.example.com/dairy/cheddar.jpg"))
        #expect(image.match == .food)
        #expect(!image.isFallback)

        #expect(try await client.foodByBarcode("3017624010701").image?.isFallback == true)

        let newer = try #require(try await client.food("gouda").image)
        #expect(newer.match == .unknown("something_new"), "matches newer than the SDK still parse")
        #expect(!newer.isFallback)

        let broken = try await client.food("broken")
        #expect(broken.image == nil, "an image without a URL is left out, the food still parses")
        #expect(broken.name == "Cola")
    }

    @Test func theImageSetParses() async throws {
        let api = FakeAPI { _ in
            json(
                #"""
                {"data":{"version":1,"updated":"2026-11-17","fallback":"generic/plate",
                 "groups":[{"key":"dairy","label":"Milk and dairy"}],
                 "images":[{"key":"dairy/milk","label":"Milk","tier":"category","group":"dairy","category":"dairy/milk","url":"https://images.example.com/dairy/milk.jpg"},
                  {"key":"dairy/milk-whole","label":"Whole milk","tier":"variant","group":"dairy","category":"dairy/milk","parent":"dairy/milk","url":"https://images.example.com/dairy/milk-whole.jpg"},
                  {"key":"dairy/milk-oat","label":"Oat milk","tier":"something_new","group":"dairy","category":"dairy/milk","url":"https://images.example.com/dairy/milk-oat.jpg"}]}}
                """#)
        }
        let set = try await api.client().images()

        #expect(api.requests.first?.encodedPath == "/v2/images")
        #expect(api.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(set.version == 1)
        #expect(set.updated == "2026-11-17")
        #expect(set.fallback == "generic/plate")
        #expect(set.groups == [ImageGroup(key: "dairy", label: "Milk and dairy")])
        #expect(set.images.count == 3)

        let milk = try #require(set.image("dairy/milk"))
        #expect(milk.tier == .category)
        #expect(milk.parent == nil)
        #expect(milk.url == URL(string: "https://images.example.com/dairy/milk.jpg"))

        let whole = try #require(set.image("dairy/milk-whole"))
        #expect(whole.tier == .variant)
        #expect(whole.label == "Whole milk")
        #expect(whole.group == "dairy")
        #expect(whole.category == "dairy/milk")
        #expect(whole.parent == "dairy/milk")

        #expect(set.image("dairy/milk-oat")?.tier == .unknown("something_new"), "tiers newer than the SDK still parse")
        #expect(set.image("dairy/yak-butter") == nil)
    }

    @Test func anEmptyImageSetHasEmptyLists() async throws {
        let api = FakeAPI { _ in json(#"{"data":{"version":1,"groups":null}}"#) }
        let set = try await api.client().images()
        #expect(set.groups.isEmpty && set.images.isEmpty && set.fallback.isEmpty)
    }

    @Test func nutrientStatsAndTheNutrientList() async throws {
        let api = FakeAPI { request in
            switch request.url!.path {
            case "/v2/foods/abc/nutrient-stats":
                json(
                    #"{"data":{"id":"abc","per":"100 g","nutrients":{"protein":{"data_points":12,"min":3.12,"std_error":0.2,"derivation":"A","derivation_description":"Analytical","updated":"2019-04-01"}}}}"#
                )
            default:
                json(
                    #"{"data":{"nutrients":[{"key":"calories","name":"Energy","unit":"kcal","group":"energy","core":true}],"other":[{"key":"usda_1018","name":"Ash","unit":"g","source":"USDA"}]}}"#
                )
            }
        }
        let client = api.client()
        let stats = try await client.nutrientStats("abc")
        #expect(stats.foodID == "abc" && stats.per == "100 g")
        let protein = try #require(stats.nutrients["protein"])
        #expect(protein.dataPoints == 12 && protein.min == 3.12 && protein.stdError == 0.2 && protein.max == nil)
        #expect(protein.derivation == "A" && protein.derivationDescription == "Analytical")
        #expect(protein.updated == "2019-04-01")

        let list = try await client.nutrients()
        #expect(api.requests.last?.encodedPath == "/v2/nutrients")
        #expect(
            list.nutrients == [
                NutrientDefinition(key: "calories", name: "Energy", unit: "kcal", group: "energy", core: true)
            ])
        #expect(list.other == [OtherNutrient(key: "usda_1018", name: "Ash", unit: "g", source: "USDA")])
    }

    @Test func modelsRoundTripThroughJSON() throws {
        let food = try JSONDecoder().decode(
            Food.self,
            from: Data(
                foodJSON(
                    image:
                        #"{"key":"drinks/cola","url":"https://images.example.com/drinks/cola.jpg","match":"variant"}"#
                ).utf8))
        let again = try JSONDecoder().decode(Food.self, from: try JSONEncoder().encode(food))
        #expect(again == food)
        #expect(again.servings[0].nutrients.values.keys.contains("fiber"))
    }

    @Test func invalidInputSendsNothing() async throws {
        let api = FakeAPI { _ in json("{}") }
        let client = api.client()
        await #expect(throws: FoodAPIError.invalidInput("empty query")) { try await client.search("  ") }
        await #expect(throws: FoodAPIError.self) { try await client.search(String(repeating: "a", count: 201)) }
        await #expect(throws: FoodAPIError.self) { try await client.search("apple", limit: 51) }
        await #expect(throws: FoodAPIError.self) { try await client.search("apple", limit: 0) }
        await #expect(throws: FoodAPIError.self) { try await client.search("apple", page: 1001) }
        await #expect(throws: FoodAPIError.self) { try await client.autocomplete("app", limit: 21) }
        await #expect(throws: FoodAPIError.invalidInput("empty barcode")) { try await client.foodByBarcode(" ") }
        await #expect(throws: FoodAPIError.invalidInput("empty food id")) { try await client.food("") }
        await #expect(throws: FoodAPIError.invalidInput("empty food id")) { try await client.nutrientStats("") }
        _ = try await client.search(String(repeating: "é", count: 200)).foods  // 200 characters is fine
        #expect(api.requests.count == 1)
    }

    @Test(arguments: [
        (400, FoodAPIError.badRequest(message: "explained")),
        (401, .unauthorized(message: "explained")),
        (403, .forbidden(message: "explained")),
        (404, .notFound(message: "explained")),
        (429, .rateLimited(message: "explained", retryAfter: nil)),
        (503, .unavailable(message: "explained", retryAfter: nil)),
        (500, .server(statusCode: 500, message: "explained", retryAfter: nil)),
        (502, .server(statusCode: 502, message: "explained", retryAfter: nil)),
    ])
    func errorStatusesBecomeTypedErrors(status: Int, expected: FoodAPIError) async throws {
        let api = FakeAPI { _ in json(#"{"message":"explained","data":{}}"#, status: status) }
        let error = await #expect(throws: FoodAPIError.self) { try await api.client(maxRetries: 0).food("x") }
        #expect(error == expected)
        #expect(error?.statusCode == status)
        #expect(error?.message == "explained")
        if status != 404, case .notFound = error {
            Issue.record("\(status) matched notFound")
        }
    }

    @Test func anErrorWithoutAMessageUsesTheStatus() async throws {
        let api = FakeAPI { _ in StubResponse(status: 500, body: "<html>oops</html>") }
        let error = await #expect(throws: FoodAPIError.self) { try await api.client(maxRetries: 0).food("x") }
        #expect(error == .server(statusCode: 500, message: "internal server error", retryAfter: nil))
    }

    @Test func anUnreadableAnswerIsAServerError() async throws {
        let api = FakeAPI { _ in json("not json") }
        let error = await #expect(throws: FoodAPIError.self) { try await api.client().food("x") }
        #expect(error?.statusCode == 200)
        #expect(api.requests.count == 1, "not retried")
    }

    @Test func retriesHonourRetryAfter() async throws {
        let api = FakeAPI { [counter = Counter()] _ in
            counter.next() == 1
                ? json(
                    #"{"message":"search is busy, please retry in a few seconds"}"#, status: 503,
                    headers: ["Retry-After": "2"])
                : json(#"{"data":\#(foodJSON)}"#)
        }
        let food = try await api.client().food("x")
        #expect(food.name == "Cola")
        #expect(api.requests.count == 2)
        #expect(api.waits == [2], "one retry after the 2 s the API asked for")
    }

    @Test(arguments: [429, 502, 503, 504])
    func temporaryStatusesAreRetriedThenReported(status: Int) async throws {
        let api = FakeAPI { _ in json("{}", status: status) }
        let error = await #expect(throws: FoodAPIError.self) { try await api.client().food("x") }
        #expect(error?.statusCode == status)
        #expect(api.requests.count == 3)
        #expect(api.waits.count == 2)
        #expect(api.waits.allSatisfy { $0 > 0 && $0 <= 1 }, "backing off without Retry-After: \(api.waits)")
    }

    @Test func aLongRetryAfterIsLeftToTheCaller() async throws {
        let api = FakeAPI { _ in json(#"{"message":"busy"}"#, status: 503, headers: ["Retry-After": "60"]) }
        let error = await #expect(throws: FoodAPIError.self) { try await api.client().food("x") }
        #expect(error == .unavailable(message: "busy", retryAfter: 60))
        #expect(error?.retryAfter == 60)
        #expect(api.requests.count == 1)
        #expect(api.waits.isEmpty)
    }

    @Test func clientErrorsAreNotRetried() async throws {
        let api = FakeAPI { _ in json(#"{"message":"food not found"}"#, status: 404) }
        await #expect(throws: FoodAPIError.notFound(message: "food not found")) { try await api.client().food("x") }
        #expect(api.requests.count == 1)
    }

    @Test func networkErrorsAreRetriedThenReported() async throws {
        let api = FakeAPI { _ in throw URLError(.networkConnectionLost) }
        let error = await #expect(throws: FoodAPIError.self) { try await api.client(maxRetries: 1).food("x") }
        guard case .network(let urlError) = error else {
            Issue.record("error = \(String(describing: error))")
            return
        }
        #expect(urlError.code == .networkConnectionLost)
        #expect(error?.isOffline == true)
        #expect(api.requests.count == 2)
    }

    @Test func aSlowAttemptIsAbortedAtTheTimeout() async throws {
        let api = FakeAPI { _ in try await hang() }
        let start = Date()
        await #expect(throws: FoodAPIError.timeout) { try await api.client(timeout: 0.2, maxRetries: 0).food("x") }
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func timeoutsAreRetried() async throws {
        let api = FakeAPI { [counter = Counter()] _ in
            if counter.next() == 1 { return try await hang() }
            return json(#"{"data":\#(foodJSON)}"#)
        }
        #expect(try await api.client(timeout: 0.2).food("x").name == "Cola")
        #expect(api.requests.count == 2)
    }

    @Test func cancellingTheTaskCancelsTheRequest() async throws {
        let api = FakeAPI { _ in try await hang() }
        let client = api.client()
        let task = Task { try await client.search("apple") }
        await api.waitForRequests(1)
        task.cancel()
        let start = Date()
        await #expect(throws: FoodAPIError.cancelled) { try await task.value }
        #expect(Date().timeIntervalSince(start) < 3)
        #expect(api.requests.count == 1, "a cancelled call isn't retried")
    }

    @Test func cancellingTheTaskCancelsTheWaitBeforeARetry() async throws {
        let api = FakeAPI { _ in json(#"{"message":"busy"}"#, status: 503, headers: ["Retry-After": "5"]) }
        let client = api.client(realWaits: true)
        let task = Task { try await client.food("x") }
        await api.waitForRequests(1)
        try await Task.sleep(nanoseconds: 100_000_000)  // Into the 5 s wait
        task.cancel()
        let start = Date()
        await #expect(throws: FoodAPIError.cancelled) { try await task.value }
        #expect(Date().timeIntervalSince(start) < 3)
        #expect(api.requests.count == 1)
    }

    @Test func anAlreadyCancelledTaskSendsNothing() async throws {
        let api = FakeAPI { _ in json(#"{"data":\#(foodJSON)}"#) }
        let client = api.client()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.food("x")
        }
        await #expect(throws: FoodAPIError.cancelled) { try await task.value }
        #expect(api.requests.isEmpty)
    }

    @Test func aSessionKeepsOnlyTheLatestSearch() async throws {
        let api = FakeAPI { request in
            let q = request.queryItems["q"] ?? ""
            if q == "app" { return try await hang() }  // Slow, and superseded
            return json(
                #"{"data":[\#(foodJSON)],"meta":{"query":"\#(q)","page":0,"limit":20,"total":1,"source":"catalog"}}"#)
        }
        let session = api.client().session()
        let first = Task { try await session.search("app") }
        await api.waitForRequests(1)
        let second = try await session.search("apple")
        #expect(second.query == "apple")
        await #expect(throws: FoodAPIError.cancelled) { try await first.value }
    }

    @Test func aSessionKeepsSearchAndAutocompleteApart() async throws {
        let api = FakeAPI { request in
            if request.url!.path.hasSuffix("/search") { try await Task.sleep(nanoseconds: 200_000_000) }
            return request.url!.path.hasSuffix("/search")
                ? json(#"{"data":[],"meta":{"query":"apple"}}"#)
                : json(#"{"data":[],"meta":{"query":"app"}}"#)
        }
        let session = api.client().session()
        async let page = session.search("apple")
        async let suggestions = session.autocomplete("app")
        #expect(try await page.query == "apple")
        #expect(try await suggestions.query == "app")
    }

    @Test func aSessionCancelsEverythingOnCancel() async throws {
        let api = FakeAPI { _ in try await hang() }
        let session = api.client().session()
        let search = Task { try await session.search("apple") }
        let suggest = Task { try await session.autocomplete("app") }
        await api.waitForRequests(2)
        session.cancel()
        await #expect(throws: FoodAPIError.cancelled) { try await search.value }
        await #expect(throws: FoodAPIError.cancelled) { try await suggest.value }
    }

    @Test func cancellingTheCallerCancelsASessionSearch() async throws {
        let api = FakeAPI { _ in try await hang() }
        let session = api.client().session()
        let search = Task { try await session.search("apple") }
        await api.waitForRequests(1)
        search.cancel()
        await #expect(throws: FoodAPIError.cancelled) { try await search.value }
    }

    @Test func theClientIPIsSentForAServersUsers() async throws {
        let api = FakeAPI { _ in
            json(
                #"{"data":[],"meta":{"query":"cheddar","page":0,"limit":20,"total":0,"source":"catalog","region":"GB"}}"#
            )
        }
        let client = api.client()
        let page = try await client.withClientIP(" 81.2.69.160 ").search("cheddar")
        #expect(page.region == "GB")
        _ = try await client.search("cheddar")
        _ = try await client.withClientIP("2001:db8::1").autocomplete("ched")
        _ = try await client.withClientIP("").search("cheddar")
        #expect(
            api.requests.map { $0.value(forHTTPHeaderField: "X-Client-IP") } == [
                "81.2.69.160", nil, "2001:db8::1", nil,
            ])
        #expect(client.withClientIP("81.2.69.160").clientIP == "81.2.69.160")
        #expect(client.clientIP == nil, "the original client is unchanged")

        // An invalid address fails before a request
        await #expect(throws: FoodAPIError.self) { try await client.withClientIP("81.2.69").food("x") }
        await #expect(throws: FoodAPIError.self) { try await client.withClientIP("localhost").food("x") }
        #expect(api.requests.count == 4)
    }

    @Test func aSessionOfAClientIPClientSendsIt() async throws {
        let api = FakeAPI { _ in json(#"{"data":[],"meta":{}}"#) }
        _ = try await api.client().withClientIP("81.2.69.160").session().search("cheddar")
        #expect(api.requests.first?.value(forHTTPHeaderField: "X-Client-IP") == "81.2.69.160")
    }

    @Test func aBaseURLWithAPathKeepsIt() async throws {
        let api = FakeAPI { _ in json(#"{"data":\#(foodJSON)}"#) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let client = FoodAPIClient(
            apiKey: "k", baseURL: URL(string: "https://\(api.host)/proxy/")!,
            urlSession: URLSession(configuration: configuration))
        _ = try await client.food("x")
        #expect(api.requests.first?.encodedPath == "/proxy/v2/foods/x")
    }

    @Test func parseRetryAfterReadsSecondsAndDates() {
        #expect(parseRetryAfter("3") == 3)
        #expect(parseRetryAfter(" 0 ") == 0)
        #expect(parseRetryAfter(nil) == nil)
        #expect(parseRetryAfter("") == nil)
        #expect(parseRetryAfter("soon") == nil)
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        #expect(parseRetryAfter(formatter.string(from: now.addingTimeInterval(5)), now: now) == 5)
        #expect(parseRetryAfter(formatter.string(from: now.addingTimeInterval(-5)), now: now) == 0)
    }

    @Test func ipAddresses() {
        #expect(isIPAddress("81.2.69.160"))
        #expect(isIPAddress("2001:db8::1"))
        #expect(!isIPAddress("81.2.69"))
        #expect(!isIPAddress("example.com"))
        #expect(!isIPAddress(""))
    }

    @Test func errorsDescribeThemselves() {
        let error = FoodAPIError.notFound(message: "food not found")
        #expect(error.localizedDescription.contains("404"))
        #expect(error.localizedDescription.contains("food not found"))
        #expect(!error.isOffline)
        #expect(FoodAPIError.timeout.isOffline)
    }
}

/// Counts calls to a fake API's handler.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}
