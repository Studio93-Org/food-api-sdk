import 'dart:async';

import 'client.dart';
import 'errors.dart';
import 'models.dart';

/// Keeps only the latest search and the latest autocomplete for one search screen.
///
/// Starting a search cancels the search still in flight, and starting an autocomplete cancels the autocomplete
/// still in flight: their futures throw [FoodApiCancelledException], which you can ignore. So a slow answer for
/// "app" can never replace the results for "apple", and abandoned requests stop using the network.
///
/// ```dart
/// final session = client.session();
/// try {
///   final page = await session.search(text);
///   showResults(page);
/// } on FoodApiCancelledException {
///   // The user typed on; a newer search is running
/// }
/// ```
class FoodSearchSession {
  FoodSearchSession(this._client);

  final FoodApiClient _client;
  Completer<void>? _search;
  Completer<void>? _autocomplete;

  /// Searches, cancelling this session's previous search. Loading the next page of the same query is a search too.
  Future<SearchPage> search(String query, {int page = 0, int limit = 20}) {
    _search = _replace(_search);
    return _client.search(query, page: page, limit: limit, cancel: _search!.future);
  }

  /// Suggests foods, cancelling this session's previous autocomplete.
  Future<AutocompleteResult> autocomplete(String query, {int limit = 8}) {
    _autocomplete = _replace(_autocomplete);
    return _client.autocomplete(query, limit: limit, cancel: _autocomplete!.future);
  }

  /// Cancels whatever is in flight, for example when the screen closes.
  void cancel() {
    _complete(_search);
    _complete(_autocomplete);
  }

  static Completer<void> _replace(Completer<void>? previous) {
    _complete(previous);
    return Completer<void>();
  }

  static void _complete(Completer<void>? c) {
    if (c != null && !c.isCompleted) c.complete();
  }
}
