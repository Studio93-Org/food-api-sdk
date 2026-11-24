import { Food, ImageSet, type AutocompleteResult, type NutrientList, type NutrientStats, type SearchPage } from './models.js';
import { FoodSearchSession } from './session.js';
/** The SDK version, sent in the User-Agent header. */
export declare const sdkVersion = "0.4.0";
/** The Food API. */
export declare const defaultBaseUrl = "https://api.studio93.io";
/** A fetch function: the global one, or yours (for example a mock in tests). */
export type FetchFunction = (input: string, init: RequestInit) => Promise<Response>;
/** Settings of a FoodApiClient. */
export interface FoodApiClientOptions {
    /** Your v2 API key, issued by Studio93. */
    apiKey: string;
    /** Another server, such as a test server. Default https://api.studio93.io. */
    baseUrl?: string | URL;
    /** Limits each attempt, in milliseconds (default 15000). Give a call an overall deadline with its `signal`. */
    timeout?: number;
    /**
     * How often a request that failed for a temporary reason (network error, timeout, 429, 502, 503, 504) is sent
     * again (default 2; 0 turns retries off).
     */
    maxRetries?: number;
    /** Your app's name and version, put before the SDK's in the User-Agent header ("my-app/1.4"). */
    userAgent?: string;
    /** Your own fetch, for example a mock in tests. Default: the global fetch. */
    fetch?: FetchFunction;
}
/** Options every call takes. */
export interface CallOptions {
    /** Cancels the call: the request is aborted and the call rejects with FoodApiCancelledError. */
    signal?: AbortSignal;
    /**
     * Server use only: the IP address of the user your server is calling for, sent as `X-Client-IP`. Search then
     * ranks for the user's country instead of your server's (with a key that has regional ranking), and usage by
     * country counts the user's. Apps calling from the user's own device (browsers, React Native) leave it out: the
     * API already sees the user's address. An address that isn't IPv4 or IPv6 throws FoodApiInvalidInput.
     */
    clientIp?: string;
}
/** Options of a search. */
export interface SearchOptions extends CallOptions {
    /** Zero-based, 0 to 1000 (default 0). */
    page?: number;
    /** Results per page, 1 to 50 (default 20). */
    limit?: number;
}
/** Options of an autocomplete. */
export interface AutocompleteOptions extends CallOptions {
    /** Suggestions, 1 to 20 (default 8). */
    limit?: number;
}
/**
 * Calls the Food API's v2 endpoints.
 *
 * Create one for the whole app and share it. Requests go through the platform's fetch (the browser's, React
 * Native's, or Node's), which keeps connections open between requests and accepts gzip, so only the first request
 * pays for the TCP and TLS handshake.
 */
export declare class FoodApiClient {
    #private;
    /** Limits each attempt, in milliseconds. */
    readonly timeout: number;
    /** How often a request that failed for a temporary reason is sent again. */
    readonly maxRetries: number;
    constructor(options: FoodApiClientOptions);
    /**
     * Finds foods matching a query, typos and all ("chiken brest"). A query nothing matches returns an empty page,
     * not an error.
     */
    search(query: string, options?: SearchOptions): Promise<SearchPage>;
    /**
     * Suggests foods for what has been typed so far; the last word matches as a prefix ("chick" finds Chicken). It
     * never asks outside providers, so it is fast enough for every keystroke.
     */
    autocomplete(query: string, options?: AutocompleteOptions): Promise<AutocompleteResult>;
    /** The food with a catalog ID. An unknown ID rejects with FoodApiNotFound. */
    food(id: string, options?: CallOptions): Promise<Food>;
    /**
     * The food for a barcode: 6 to 14 digits, or what a scanner read from a 2D code (a GS1 code such as
     * "(01)03017624010701", or a GS1 Digital Link). A barcode no source knows rejects with FoodApiNotFound.
     */
    foodByBarcode(barcode: string, options?: CallOptions): Promise<Food>;
    /**
     * What a food's source says about each of its nutrient values: samples, spread and how each was obtained. Foods
     * whose source gives no such details have none.
     */
    nutrientStats(foodId: string, options?: CallOptions): Promise<NutrientStats>;
    /** Every nutrient key a serving can have, with its name and unit. */
    nutrients(options?: CallOptions): Promise<NutrientList>;
    /**
     * Every food image, with its label, group and URL, for apps that bundle or prefetch them. Foods carry their own
     * `image`, so showing a food's picture needs no call to this.
     */
    images(options?: CallOptions): Promise<ImageSet>;
    /** A session that keeps only the latest search and the latest autocomplete: use one per search screen. */
    session(): FoodSearchSession;
}
