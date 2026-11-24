package io.studio93.foodapi

import kotlinx.coroutines.delay
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.Json
import okhttp3.ConnectionPool
import okhttp3.Dispatcher
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.Closeable
import java.io.IOException
import java.io.InterruptedIOException
import java.util.concurrent.TimeUnit
import kotlin.random.Random
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/** The SDK version, sent in the User-Agent header. */
public const val SDK_VERSION: String = "0.4.0"

/** The Food API. */
public const val DEFAULT_BASE_URL: String = "https://api.studio93.io"

// Limits the API enforces, checked before sending
private const val MAX_QUERY_LENGTH = 200
private const val MAX_PAGE = 1000
private const val MAX_LIMIT = 50
private const val MAX_SUGGESTIONS = 20

// The longest Retry-After the client waits for itself; a longer one is thrown to the caller
private val MAX_RETRY_WAIT = 10.seconds

private val json = Json {
    ignoreUnknownKeys = true // Fields newer than the SDK
    coerceInputValues = true // null for a field with a default
    explicitNulls = false
}

/**
 * Calls the Food API's v2 endpoints. Every call is a suspend function; cancelling the coroutine cancels the HTTP
 * request and any wait before a retry.
 *
 * Create one for the whole app (or server) and share it: it keeps connections open between requests (OkHttp, with
 * HTTP/2 and gzip), which saves a TCP and TLS handshake (one or two network round trips) on every request after the
 * first. It is safe for concurrent use.
 *
 * [apiKey] is issued by Studio93. [timeout] limits each attempt; [maxRetries] is how often a request that failed for
 * a temporary reason (network error, timeout, 429, 502, 503, 504) is sent again. Pass [httpClient] to share your
 * app's OkHttpClient (its connections, dispatcher and interceptors); the [FoodApiClient] then doesn't close it.
 */
public class FoodApiClient private constructor(
    private val apiKey: String,
    private val baseUrl: HttpUrl,
    private val http: OkHttpClient,
    private val ownsHttp: Boolean,
    /** The time limit of each attempt. */
    public val timeout: Duration,
    /** How often a request that failed for a temporary reason is sent again. */
    public val maxRetries: Int,
    private val userAgent: String,
    /** The end user's IP address sent with every call, set with [withClientIP]; null for apps on the user's device. */
    public val clientIP: String?,
    private val wait: suspend (Duration) -> Unit,
) : Closeable {
    public constructor(
        apiKey: String,
        baseUrl: String = DEFAULT_BASE_URL,
        httpClient: OkHttpClient? = null,
        timeout: Duration = 15.seconds,
        maxRetries: Int = 2,
        userAgent: String? = null,
    ) : this(
        apiKey = apiKey,
        baseUrl = baseUrl.trimEnd('/').toHttpUrl(),
        // Not callTimeout(java.time.Duration): java.time needs Android 8 (API 26)
        http = (httpClient?.newBuilder() ?: defaultHttpClient())
            .callTimeout(timeout.inWholeMilliseconds, TimeUnit.MILLISECONDS)
            .build(),
        ownsHttp = httpClient == null,
        timeout = timeout,
        maxRetries = maxRetries.coerceAtLeast(0),
        userAgent = listOfNotNull(userAgent, "studio93-food-api-kotlin/$SDK_VERSION").joinToString(" "),
        clientIP = null,
        wait = { delay(it) },
    )

    /**
     * Finds foods matching [query], typos and all ("chiken brest"). [page] is zero-based (0 to 1000), [limit] is 1 to
     * 50. A query nothing matches returns an empty page, not an error.
     */
    public suspend fun search(query: String, page: Int = 0, limit: Int = 20): SearchPage {
        checkQuery(query)
        if (page !in 0..MAX_PAGE) throw FoodApiInvalidInput("page must be between 0 and $MAX_PAGE")
        if (limit !in 1..MAX_LIMIT) throw FoodApiInvalidInput("limit must be between 1 and $MAX_LIMIT")
        val (res, cached) = get(
            listOf("v2", "foods", "search"),
            mapOf("q" to query, "page" to "$page", "limit" to "$limit"),
            SearchResponse.serializer(),
        )
        val meta = res.meta
        return SearchPage(
            foods = res.data.orEmpty(),
            query = meta.query ?: query,
            page = meta.page ?: page,
            limit = meta.limit ?: limit,
            total = meta.total,
            source = meta.source ?: "catalog",
            region = meta.region?.takeIf { it.isNotBlank() },
            brand = meta.brand?.takeIf { it.isNotBlank() },
            cached = cached,
        )
    }

    /**
     * Suggests foods for what has been typed so far; the last word matches as a prefix ("chick" finds Chicken).
     * [limit] is 1 to 20. It never asks outside providers, so it is fast enough for every keystroke.
     */
    public suspend fun autocomplete(query: String, limit: Int = 8): AutocompleteResult {
        checkQuery(query)
        if (limit !in 1..MAX_SUGGESTIONS) throw FoodApiInvalidInput("limit must be between 1 and $MAX_SUGGESTIONS")
        val (res, cached) = get(
            listOf("v2", "foods", "autocomplete"),
            mapOf("q" to query, "limit" to "$limit"),
            AutocompleteResponse.serializer(),
        )
        return AutocompleteResult(
            suggestions = res.data.orEmpty(),
            query = res.meta.query ?: query,
            limit = res.meta.limit ?: limit,
            total = res.meta.total,
            cached = cached,
        )
    }

    /** The food with a catalog ID. An unknown ID throws [FoodApiNotFound]. */
    public suspend fun food(id: String): Food {
        if (id.isBlank()) throw FoodApiInvalidInput("empty food id")
        return get(listOf("v2", "foods", id.trim()), emptyMap(), DataResponse.serializer(Food.serializer())).first.data
    }

    /**
     * The food for a barcode: 6 to 14 digits, or what a scanner read from a 2D code (a GS1 code such as
     * "(01)03017624010701", or a GS1 Digital Link). A barcode no source knows throws [FoodApiNotFound].
     */
    public suspend fun foodByBarcode(barcode: String): Food {
        if (barcode.isBlank()) throw FoodApiInvalidInput("empty barcode")
        val path = listOf("v2", "foods", "barcode", barcode.trim())
        return get(path, emptyMap(), DataResponse.serializer(Food.serializer())).first.data
    }

    /**
     * What a food's source says about each of its nutrient values: samples, spread and how each was obtained. Foods
     * whose source gives no such details have none.
     */
    public suspend fun nutrientStats(foodId: String): NutrientStats {
        if (foodId.isBlank()) throw FoodApiInvalidInput("empty food id")
        val path = listOf("v2", "foods", foodId.trim(), "nutrient-stats")
        return get(path, emptyMap(), DataResponse.serializer(NutrientStats.serializer())).first.data
    }

    /** Every nutrient key a serving can have, with its name and unit. */
    public suspend fun nutrients(): NutrientList =
        get(listOf("v2", "nutrients"), emptyMap(), DataResponse.serializer(NutrientList.serializer())).first.data

    /**
     * Every food image, with its label, group and URL, for apps that bundle or prefetch them. Foods carry their own
     * [Food.image], so showing a food's picture needs no call to this.
     */
    public suspend fun images(): ImageSet =
        get(listOf("v2", "images"), emptyMap(), DataResponse.serializer(ImageSet.serializer())).first.data

    /** A session that keeps only the latest search and the latest autocomplete: use one per search screen. */
    public fun session(): FoodSearchSession = FoodSearchSession(this)

    /**
     * A client for calls made for one of your users, carrying that user's IP address; it shares this client's
     * connections. When your server calls the API for its users, use one per user request: search ranks for the
     * user's country rather than your server's (with a key that has regional ranking), and usage by country counts
     * the user's. Apps that call the API from the user's own device don't need it.
     *
     * The address is sent as the `X-Client-IP` header. One that isn't IPv4 or IPv6 makes each call throw
     * [FoodApiInvalidInput] without a request. Rate limits still apply to your server's own address.
     */
    public fun withClientIP(ip: String): FoodApiClient =
        copy(clientIP = ip.trim().ifEmpty { null }, ownsHttp = false)

    /** Closes the connections, if the client created its OkHttpClient itself. */
    override fun close() {
        if (!ownsHttp) return
        http.dispatcher.executorService.shutdown()
        http.connectionPool.evictAll()
    }

    /** For tests: records the waits between retries instead of sleeping. */
    internal fun withWait(wait: suspend (Duration) -> Unit): FoodApiClient = copy(wait = wait)

    private fun copy(
        clientIP: String? = this.clientIP,
        ownsHttp: Boolean = this.ownsHttp,
        wait: suspend (Duration) -> Unit = this.wait,
    ) = FoodApiClient(apiKey, baseUrl, http, ownsHttp, timeout, maxRetries, userAgent, clientIP, wait)

    private fun checkQuery(query: String) {
        if (query.isBlank()) throw FoodApiInvalidInput("empty query")
        if (query.codePointCount(0, query.length) > MAX_QUERY_LENGTH) {
            throw FoodApiInvalidInput("query longer than $MAX_QUERY_LENGTH characters")
        }
    }

    /** Sends a GET request, retrying what is safe to retry. Returns the answer and whether the API had it cached. */
    private suspend fun <T> get(
        path: List<String>,
        query: Map<String, String>,
        deserializer: DeserializationStrategy<T>,
    ): Pair<T, Boolean> {
        if (clientIP != null && !isIPAddress(clientIP)) {
            throw FoodApiInvalidInput("client IP \"$clientIP\" is not an IPv4 or IPv6 address")
        }
        val url = baseUrl.newBuilder().apply {
            path.forEach { addPathSegment(it) } // Escapes "/" in a barcode link as %2F
            query.forEach { (k, v) -> addQueryParameter(k, v) }
        }.build()
        val request = Request.Builder().url(url)
            .header("Authorization", "Bearer $apiKey")
            .header("Accept", "application/json")
            .header("User-Agent", userAgent)
            .apply { if (clientIP != null) header("X-Client-IP", clientIP) }
            .build()

        var attempt = 0
        while (true) {
            try {
                return once(request, deserializer)
            } catch (e: FoodApiException) {
                if (attempt >= maxRetries || !retryable(e)) throw e
                val delay = (e as? FoodApiHttpException)?.retryAfter ?: backoff(attempt)
                if (delay > MAX_RETRY_WAIT) throw e // Not worth waiting here; the caller can decide
                wait(delay) // Cancellable
                attempt++
            }
        }
    }

    /** Sends one request. */
    private suspend fun <T> once(request: Request, deserializer: DeserializationStrategy<T>): Pair<T, Boolean> = try {
        http.newCall(request).await { res -> read(res, deserializer) }
    } catch (e: InterruptedIOException) { // OkHttp's call timeout, or a socket timeout
        throw FoodApiTimeoutException("no answer within ${timeout.inWholeMilliseconds} ms", e)
    } catch (e: IOException) {
        throw FoodApiNetworkException(e.message ?: e.toString(), e)
    }

    /** Turns an answer into its value, or the exception for its status. Runs on OkHttp's thread. */
    private fun <T> read(res: RawResponse, deserializer: DeserializationStrategy<T>): Pair<T, Boolean> {
        if (res.code != 200) {
            throw FoodApiHttpException.fromStatus(res.code, errorMessage(res), res.retryAfter)
        }
        val value = try {
            json.decodeFromString(deserializer, res.body)
        } catch (e: IllegalArgumentException) { // SerializationException and its subclasses
            throw FoodApiServerError(200, "invalid response: ${e.message}")
        }
        return value to res.cached
    }

    private fun errorMessage(res: RawResponse): String = try {
        json.decodeFromString(ErrorBody.serializer(), res.body).message
    } catch (e: IllegalArgumentException) {
        null // Not JSON
    } ?: "HTTP ${res.code}"

    private fun retryable(e: FoodApiException): Boolean = when (e) {
        is FoodApiNetworkException, is FoodApiTimeoutException, is FoodApiRateLimited, is FoodApiUnavailable -> true
        is FoodApiServerError -> e.statusCode == 502 || e.statusCode == 504
        else -> false
    }

    /** The wait before retry attempt+1 when the API didn't say: 0.5 s, 1 s, … with jitter. */
    private fun backoff(attempt: Int): Duration {
        val ms = 500L shl attempt
        return (ms / 2 + Random.nextLong(ms / 2 + 1)).milliseconds
    }

    private companion object {
        fun defaultHttpClient(): OkHttpClient.Builder = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            // OkHttp allows 5 requests at once per host by default: too few for a server or a busy screen
            .dispatcher(Dispatcher().apply { maxRequests = 64; maxRequestsPerHost = 32 })
            .connectionPool(ConnectionPool(16, 5, TimeUnit.MINUTES))
    }
}
