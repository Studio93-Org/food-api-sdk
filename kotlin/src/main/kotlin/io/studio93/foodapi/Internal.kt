package io.studio93.foodapi

import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.Serializable
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Response
import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/** An answer read in full on OkHttp's thread. */
internal class RawResponse(val code: Int, val body: String, val retryAfter: Duration?, val cached: Boolean)

/**
 * Sends the call, suspending until it answers, and hands the answer to [read] on OkHttp's thread, so neither the
 * body nor the JSON is read on the caller's (perhaps Android's main) thread. Cancelling the coroutine cancels the
 * HTTP call. An IOException is the network's; anything [read] throws is passed on as it is.
 */
internal suspend fun <T> Call.await(read: (RawResponse) -> T): T = suspendCancellableCoroutine { cont ->
    cont.invokeOnCancellation { cancel() }
    enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) {
            cont.resumeWithException(e) // Ignored once the coroutine is cancelled
        }

        override fun onResponse(call: Call, response: Response) {
            val result = runCatching {
                val raw = response.use {
                    RawResponse(it.code, it.body.string(), parseRetryAfter(it), it.header("X-Cache") == "HIT")
                }
                read(raw)
            }
            result.fold({ cont.resume(it) }, { cont.resumeWithException(it) })
        }
    })
}

/** Reads a Retry-After header: seconds, or an HTTP date. */
internal fun parseRetryAfter(response: Response): Duration? {
    val value = response.header("Retry-After")?.trim() ?: return null
    value.toLongOrNull()?.let { return if (it >= 0) it.seconds else null }
    val date = response.headers.getDate("Retry-After") ?: return null
    return (date.time - System.currentTimeMillis()).coerceAtLeast(0).milliseconds
}

@Serializable
internal class SearchResponse(val data: List<Food>? = null, val meta: SearchMeta = SearchMeta())

@Serializable
internal class SearchMeta(
    val query: String? = null,
    val page: Int? = null,
    val limit: Int? = null,
    val total: Long = 0,
    val source: String? = null,
    val region: String? = null,
    val brand: String? = null,
)

@Serializable
internal class AutocompleteResponse(val data: List<Suggestion>? = null, val meta: AutocompleteMeta = AutocompleteMeta())

@Serializable
internal class AutocompleteMeta(val query: String? = null, val limit: Int? = null, val total: Long = 0)

@Serializable
internal class DataResponse<T>(val data: T)

@Serializable
internal class ErrorBody(val message: String? = null)

/**
 * Whether [s] is an IPv4 or IPv6 address literal (an IPv6 one may carry a zone, "fe80::1%eth0"). It never looks a
 * name up, unlike InetAddress.getByName.
 */
internal fun isIPAddress(s: String): Boolean = isIPv4(s) || isIPv6(s)

private fun isIPv4(s: String): Boolean {
    val parts = s.split('.')
    return parts.size == 4 && parts.all { p ->
        p.length in 1..3 && p.all { it in '0'..'9' } && (p.length == 1 || p[0] != '0') && p.toInt() <= 255
    }
}

private fun isIPv6(address: String): Boolean {
    val zone = address.indexOf('%')
    if (zone == address.length - 1) return false // An empty zone
    var s = if (zone >= 0) address.substring(0, zone) else address
    val lastColon = s.lastIndexOf(':')
    if (lastColon < 0) return false
    val tail = s.substring(lastColon + 1)
    if (tail.contains('.')) { // An embedded IPv4 address ("::ffff:1.2.3.4") stands for two groups
        if (!isIPv4(tail)) return false
        s = s.substring(0, lastColon + 1) + "0:0"
    }
    val halves = s.split("::")
    fun groups(h: String): List<String>? =
        if (h.isEmpty()) emptyList() else h.split(':').takeIf { it.all(::isHexGroup) }
    return when (halves.size) {
        1 -> groups(s)?.size == 8
        2 -> {
            val before = groups(halves[0]) ?: return false
            val after = groups(halves[1]) ?: return false
            before.size + after.size <= 7
        }
        else -> false // "::" at most once
    }
}

private fun isHexGroup(g: String): Boolean =
    g.length in 1..4 && g.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }
