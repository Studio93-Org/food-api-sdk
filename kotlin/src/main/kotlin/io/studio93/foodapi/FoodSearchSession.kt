package io.studio93.foodapi

import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicReference

/**
 * Keeps only the latest search and the latest autocomplete for one search screen.
 *
 * Starting a search cancels the search still in flight, and starting an autocomplete cancels the autocomplete still
 * in flight: the replaced call throws [FoodApiCancelledException], a [kotlinx.coroutines.CancellationException], so a
 * coroutine that doesn't catch it just ends. A slow answer for "app" can never replace the results for "apple", and
 * abandoned requests stop using the network.
 *
 * ```kotlin
 * val session = foodApi.session()
 *
 * fun onQueryChanged(text: String) {
 *     scope.launch {
 *         val page = session.search(text) // A newer search ends this coroutine here
 *         showResults(page)
 *     }
 * }
 * ```
 *
 * Get one with [FoodApiClient.session]. It is safe to use from several coroutines and threads.
 */
public class FoodSearchSession internal constructor(private val client: FoodApiClient) {
    private val search = AtomicReference<Job?>(null)
    private val autocomplete = AtomicReference<Job?>(null)

    /** Searches, cancelling this session's previous search. Loading the next page of the same query is a search too. */
    public suspend fun search(query: String, page: Int = 0, limit: Int = 20): SearchPage =
        latest(search) { client.search(query, page, limit) }

    /** Suggests foods, cancelling this session's previous autocomplete. */
    public suspend fun autocomplete(query: String, limit: Int = 8): AutocompleteResult =
        latest(autocomplete) { client.autocomplete(query, limit) }

    /** Cancels whatever is in flight, for example when the screen closes. */
    public fun cancel() {
        search.get()?.cancel(FoodApiCancelledException("the search session was cancelled"))
        autocomplete.get()?.cancel(FoodApiCancelledException("the search session was cancelled"))
    }

    /**
     * Runs [call] in a job of its own, a child of the caller's, after cancelling the job of the previous call in
     * [slot]. Cancelling that job cancels the HTTP request (or the wait before a retry) and makes this call throw.
     */
    private suspend fun <T> latest(slot: AtomicReference<Job?>, call: suspend () -> T): T {
        val job = Job(currentCoroutineContext()[Job])
        slot.getAndSet(job)?.cancel(FoodApiCancelledException("replaced by a newer call"))
        try {
            return withContext(job) { call() }
        } finally {
            job.complete() // Otherwise the caller's job would wait for it forever
            slot.compareAndSet(job, null)
        }
    }
}
