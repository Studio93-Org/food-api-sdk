import {
  FoodApiCancelledError,
  FoodApiError,
  FoodApiHttpError,
  FoodApiInvalidInput,
  FoodApiNetworkError,
  FoodApiServerError,
  FoodApiTimeoutError,
} from './errors.js';
import { isIpAddress } from './ip.js';
import { isObject, list, num, obj, strOrNull } from './json.js';
import {
  Food,
  ImageSet,
  nutrientListFromJson,
  nutrientStatsFromJson,
  suggestionFromJson,
  type AutocompleteResult,
  type NutrientList,
  type NutrientStats,
  type SearchPage,
} from './models.js';
import { FoodSearchSession } from './session.js';

/** The SDK version, sent in the User-Agent header. */
export const sdkVersion = '0.4.0';

/** The Food API. */
export const defaultBaseUrl = 'https://api.studio93.io';

// Limits the API enforces, checked before sending
const maxQueryLength = 200;
const maxPage = 1000;
const maxLimit = 50;
const maxSuggestions = 20;

// The longest Retry-After the client waits for itself; a longer one is thrown to the caller
const maxRetryWait = 10_000;

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

interface ApiResponse {
  body: Record<string, unknown>;
  cached: boolean;
}

/**
 * Calls the Food API's v2 endpoints.
 *
 * Create one for the whole app and share it. Requests go through the platform's fetch (the browser's, React
 * Native's, or Node's), which keeps connections open between requests and accepts gzip, so only the first request
 * pays for the TCP and TLS handshake.
 */
export class FoodApiClient {
  readonly #apiKey: string;
  readonly #baseUrl: string;
  readonly #fetch: FetchFunction;
  readonly #userAgent: string;
  /** Limits each attempt, in milliseconds. */
  readonly timeout: number;
  /** How often a request that failed for a temporary reason is sent again. */
  readonly maxRetries: number;

  constructor(options: FoodApiClientOptions) {
    if (typeof options.apiKey !== 'string') throw new TypeError('apiKey is required');
    this.#apiKey = options.apiKey;
    this.#baseUrl = String(options.baseUrl ?? defaultBaseUrl).replace(/\/+$/, '');
    const custom = options.fetch;
    if (custom === undefined && typeof globalThis.fetch !== 'function') {
      throw new TypeError('no global fetch: pass options.fetch, or use Node 18 or newer');
    }
    // The global fetch is called as a method: some browsers reject it detached from window
    this.#fetch = custom ?? ((input, init) => globalThis.fetch(input, init));
    this.#userAgent = [options.userAgent, `studio93-food-api-ts/${sdkVersion}`].filter(Boolean).join(' ');
    this.timeout = options.timeout ?? 15_000;
    this.maxRetries = Math.max(0, Math.trunc(options.maxRetries ?? 2));
  }

  /**
   * Finds foods matching a query, typos and all ("chiken brest"). A query nothing matches returns an empty page,
   * not an error.
   */
  async search(query: string, options: SearchOptions = {}): Promise<SearchPage> {
    checkQuery(query);
    const params: Record<string, string> = { q: query };
    const { page, limit } = options;
    if (page !== undefined) {
      if (!Number.isInteger(page) || page < 0 || page > maxPage) {
        throw new FoodApiInvalidInput(`page must be between 0 and ${maxPage}`);
      }
      if (page > 0) params['page'] = String(page);
    }
    if (limit !== undefined) {
      if (!Number.isInteger(limit) || limit < 1 || limit > maxLimit) {
        throw new FoodApiInvalidInput(`limit must be between 1 and ${maxLimit}`);
      }
      params['limit'] = String(limit);
    }
    const res = await this.#get('/v2/foods/search', params, options);
    const meta = obj(res.body['meta']);
    return {
      foods: list(res.body['data']).map((f) => Food.fromJson(f)),
      query: strOrNull(meta['query']) ?? query,
      page: num(meta['page']) ?? page ?? 0,
      limit: num(meta['limit']) ?? limit ?? 20,
      total: num(meta['total']) ?? 0,
      source: strOrNull(meta['source']) ?? 'catalog',
      region: strOrNull(meta['region']) || null,
      brand: strOrNull(meta['brand']) || null,
      cached: res.cached,
    };
  }

  /**
   * Suggests foods for what has been typed so far; the last word matches as a prefix ("chick" finds Chicken). It
   * never asks outside providers, so it is fast enough for every keystroke.
   */
  async autocomplete(query: string, options: AutocompleteOptions = {}): Promise<AutocompleteResult> {
    checkQuery(query);
    const params: Record<string, string> = { q: query };
    const { limit } = options;
    if (limit !== undefined) {
      if (!Number.isInteger(limit) || limit < 1 || limit > maxSuggestions) {
        throw new FoodApiInvalidInput(`limit must be between 1 and ${maxSuggestions}`);
      }
      params['limit'] = String(limit);
    }
    const res = await this.#get('/v2/foods/autocomplete', params, options);
    const meta = obj(res.body['meta']);
    return {
      suggestions: list(res.body['data']).map(suggestionFromJson),
      query: strOrNull(meta['query']) ?? query,
      limit: num(meta['limit']) ?? limit ?? 8,
      total: num(meta['total']) ?? 0,
      cached: res.cached,
    };
  }

  /** The food with a catalog ID. An unknown ID rejects with FoodApiNotFound. */
  async food(id: string, options: CallOptions = {}): Promise<Food> {
    const res = await this.#get(`/v2/foods/${segment(id, 'empty food id')}`, undefined, options);
    return Food.fromJson(data(res));
  }

  /**
   * The food for a barcode: 6 to 14 digits, or what a scanner read from a 2D code (a GS1 code such as
   * "(01)03017624010701", or a GS1 Digital Link). A barcode no source knows rejects with FoodApiNotFound.
   */
  async foodByBarcode(barcode: string, options: CallOptions = {}): Promise<Food> {
    const res = await this.#get(`/v2/foods/barcode/${segment(barcode, 'empty barcode')}`, undefined, options);
    return Food.fromJson(data(res));
  }

  /**
   * What a food's source says about each of its nutrient values: samples, spread and how each was obtained. Foods
   * whose source gives no such details have none.
   */
  async nutrientStats(foodId: string, options: CallOptions = {}): Promise<NutrientStats> {
    const path = `/v2/foods/${segment(foodId, 'empty food id')}/nutrient-stats`;
    return nutrientStatsFromJson(data(await this.#get(path, undefined, options)));
  }

  /** Every nutrient key a serving can have, with its name and unit. */
  async nutrients(options: CallOptions = {}): Promise<NutrientList> {
    return nutrientListFromJson(data(await this.#get('/v2/nutrients', undefined, options)));
  }

  /**
   * Every food image, with its label, group and URL, for apps that bundle or prefetch them. Foods carry their own
   * `image`, so showing a food's picture needs no call to this.
   */
  async images(options: CallOptions = {}): Promise<ImageSet> {
    return ImageSet.fromJson(data(await this.#get('/v2/images', undefined, options)));
  }

  /** A session that keeps only the latest search and the latest autocomplete: use one per search screen. */
  session(): FoodSearchSession {
    return new FoodSearchSession(this);
  }

  /** Sends a GET request, retrying what is safe to retry. `path` is already escaped. */
  async #get(path: string, params: Record<string, string> | undefined, options: CallOptions): Promise<ApiResponse> {
    const clientIp = options.clientIp?.trim();
    if (clientIp && !isIpAddress(clientIp)) {
      throw new FoodApiInvalidInput(`client IP "${clientIp}" is not an IPv4 or IPv6 address`);
    }
    const { signal } = options;
    if (signal?.aborted) throw abortError(signal);

    let url = this.#baseUrl + path;
    if (params) url += '?' + new URLSearchParams(params).toString();
    const headers: Record<string, string> = {
      Authorization: `Bearer ${this.#apiKey}`,
      Accept: 'application/json',
    };
    if (!inBrowser()) headers['User-Agent'] = this.#userAgent; // Browsers don't let pages set it
    if (clientIp) headers['X-Client-IP'] = clientIp;

    for (let attempt = 0; ; attempt++) {
      try {
        return await this.#once(url, headers, signal);
      } catch (e) {
        if (!(e instanceof FoodApiError) || signal?.aborted || attempt >= this.maxRetries || !retryable(e)) throw e;
        const delay = (e instanceof FoodApiHttpError ? e.retryAfter : null) ?? backoff(attempt);
        if (delay > maxRetryWait) throw e; // Not worth waiting here; the caller can decide
        await wait(delay, signal);
      }
    }
  }

  /** Sends one request, aborted when the call's signal aborts or the attempt times out. */
  async #once(url: string, headers: Record<string, string>, signal: AbortSignal | undefined): Promise<ApiResponse> {
    const controller = new AbortController();
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, this.timeout);
    const onAbort = () => controller.abort();
    signal?.addEventListener('abort', onAbort);

    const failure = (e: unknown): FoodApiError => {
      if (signal?.aborted) return abortError(signal);
      if (timedOut) return new FoodApiTimeoutError(`no answer within ${this.timeout / 1000} s`, { cause: e });
      if (e instanceof FoodApiError) return e;
      return new FoodApiNetworkError(e instanceof Error ? e.message : String(e), { cause: e });
    };

    try {
      let response: Response;
      let text: string;
      try {
        response = await this.#fetch(url, { method: 'GET', headers, signal: controller.signal });
        text = await response.text();
      } catch (e) {
        throw failure(e);
      }
      if (response.status !== 200) {
        throw FoodApiHttpError.fromStatus(
          response.status,
          errorMessage(text, response),
          parseRetryAfter(response.headers.get('retry-after')),
        );
      }
      let body: unknown;
      try {
        body = JSON.parse(text);
      } catch (e) {
        throw new FoodApiServerError(200, `invalid response: ${e instanceof Error ? e.message : String(e)}`);
      }
      if (!isObject(body)) throw new FoodApiServerError(200, 'invalid response');
      return { body, cached: response.headers.get('x-cache') === 'HIT' };
    } finally {
      clearTimeout(timer);
      signal?.removeEventListener('abort', onAbort);
    }
  }
}

function checkQuery(query: string): void {
  if (typeof query !== 'string' || query.trim() === '') throw new FoodApiInvalidInput('empty query');
  if ([...query].length > maxQueryLength) {
    throw new FoodApiInvalidInput(`query longer than ${maxQueryLength} characters`);
  }
}

/** A path segment, escaped like Go's url.PathEscape so a barcode link's slashes stay inside the segment. */
function segment(value: string, emptyMessage: string): string {
  const v = typeof value === 'string' ? value.trim() : '';
  if (v === '') throw new FoodApiInvalidInput(emptyMessage);
  return encodeURIComponent(v).replace(/%(3A|40|26|3D|2B|24)/gi, (m) => decodeURIComponent(m));
}

function data(res: ApiResponse): unknown {
  const d = res.body['data'];
  if (!isObject(d)) throw new FoodApiServerError(200, 'invalid response: no data');
  return d;
}

function errorMessage(text: string, response: Response): string {
  try {
    const body: unknown = JSON.parse(text);
    if (isObject(body) && typeof body['message'] === 'string' && body['message'] !== '') return body['message'];
  } catch {
    // Not JSON
  }
  return response.statusText || `HTTP ${response.status}`;
}

/** The error for a call whose signal aborted: a timeout when the signal timed out, a cancellation otherwise. */
function abortError(signal: AbortSignal): FoodApiError {
  const reason: unknown = signal.reason;
  if (reason instanceof Error && reason.name === 'TimeoutError') {
    return new FoodApiTimeoutError('the call timed out', { cause: reason });
  }
  return new FoodApiCancelledError({ cause: reason });
}

/** Whether a failed request may succeed when sent again. */
function retryable(e: FoodApiError): boolean {
  if (e instanceof FoodApiNetworkError || e instanceof FoodApiTimeoutError) return true;
  if (e instanceof FoodApiHttpError) return [429, 502, 503, 504].includes(e.statusCode);
  return false;
}

/** Reads a Retry-After header: seconds, or an HTTP date. In milliseconds, or null without one. */
function parseRetryAfter(value: string | null): number | null {
  const v = value?.trim();
  if (!v) return null;
  if (/^\d+$/.test(v)) return Number(v) * 1000;
  const date = Date.parse(v);
  if (Number.isNaN(date)) return null;
  return Math.max(date - Date.now(), 0);
}

/** The wait before retry attempt+1 when the API didn't say: 0.5 s, 1 s, … with jitter. */
function backoff(attempt: number): number {
  const ms = 500 * 2 ** attempt;
  return ms / 2 + Math.random() * (ms / 2);
}

/** Waits, or rejects as soon as the signal aborts. */
function wait(ms: number, signal: AbortSignal | undefined): Promise<void> {
  return new Promise((resolve, reject) => {
    const onAbort = () => {
      clearTimeout(timer);
      reject(abortError(signal!));
    };
    const timer = setTimeout(() => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }, ms);
    signal?.addEventListener('abort', onAbort, { once: true });
  });
}

/** Whether this runs in a web page or worker, where fetch may not set User-Agent. React Native isn't one. */
function inBrowser(): boolean {
  const g = globalThis as { document?: unknown; navigator?: { product?: string }; importScripts?: unknown };
  if (g.navigator?.product === 'ReactNative') return false;
  return g.document !== undefined || typeof g.importScripts === 'function';
}
