package io.studio93.foodapi

import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import mockwebserver3.Dispatcher
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import mockwebserver3.SocketEffect
import okhttp3.OkHttpClient
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

private val Json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }

const val FOOD_JSON = """{"id":"01a163d2-bfdc-7912-878d-4020b11915ab","name":"Cola","brand":null,"type":"generic","barcodes":[],
 "servings":[{"description":"100 g","measurement":"g","metric_amount":100,"metric_unit":"g","units":100,
   "nutrients":{"calories":37,"protein":0,"sugar":0.5,"fiber":null,"cnf_409":0.01}},
  {"description":"1 fl oz","measurement":"fl oz","metric_amount":29.57,"metric_unit":"ml","units":1,"generic":true,
   "nutrients":{"calories":10.94}}],
 "source":{"provider":"CNF","id":"2920"},"ingredients":null,"category":"Beverages","something_new":{"a":1},
 "attributes":{"alternate_names":"pop, soda, soft drink"},"nutrient_flags":{"sugar":"upper_bound","fat":"something_new"}}"""

fun withImage(image: String) = FOOD_JSON.replaceFirst("\"nutrient_flags\"", "\"image\":$image,\"nutrient_flags\"")

fun json(body: String, status: Int = 200, vararg headers: Pair<String, String>): MockResponse =
    MockResponse.Builder().code(status).addHeader("Content-Type", "application/json").body(body)
        .apply { headers.forEach { (k, v) -> addHeader(k, v) } }.build()

/** Answers every request with [answer], by request. */
fun dispatch(answer: (RecordedRequest) -> MockResponse) = object : Dispatcher() {
    override fun dispatch(request: RecordedRequest) = answer(request)
}

val stall: MockResponse = MockResponse.Builder().onResponseStart(SocketEffect.Stall).build()

class FoodApiClientTest {
    private lateinit var server: MockWebServer
    private val waits = mutableListOf<Duration>()

    @BeforeTest
    fun start() {
        server = MockWebServer()
        server.start()
    }

    @AfterTest
    fun stop() = server.close()

    /** A client for the test server that records the waits between retries instead of sleeping. */
    private fun client(timeout: Duration = 5.seconds, maxRetries: Int = 2, http: OkHttpClient? = null) =
        FoodApiClient(
            apiKey = "test-key",
            baseUrl = server.url("/").toString(),
            httpClient = http,
            timeout = timeout,
            maxRetries = maxRetries,
            userAgent = "my-app/1.0",
        ).withWait { waits += it }

    private fun take(): RecordedRequest = assertNotNull(server.takeRequest(1, java.util.concurrent.TimeUnit.SECONDS))

    @Test
    fun `search sends the query and key and parses the page`() = runBlocking {
        server.enqueue(
            json(
                """{"data":[$FOOD_JSON],"meta":{"query":"cola zero","page":2,"limit":5,"total":11,"source":"catalog"}}""",
                200, "X-Cache" to "HIT",
            ),
        )
        val page = client().search("Cola  Zero", page = 2, limit = 5)

        val req = take()
        assertEquals("/v2/foods/search", req.url.encodedPath)
        assertEquals("Cola  Zero", req.url.queryParameter("q"))
        assertEquals("2", req.url.queryParameter("page"))
        assertEquals("5", req.url.queryParameter("limit"))
        assertEquals("Bearer test-key", req.headers["Authorization"])
        assertEquals("my-app/1.0 studio93-food-api-kotlin/$SDK_VERSION", req.headers["User-Agent"])
        assertEquals("gzip", req.headers["Accept-Encoding"], "OkHttp asks for gzip and unpacks it")
        assertNull(req.headers["X-Client-IP"])

        assertEquals("cola zero", page.query)
        assertEquals(2, page.page)
        assertEquals(11L, page.total)
        assertEquals("catalog", page.source)
        assertTrue(page.cached)
        assertNull(page.region, "no country ranked first")
        assertNull(page.brand, "the query names no brand")

        val food = page.foods.single()
        assertEquals(FoodType.GENERIC, food.type)
        assertEquals(listOf(false, true), food.servings.map { it.generic })
        assertEquals("1 fl oz", food.servings[1].description)
        assertEquals(29.57, food.servings[1].metricAmount)
        val n = food.servings.first().nutrients
        assertEquals(37.0, n.calories)
        assertEquals(37.0, n[Nutrients.CALORIES])
        assertNull(n.fiber, "unknown values are null")
        assertTrue(n.values.containsKey("fiber"))
        assertEquals(0.01, n["cnf_409"])
        assertEquals(NutrientFlag.UPPER_BOUND, food.flag("sugar"))
        assertEquals(NutrientFlag.UNKNOWN, food.flag("fat"), "flags newer than the SDK still parse")
        assertNull(food.flag("protein"))
        assertEquals(listOf("pop", "soda", "soft drink"), food.alternateNames)
        assertEquals(FoodSource("CNF", "2920"), food.source)
        assertNull(food.ingredients)
        assertEquals("Beverages", food.category)
        assertNull(food.image, "answers from before images still parse")
    }

    @Test
    fun `search reports the country and the brand that ranked first`() = runBlocking {
        server.enqueue(
            json("""{"data":[],"meta":{"query":"coke","page":0,"limit":20,"total":0,"source":"catalog","region":"CA","brand":"Coca-Cola"}}"""),
        )
        val page = client().search("coke")
        assertEquals("CA", page.region)
        assertEquals("Coca-Cola", page.brand)
        assertEquals("0", take().url.queryParameter("page"))
    }

    @Test
    fun `foods carry their image`() = runBlocking {
        server.dispatcher = dispatch { r ->
            json(
                when (r.url.encodedPath) {
                    "/v2/foods/cheddar" ->
                        """{"data":${withImage("""{"key":"dairy/cheddar","url":"https://images.example.com/dairy/cheddar.jpg","match":"food"}""")}}"""
                    "/v2/foods/barcode/3017624010701" ->
                        """{"data":${withImage("""{"key":"generic/plate","url":"https://images.example.com/generic/plate.jpg","match":"fallback"}""")}}"""
                    else ->
                        """{"data":${withImage("""{"key":"dairy/cheese","url":"https://images.example.com/dairy/cheese.jpg","match":"something_new"}""")}}"""
                },
            )
        }
        val client = client()

        val image = assertNotNull(client.food("cheddar").image)
        assertEquals(FoodImage("dairy/cheddar", "https://images.example.com/dairy/cheddar.jpg", ImageMatch.FOOD), image)
        assertFalse(image.isFallback)

        assertTrue(assertNotNull(client.foodByBarcode("3017624010701").image).isFallback)

        val newer = assertNotNull(client.food("gouda").image)
        assertEquals(ImageMatch.UNKNOWN, newer.match, "matches newer than the SDK still parse")
        assertFalse(newer.isFallback)
    }

    @Test
    fun `the image set parses`() = runBlocking {
        server.enqueue(
            json(
                """{"data":{"version":1,"updated":"2026-11-17","fallback":"generic/plate",
 "groups":[{"key":"dairy","label":"Milk and dairy"}],
 "images":[{"key":"dairy/milk","label":"Milk","tier":"category","group":"dairy","category":"dairy/milk","url":"https://images.example.com/dairy/milk.jpg"},
  {"key":"dairy/milk-whole","label":"Whole milk","tier":"variant","group":"dairy","category":"dairy/milk","parent":"dairy/milk","url":"https://images.example.com/dairy/milk-whole.jpg"},
  {"key":"dairy/milk-oat","label":"Oat milk","tier":"something_new","group":"dairy","category":"dairy/milk","url":"https://images.example.com/dairy/milk-oat.jpg"}]}}""",
            ),
        )
        val set = client().images()

        val req = take()
        assertEquals("/v2/images", req.url.encodedPath)
        assertEquals("Bearer test-key", req.headers["Authorization"])
        assertEquals(1, set.version)
        assertEquals("2026-11-17", set.updated)
        assertEquals("generic/plate", set.fallback)
        assertEquals(ImageGroup("dairy", "Milk and dairy"), set.groups.single())
        assertEquals(3, set.images.size)

        val milk = assertNotNull(set.image("dairy/milk"))
        assertEquals(ImageTier.CATEGORY, milk.tier)
        assertNull(milk.parent)
        assertEquals("https://images.example.com/dairy/milk.jpg", milk.url)

        assertEquals(
            ImageEntry(
                key = "dairy/milk-whole", label = "Whole milk", tier = ImageTier.VARIANT, group = "dairy",
                category = "dairy/milk", parent = "dairy/milk", url = "https://images.example.com/dairy/milk-whole.jpg",
            ),
            set.image("dairy/milk-whole"),
        )
        assertEquals(ImageTier.UNKNOWN, set.image("dairy/milk-oat")?.tier, "tiers newer than the SDK still parse")
        assertNull(set.image("dairy/yak-butter"))
    }

    @Test
    fun `empty results are empty lists`() = runBlocking {
        server.dispatcher = dispatch { json("""{"data":null,"meta":{"total":0}}""") }
        val client = client()
        assertEquals(emptyList(), client.search("xqzw").foods)
        assertEquals(emptyList(), client.autocomplete("xq").suggestions)
        server.dispatcher = dispatch { json("""{"data":{"version":1,"groups":null}}""") }
        assertEquals(emptyList(), client.images().groups)
    }

    @Test
    fun `autocomplete sends the query and limit`() = runBlocking {
        server.enqueue(
            json("""{"data":[{"id":"a1","name":"Chicken breast","brand":null},{"id":"b2","name":"Chick peas","brand":"Acme"}],"meta":{"query":"chick","limit":5,"total":312}}"""),
        )
        val result = client().autocomplete("chick", limit = 5)
        val req = take()
        assertEquals("/v2/foods/autocomplete", req.url.encodedPath)
        assertEquals("chick", req.url.queryParameter("q"))
        assertEquals("5", req.url.queryParameter("limit"))
        assertEquals(listOf(Suggestion("a1", "Chicken breast"), Suggestion("b2", "Chick peas", "Acme")), result.suggestions)
        assertEquals(312L, result.total)
        assertFalse(result.cached)
    }

    @Test
    fun `food by id and barcode use their paths`() = runBlocking {
        server.dispatcher = dispatch { json("""{"data":$FOOD_JSON}""") }
        val client = client()
        assertEquals("Cola", client.food(" 01a163d2-bfdc-7912-878d-4020b11915ab ").name)
        assertEquals("/v2/foods/01a163d2-bfdc-7912-878d-4020b11915ab", take().url.encodedPath)
        client.foodByBarcode("(01)03017624010701")
        assertEquals("/v2/foods/barcode/(01)03017624010701", take().url.encodedPath)
    }

    @Test
    fun `barcode links are escaped into the path`() = runBlocking {
        server.enqueue(json("""{"data":$FOOD_JSON}"""))
        client().foodByBarcode(" https://id.gs1.org/01/03017624010701 ")
        assertEquals("/v2/foods/barcode/https:%2F%2Fid.gs1.org%2F01%2F03017624010701", take().target)
    }

    @Test
    fun `error statuses become typed exceptions with the API's message`() = runBlocking {
        val expected = mapOf(
            400 to FoodApiBadRequest::class,
            401 to FoodApiUnauthorized::class,
            403 to FoodApiForbidden::class,
            404 to FoodApiNotFound::class,
            429 to FoodApiRateLimited::class,
            503 to FoodApiUnavailable::class,
            500 to FoodApiServerError::class,
            502 to FoodApiServerError::class,
        )
        for ((status, type) in expected) {
            server.enqueue(json("""{"message":"explained","data":{}}""", status))
            val e = assertFailsWith<FoodApiHttpException> { client(maxRetries = 0).food("x") }
            assertEquals(type, e::class, "status $status")
            assertEquals(status, e.statusCode)
            assertEquals("explained", e.message)
        }
        server.enqueue(MockResponse.Builder().code(500).body("<html>oops</html>").build())
        assertEquals("HTTP 500", assertFailsWith<FoodApiServerError> { client(maxRetries = 0).food("x") }.message)
    }

    @Test
    fun `an unreadable answer is a server error`() = runBlocking {
        server.enqueue(json("""{"data":{"name":"no id"}}"""))
        val e = assertFailsWith<FoodApiServerError> { client().food("x") }
        assertEquals(200, e.statusCode)
        assertEquals(1, server.requestCount, "not retried")
    }

    @Test
    fun `retries honour Retry-After`() = runBlocking {
        server.enqueue(json("""{"message":"search is busy, please retry in a few seconds"}""", 503, "Retry-After" to "2"))
        server.enqueue(json("""{"data":$FOOD_JSON}"""))
        assertEquals("Cola", client().food("x").name)
        assertEquals(2, server.requestCount)
        assertEquals(listOf(2.seconds), waits)
    }

    @Test
    fun `Retry-After can be an HTTP date`() = runBlocking {
        val format = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("GMT")
        val inFiveSeconds = format.format(Date(System.currentTimeMillis() + 5_000))
        server.enqueue(json("""{"message":"busy"}""", 429, "Retry-After" to inFiveSeconds))
        server.enqueue(json("""{"data":$FOOD_JSON}"""))
        client().food("x")
        val wait = waits.single()
        assertTrue(wait > 3.seconds && wait <= 5.seconds, "waited $wait")
    }

    @Test
    fun `gives up after the retries, backing off without Retry-After`() = runBlocking {
        server.dispatcher = dispatch { json("""{"message":"slow down"}""", 429) }
        val e = assertFailsWith<FoodApiRateLimited> { client().food("x") }
        assertNull(e.retryAfter)
        assertEquals(3, server.requestCount)
        assertEquals(2, waits.size)
        assertTrue(waits[0] in 250.milliseconds..500.milliseconds && waits[1] in 500.milliseconds..1.seconds, "$waits")
    }

    @Test
    fun `502 and 504 are retried, 500 isn't`() = runBlocking {
        server.enqueue(json("{}", 502))
        server.enqueue(json("{}", 504))
        server.enqueue(json("""{"data":$FOOD_JSON}"""))
        client().food("x")
        assertEquals(3, server.requestCount)

        server.enqueue(json("{}", 500))
        assertFailsWith<FoodApiServerError> { client().food("x") }
        assertEquals(4, server.requestCount)
    }

    @Test
    fun `a long Retry-After is left to the caller`() = runBlocking {
        server.dispatcher = dispatch { json("""{"message":"busy"}""", 503, "Retry-After" to "60") }
        val e = assertFailsWith<FoodApiUnavailable> { client().food("x") }
        assertEquals(60.seconds, e.retryAfter)
        assertEquals(1, server.requestCount)
        assertTrue(waits.isEmpty())
    }

    @Test
    fun `not found and other client errors are not retried`() = runBlocking {
        server.dispatcher = dispatch { json("""{"message":"food not found"}""", 404) }
        assertFailsWith<FoodApiNotFound> { client().food("x") }
        assertEquals(1, server.requestCount)
    }

    @Test
    fun `network errors are retried, then reported`() = runBlocking {
        val url = server.url("/").toString()
        server.close() // Nothing listens there any more
        val client = FoodApiClient("test-key", baseUrl = url, maxRetries = 1).withWait { waits += it }
        assertFailsWith<FoodApiNetworkException> { client.food("x") }
        assertEquals(1, waits.size)
    }

    @Test
    fun `a slow attempt is cut off at the timeout`() = runBlocking {
        server.dispatcher = dispatch { stall }
        val e = assertFailsWith<FoodApiTimeoutException> { client(timeout = 200.milliseconds, maxRetries = 0).food("x") }
        assertTrue(e.message.contains("200 ms"), e.message)
    }

    @Test
    fun `cancelling the coroutine cancels the HTTP call`() = runBlocking {
        server.dispatcher = dispatch { stall }
        val http = OkHttpClient()
        val job = launch { client(http = http).search("apple") }
        withTimeout(2_000) { while (http.dispatcher.runningCallsCount() == 0) delay(10) }
        job.cancel()
        withTimeout(2_000) {
            job.join()
            while (http.dispatcher.runningCallsCount() > 0) delay(10) // The call was cancelled, not left running
        }
        assertTrue(job.isCancelled)
    }

    @Test
    fun `cancelling the coroutine cancels the wait before a retry`() = runBlocking {
        server.dispatcher = dispatch { json("""{"message":"busy"}""", 503, "Retry-After" to "5") }
        val client = FoodApiClient("test-key", baseUrl = server.url("/").toString()) // Waits for real
        val job = launch { client.food("x") }
        delay(300)
        withTimeout(1_000) { job.cancelAndJoin() }
        assertEquals(1, server.requestCount, "no retry after cancelling")
    }

    @Test
    fun `a session keeps only the latest search`() = runBlocking {
        server.dispatcher = dispatch { r ->
            val q = r.url.queryParameter("q")
            if (q == "app") {
                stall // Slow, and replaced
            } else {
                json("""{"data":[$FOOD_JSON],"meta":{"query":"$q","page":0,"limit":20,"total":1,"source":"catalog"}}""")
            }
        }
        val session = client().session()
        val first = async(start = CoroutineStart.UNDISPATCHED) {
            try {
                session.search("app").query
            } catch (e: FoodApiCancelledException) {
                "cancelled"
            }
        }
        withTimeout(2_000) { while (server.requestCount == 0) delay(10) }
        val second = async { session.search("apple") }
        withTimeout(3_000) {
            assertEquals("cancelled", first.await())
            assertEquals("apple", second.await().query)
        }
    }

    @Test
    fun `a session cancels everything on close, and the caller goes on`() = runBlocking {
        server.dispatcher = dispatch { stall }
        val session = client().session()
        val search = async(start = CoroutineStart.UNDISPATCHED) { runCatching { session.search("apple") } }
        val suggest = async(start = CoroutineStart.UNDISPATCHED) { runCatching { session.autocomplete("app") } }
        withTimeout(2_000) { while (server.requestCount < 2) delay(10) }
        session.cancel()
        withTimeout(2_000) {
            assertIs<FoodApiCancelledException>(search.await().exceptionOrNull())
            assertIs<FoodApiCancelledException>(suggest.await().exceptionOrNull())
        }
        // The session still works afterwards
        server.dispatcher = dispatch { json("""{"data":[],"meta":{"query":"pear","total":0}}""") }
        assertEquals("pear", session.search("pear").query)
    }

    @Test
    fun `invalid input sends nothing`() = runBlocking {
        val client = client()
        assertFailsWith<FoodApiInvalidInput> { client.search("  ") }
        assertFailsWith<FoodApiInvalidInput> { client.search("a".repeat(201)) }
        server.enqueue(json("""{"data":[],"meta":{"total":0}}"""))
        client.search("🍎".repeat(200)) // 200 characters are fine, however many UTF-16 units they take
        assertFailsWith<FoodApiInvalidInput> { client.search("apple", limit = 51) }
        assertFailsWith<FoodApiInvalidInput> { client.search("apple", limit = 0) }
        assertFailsWith<FoodApiInvalidInput> { client.search("apple", page = 1001) }
        assertFailsWith<FoodApiInvalidInput> { client.autocomplete("app", limit = 21) }
        assertFailsWith<FoodApiInvalidInput> { client.food(" ") }
        assertFailsWith<FoodApiInvalidInput> { client.foodByBarcode("") }
        assertFailsWith<FoodApiInvalidInput> { client.nutrientStats("") }
        assertEquals(1, server.requestCount, "only the 200-character search was sent")
    }

    @Test
    fun `nutrient stats and the nutrient list parse`() = runBlocking {
        server.dispatcher = dispatch { r ->
            when (r.url.encodedPath) {
                "/v2/foods/abc/nutrient-stats" -> json(
                    """{"data":{"id":"abc","per":"100 g","nutrients":{"protein":{"data_points":12,"min":3.12,"derivation":"A","derivation_description":"Analytical"}}}}""",
                )
                "/v2/nutrients" -> json(
                    """{"data":{"nutrients":[{"key":"calories","name":"Energy","unit":"kcal","group":"energy","core":true}],"other":[{"key":"usda_1018","name":"Ash","unit":"g","source":"USDA"}]}}""",
                )
                else -> json("{}", 404)
            }
        }
        val client = client()
        val stats = client.nutrientStats("abc")
        assertEquals("abc", stats.foodId)
        assertEquals("100 g", stats.per)
        val protein = assertNotNull(stats.nutrients["protein"])
        assertEquals(12, protein.dataPoints)
        assertEquals(3.12, protein.min)
        assertNull(protein.max)
        assertEquals("Analytical", protein.derivationDescription)
        val list = client.nutrients()
        assertEquals(NutrientDefinition("calories", "Energy", "kcal", "energy", core = true), list.nutrients.single())
        assertEquals(OtherNutrient("usda_1018", "Ash", "g", "USDA"), list.other.single())
    }

    @Test
    fun `a client for a user sends the user's address`() = runBlocking {
        server.dispatcher = dispatch {
            json("""{"data":[],"meta":{"query":"cheddar","page":0,"limit":20,"total":0,"source":"catalog","region":"GB"}}""")
        }
        val client = client()
        assertEquals("GB", client.withClientIP(" 81.2.69.160 ").search("cheddar").region)
        assertEquals("81.2.69.160", take().headers["X-Client-IP"])
        client.search("cheddar")
        assertNull(take().headers["X-Client-IP"], "the shared client sends none")
        client.withClientIP("2001:db8::1").autocomplete("ched")
        assertEquals("2001:db8::1", take().headers["X-Client-IP"])
        assertEquals("2001:db8::1", client.withClientIP("2001:db8::1").clientIP)

        // An invalid address fails before a request
        assertFailsWith<FoodApiInvalidInput> { client.withClientIP("81.2.69").food("x") }
        assertFailsWith<FoodApiInvalidInput> { client.withClientIP("example.com").food("x") }
        assertEquals(3, server.requestCount)
    }

    @Test
    fun `IP address literals`() {
        val valid = listOf(
            "81.2.69.160", "0.0.0.0", "255.255.255.255", "::", "::1", "1::", "2001:db8::1", "fe80::1%eth0",
            "2001:0db8:0000:0000:0000:ff00:0042:8329", "::ffff:192.0.2.1", "64:ff9b::192.0.2.33", "1:2:3:4:5:6:7::",
        )
        val invalid = listOf(
            "", "81.2.69", "256.1.1.1", "01.2.3.4", "1.2.3.4.5", "example.com", "localhost", ":::", "1:::2",
            "1::2::3", "2001:db8:1", "1:2:3:4:5:6:7:8:9", "12345::", "g::1", "fe80::1%", "::ffff:1.2.3",
            "1:2:3:4:5:6:7:8::", " 1.2.3.4",
        )
        valid.forEach { assertTrue(isIPAddress(it), it) }
        invalid.forEach { assertFalse(isIPAddress(it), it) }
    }

    @Test
    fun `the version matches the build`() {
        assertEquals(System.getProperty("foodapi.version"), SDK_VERSION)
        assertEquals("https://api.studio93.io", DEFAULT_BASE_URL)
    }

    @Test
    fun `models serialize for an app's own cache`() {
        val food = Json.decodeFromString(Food.serializer(), withImage("""{"key":"k","url":"u","match":"variant"}"""))
        assertEquals(food, Json.decodeFromString(Food.serializer(), Json.encodeToString(Food.serializer(), food)))
    }
}
