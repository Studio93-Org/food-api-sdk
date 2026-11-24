/**
 * Keeps only the latest search and the latest autocomplete for one search screen.
 *
 * Starting a search cancels the search still in flight, and starting an autocomplete cancels the autocomplete
 * still in flight: their promises reject with FoodApiCancelledError, which you can ignore. So a slow answer for
 * "app" can never replace the results for "apple", and abandoned requests stop using the network.
 *
 * ```ts
 * const session = foodApi.session();
 * try {
 *   showResults(await session.search(text));
 * } catch (e) {
 *   if (e instanceof FoodApiCancelledError) return; // The user typed on; a newer search is running
 *   throw e;
 * }
 * ```
 */
export class FoodSearchSession {
    #client;
    #search = null;
    #autocomplete = null;
    constructor(client) {
        this.#client = client;
    }
    /** Searches, cancelling this session's previous search. Loading the next page of the same query is a search too. */
    search(query, options = {}) {
        this.#search?.abort();
        const controller = new AbortController();
        this.#search = controller;
        return this.#client.search(query, { ...options, signal: controller.signal });
    }
    /** Suggests foods, cancelling this session's previous autocomplete. */
    autocomplete(query, options = {}) {
        this.#autocomplete?.abort();
        const controller = new AbortController();
        this.#autocomplete = controller;
        return this.#client.autocomplete(query, { ...options, signal: controller.signal });
    }
    /** Cancels whatever is in flight, for example when the screen closes. */
    cancel() {
        this.#search?.abort();
        this.#autocomplete?.abort();
    }
}
