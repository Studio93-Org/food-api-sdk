# studio93_food_api

Flutter client for the [Studio93 Food API](https://api.studio93.io/food/docs) (v2): typo-tolerant food search,
autocomplete, barcode lookups and detailed nutrition. You need an API key from Studio93.

## Install

Add it to your app's `pubspec.yaml` as a git dependency, pinned to a release:

```yaml
dependencies:
  studio93_food_api:
    git:
      url: https://github.com/Studio93-Org/food-api-sdk.git
      path: dart
      ref: dart-v0.2.0
```

Then run `flutter pub get`. To upgrade, change `ref` to a newer `dart-v…` tag.

## Requirements

| | |
|---|---|
| Flutter | 3.38 or newer (Dart 3.10) |
| iOS | 15 or newer |
| macOS | 12 or newer, with the outgoing-connections entitlement (`com.apple.security.network.client`) |
| Android | `minSdk` 24 or newer, with the `INTERNET` permission |
| Web | supported (requests go through the browser) |

The SDK uses each platform's own HTTP stack: `URLSession` on iOS and macOS and Cronet on Android. Both pool
connections, speak HTTP/2 and HTTP/3, and cope better with switching between Wi-Fi and mobile data than `dart:io`.
Cronet comes from Google Play services; on devices without them the SDK falls back to `dart:io`. To bundle Cronet
in your app instead (for example for devices without Google Play), build with
`--dart-define=cronetHttpNoPlay=true` (see [cronet_http](https://pub.dev/packages/cronet_http)).

## Create one client for the whole app

```dart
import 'package:studio93_food_api/studio93_food_api.dart';

final foodApi = FoodApiClient(apiKey: apiKey, userAgent: 'my-app/1.4.0');
```

Create it once (in your dependency injection, a provider or a top-level variable) and share it. A shared client keeps
connections open, so only the first request pays for connecting; a client per request pays for it every time.
Load the API key from your app's configuration (for example Remote Config) and don't commit it.

## Search

```dart
final page = await foodApi.search('greek yogurt'); // Typos are fine: 'chiken brest' works
for (final food in page.foods) {
  print('${food.name}: ${food.servings.first.nutrients.calories} kcal');
}
```

`search` takes `page` (zero-based) and `limit` (1 to 50, default 20). A query nothing matches returns an empty page.

### As the user types

Use one `FoodSearchSession` per search screen. A new search cancels the one still in flight, so a slow answer for
"app" can never replace the results for "apple":

```dart
final session = foodApi.session();

Future<void> onQueryChanged(String text) async {
  try {
    final page = await session.search(text);
    setState(() => results = page.foods);
  } on FoodApiCancelledException {
    // The user typed on; a newer search is running
  }
}

// Next page of the same query
final more = await session.search(text, page: 1);

// When the screen closes
session.cancel();
```

Debounce the text field as usual (250 to 500 ms). For a type-ahead list, `session.autocomplete(text)` works the same
way and is fast enough for every keystroke; look a picked suggestion up with `foodApi.food(suggestion.id)`.

## Barcodes

Pass whatever the scanner read: a plain barcode, a GS1 code or a GS1 Digital Link.

```dart
try {
  final food = await foodApi.foodByBarcode(scanned);
  showFood(food);
} on FoodApiNotFound {
  showNotFound(); // No source knows this barcode
}
```

## Errors

Every failure is a `FoodApiException`. Switch on the type to show the right message:

```dart
try {
  final page = await foodApi.search(text);
} on FoodApiException catch (e) {
  switch (e) {
    case FoodApiNotFound():
      showNotFound();
    case FoodApiRateLimited() || FoodApiUnavailable():
      showTryAgainSoon(); // Already retried
    case FoodApiNetworkException() || FoodApiTimeoutException():
      showOffline();
    case FoodApiCancelledException():
      break; // Superseded by a newer search
    default:
      showError(e.message);
  }
}
```

Temporary failures (network errors, timeouts, and 429, 502, 503 and 504 responses) are retried twice before they
reach you, waiting as long as the API's `Retry-After` header asks (up to 10 seconds). Change this with
`FoodApiClient(maxRetries: …)`, and the time limit per attempt with `timeout:` (default 15 seconds).

## Nutrition

Every serving has its nutrients as numbers, null when unknown. The 17 core nutrients have getters; read any other
key by name. `foodApi.nutrients()` lists every key with its name and unit.

```dart
final n = food.servings.first.nutrients; // The source's first serving
print('${n.calories} kcal, ${n.protein} g protein, ${n['magnesium']} mg magnesium');
```

A food's servings start with its source's own and end with generic ones (`serving.generic`): 100 g and 1 oz for
solids, plus 1 cup or 1 tbsp and 1 tsp where the source measures the food that way; 100 ml, 1 fl oz, 1 cup, 1 tbsp
and 1 tsp for liquids. A food measured only by volume ("1/2 cup") gets the other volumes but no weights; one
measured by neither ("1 serving") gets none.

Some values aren't plain measurements. Show them the way the label meant them:

```dart
String sugarText(Food food, double grams) => switch (food.flag('sugar')) {
  NutrientFlag.upperBound => '< ${grams.toStringAsFixed(1)} g', // The label said "less than"
  NutrientFlag.approximate => '~${grams.toStringAsFixed(1)} g',
  _ => '${grams.toStringAsFixed(1)} g',
};
```

`food.alternateNames` has the other names a source gives the food, and `foodApi.nutrientStats(food.id)` the details
behind each value (samples, spread, how it was obtained) where the source gives them.

## Testing your app

Pass your own `http.Client` as `httpClient:`, for example `MockClient` from `package:http/testing.dart`; the
`FoodApiClient` then leaves it open when you call `close()`. [example/example.dart](example/example.dart) has these
snippets as code that compiles. The SDK's own tests:

```bash
flutter test                                       # unit tests
FOOD_API_KEY=... flutter test test/live_test.dart  # against the API
```
