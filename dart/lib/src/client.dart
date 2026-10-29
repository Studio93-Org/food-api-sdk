import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show parseHttpDate;

import 'errors.dart';
import 'models.dart';
import 'platform_client.dart';
import 'session.dart';

/// The SDK version, sent in the User-Agent header.
const sdkVersion = '0.2.0';

/// The Food API.
final defaultBaseUrl = Uri.parse('https://api.studio93.io');

// Limits the API enforces, checked before sending
const _maxQueryLength = 200;
const _maxPage = 1000;
const _maxLimit = 50;
const _maxSuggestions = 20;

// The longest Retry-After the client waits for itself; a longer one is thrown to the caller
const _maxRetryWait = Duration(seconds: 10);

/// Calls the Food API's v2 endpoints.
///
/// Create one for the whole app and share it: it keeps connections open between requests, which saves a TCP and
/// TLS handshake (one or two network round trips) on every request after the first. By default it uses the
/// platform's own HTTP stack (URLSession on iOS, Cronet on Android), which speaks HTTP/2 and HTTP/3.
class FoodApiClient {
  /// [apiKey] is issued by Studio93. [timeout] limits each attempt; [maxRetries] is how often a request that failed
  /// for a temporary reason (network error, timeout, 429, 502, 503, 504) is sent again. Pass [httpClient] to use
  /// your own client, for example in tests; the [FoodApiClient] then doesn't close it.
  FoodApiClient({
    required String apiKey,
    Uri? baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
    this.maxRetries = 2,
    String? userAgent,
  }) : _apiKey = apiKey,
       _baseUrl = baseUrl ?? defaultBaseUrl,
       _http = httpClient ?? createPlatformClient(),
       _ownsClient = httpClient == null,
       _userAgent = [?userAgent, 'studio93-food-api-dart/$sdkVersion'].join(' ');

  final String _apiKey;
  final Uri _baseUrl;
  final http.Client _http;
  final bool _ownsClient;
  final String _userAgent;
  final Duration timeout;
  final int maxRetries;
  final _random = Random();

  /// Finds foods matching [query], typos and all ("chiken brest"). [page] is zero-based (0 to 1000), [limit] is 1
  /// to 50. A query nothing matches returns an empty page, not an error. Completing [cancel] cancels the call.
  Future<SearchPage> search(String query, {int page = 0, int limit = 20, Future<void>? cancel}) async {
    _checkQuery(query);
    if (page < 0 || page > _maxPage) throw FoodApiInvalidInput('page must be between 0 and $_maxPage');
    if (limit < 1 || limit > _maxLimit) throw FoodApiInvalidInput('limit must be between 1 and $_maxLimit');
    final res = await _get(['v2', 'foods', 'search'], {'q': query, 'page': '$page', 'limit': '$limit'}, cancel);
    final meta = res.body['meta'] as Map<String, dynamic>? ?? const {};
    return SearchPage(
      foods: _items(res.body['data']).map((f) => Food.fromJson(f as Map<String, dynamic>)).toList(),
      query: meta['query'] as String? ?? query,
      page: (meta['page'] as num?)?.toInt() ?? page,
      limit: (meta['limit'] as num?)?.toInt() ?? limit,
      total: (meta['total'] as num?)?.toInt() ?? 0,
      source: meta['source'] as String? ?? 'catalog',
      cached: res.cached,
    );
  }

  /// Suggests foods for what has been typed so far; the last word matches as a prefix ("chick" finds Chicken).
  /// [limit] is 1 to 20. It never asks outside providers, so it is fast enough for every keystroke.
  Future<AutocompleteResult> autocomplete(String query, {int limit = 8, Future<void>? cancel}) async {
    _checkQuery(query);
    if (limit < 1 || limit > _maxSuggestions) {
      throw FoodApiInvalidInput('limit must be between 1 and $_maxSuggestions');
    }
    final res = await _get(['v2', 'foods', 'autocomplete'], {'q': query, 'limit': '$limit'}, cancel);
    final meta = res.body['meta'] as Map<String, dynamic>? ?? const {};
    return AutocompleteResult(
      suggestions: _items(res.body['data']).map((s) => Suggestion.fromJson(s as Map<String, dynamic>)).toList(),
      query: meta['query'] as String? ?? query,
      limit: (meta['limit'] as num?)?.toInt() ?? limit,
      total: (meta['total'] as num?)?.toInt() ?? 0,
      cached: res.cached,
    );
  }

  /// The food with a catalog ID. An unknown ID throws [FoodApiNotFound].
  Future<Food> food(String id, {Future<void>? cancel}) async {
    if (id.trim().isEmpty) throw const FoodApiInvalidInput('empty food id');
    final res = await _get(['v2', 'foods', id.trim()], const {}, cancel);
    return Food.fromJson(res.body['data'] as Map<String, dynamic>);
  }

  /// The food for a barcode: 6 to 14 digits, or what a scanner read from a 2D code (a GS1 code such as
  /// "(01)03017624010701", or a GS1 Digital Link). A barcode no source knows throws [FoodApiNotFound].
  Future<Food> foodByBarcode(String barcode, {Future<void>? cancel}) async {
    if (barcode.trim().isEmpty) throw const FoodApiInvalidInput('empty barcode');
    final res = await _get(['v2', 'foods', 'barcode', barcode.trim()], const {}, cancel);
    return Food.fromJson(res.body['data'] as Map<String, dynamic>);
  }

  /// What a food's source says about each of its nutrient values: samples, spread and how each was obtained.
  /// Foods whose source gives no such details have none.
  Future<NutrientStats> nutrientStats(String foodId, {Future<void>? cancel}) async {
    if (foodId.trim().isEmpty) throw const FoodApiInvalidInput('empty food id');
    final res = await _get(['v2', 'foods', foodId.trim(), 'nutrient-stats'], const {}, cancel);
    return NutrientStats.fromJson(res.body['data'] as Map<String, dynamic>);
  }

  /// Every nutrient key a serving can have, with its name and unit.
  Future<NutrientList> nutrients({Future<void>? cancel}) async {
    final res = await _get(['v2', 'nutrients'], const {}, cancel);
    return NutrientList.fromJson(res.body['data'] as Map<String, dynamic>);
  }

  /// A session that keeps only the latest search and the latest autocomplete: use one per search screen.
  FoodSearchSession session() => FoodSearchSession(this);

  /// Closes the connections, if the client created its HTTP client itself.
  void close() {
    if (_ownsClient) _http.close();
  }

  void _checkQuery(String query) {
    if (query.trim().isEmpty) throw const FoodApiInvalidInput('empty query');
    if (query.runes.length > _maxQueryLength) {
      throw const FoodApiInvalidInput('query longer than $_maxQueryLength characters');
    }
  }

  /// Sends a GET request, retrying what is safe to retry.
  Future<_Response> _get(List<String> path, Map<String, String> query, Future<void>? cancel) async {
    var cancelled = false;
    if (cancel != null) unawaited(cancel.then((_) => cancelled = true));
    final uri = _baseUrl.replace(
      pathSegments: [..._baseUrl.pathSegments.where((s) => s.isNotEmpty), ...path],
      queryParameters: query.isEmpty ? null : query,
    );

    for (var attempt = 0; ; attempt++) {
      try {
        return await _once(uri, cancel);
      } on FoodApiException catch (e) {
        if (cancelled || e is FoodApiCancelledException || attempt >= maxRetries || !_retryable(e)) rethrow;
        final retryAfter = e is FoodApiHttpException ? e.retryAfter : null;
        final delay = retryAfter ?? _backoff(attempt);
        if (delay > _maxRetryWait) rethrow; // Not worth waiting here; the caller can decide
        await Future.any([Future<void>.delayed(delay), ?cancel]);
        if (cancelled) throw const FoodApiCancelledException();
      }
    }
  }

  /// Sends one request. The request is aborted when [cancel] completes or the attempt times out.
  Future<_Response> _once(Uri uri, Future<void>? cancel) async {
    final abort = Completer<void>();
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      if (!abort.isCompleted) abort.complete();
    });
    if (cancel != null) {
      unawaited(
        cancel.then((_) {
          if (!abort.isCompleted) abort.complete();
        }),
      );
    }

    final request = http.AbortableRequest('GET', uri, abortTrigger: abort.future)
      ..headers['Authorization'] = 'Bearer $_apiKey'
      ..headers['Accept'] = 'application/json';
    if (!kIsWeb) request.headers['User-Agent'] = _userAgent; // Browsers don't let pages set it

    try {
      final response = await http.Response.fromStream(await _http.send(request));
      if (response.statusCode != 200) {
        throw FoodApiHttpException.fromStatus(
          response.statusCode,
          _errorMessage(response),
          retryAfter: _parseRetryAfter(response.headers['retry-after']),
        );
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) throw const FoodApiServerError(200, 'invalid response');
      return _Response(body, response.headers['x-cache'] == 'HIT');
    } on http.RequestAbortedException {
      if (timedOut) throw FoodApiTimeoutException('no answer within ${timeout.inSeconds} s');
      throw const FoodApiCancelledException();
    } on http.ClientException catch (e) {
      throw FoodApiNetworkException(e.message, e);
    } on FormatException catch (e) {
      throw FoodApiServerError(200, 'invalid response: ${e.message}');
    } finally {
      timer.cancel();
    }
  }

  bool _retryable(FoodApiException e) => switch (e) {
    FoodApiNetworkException() || FoodApiTimeoutException() || FoodApiRateLimited() || FoodApiUnavailable() => true,
    FoodApiServerError(:final statusCode) => statusCode == 502 || statusCode == 504,
    _ => false,
  };

  /// The wait before retry attempt+1 when the API didn't say: 0.5 s, 1 s, … with jitter.
  Duration _backoff(int attempt) {
    final ms = 500 * (1 << attempt);
    return Duration(milliseconds: ms ~/ 2 + _random.nextInt(ms ~/ 2 + 1));
  }
}

class _Response {
  const _Response(this.body, this.cached);

  final Map<String, dynamic> body;
  final bool cached;
}

String _errorMessage(http.Response response) {
  try {
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is Map && body['message'] is String) return body['message'] as String;
  } on FormatException {
    // Not JSON
  }
  return response.reasonPhrase ?? 'HTTP ${response.statusCode}';
}

/// Reads a Retry-After header: seconds, or an HTTP date.
Duration? _parseRetryAfter(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final seconds = int.tryParse(value.trim());
  if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
  try {
    final until = parseHttpDate(value).difference(DateTime.now());
    return until.isNegative ? Duration.zero : until;
  } on FormatException {
    return null;
  }
}

List<Object?> _items(Object? data) => (data as List<Object?>?) ?? const [];
