# studio93_food_api

Flutter client for the [Studio93 Food API](https://api.studio93.io/food/docs) (v2).

## Install

```yaml
dependencies:
  studio93_food_api:
    git:
      url: https://github.com/Studio93-Org/food-api-sdk.git
      path: dart
      ref: dart-v0.1.0
```

It needs Dart 3.10 and Flutter 3.38 or newer.

## Use one client for the whole app

```dart
import 'package:studio93_food_api/studio93_food_api.dart';

// Create it once (in your dependency injection, a provider or a top-level variable) and share it
final foodApi = FoodApiClient(apiKey: apiKey, userAgent: 'my-app/1.4.0');
```

Sharing one client matters: it keeps connections open, so only the first request pays for connecting. By default it
uses the platform's own HTTP stack, `URLSession` on iOS and macOS and Cronet on Android (from Google Play
services; where that's missing, it falls back to `dart:io`). Both speak HTTP/2 and HTTP/3 and cope better with
switching between Wi-Fi and mobile data.

## Search as the user types

Use a `FoodSearchSession` per search screen. A new search cancels the one still in flight, so a slow answer for
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

// When the screen closes
session.cancel();
```

Debounce the text field as usual (250 to 500 ms). `session.autocomplete(text)` works the same way for type-ahead
suggestions; look a picked suggestion up with `foodApi.food(suggestion.id)`.

To load the next page of the same query, call `session.search(text, page: 1)`.

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

Every failure is a `FoodApiException`; switch on the type to show the right message:

```dart
try {
  final page = await foodApi.search(text);
} on FoodApiException catch (e) {
  switch (e) {
    case FoodApiNotFound():
      showNotFound();
    case FoodApiRateLimited() || FoodApiUnavailable():
      showTryAgainSoon(); // Already retried; e.retryAfter says when to try again
    case FoodApiNetworkException() || FoodApiTimeoutException():
      showOffline();
    case FoodApiCancelledException():
      break; // Superseded by a newer search
    default:
      showError(e.message);
  }
}
```

Temporary failures (network errors, timeouts, 429, 502, 503, 504) are retried twice before they reach you. Change
that with `FoodApiClient(maxRetries: ...)`, and the per-attempt limit with `timeout:`.

## Nutrition

Each serving has its nutrients as numbers, null when unknown. The 17 core nutrients have getters; read any other
key by name. `foodApi.nutrients()` lists every key with its name and unit.

```dart
final serving = food.servings.first; // The last serving is always 100 g (or 100 ml)
final n = serving.nutrients;
print('${n.calories} kcal, ${n.protein} g protein, ${n['magnesium']} mg magnesium');
```

Some values aren't plain measurements. Show them as the label meant them:

```dart
String sugarText(Food food, double grams) => switch (food.flag('sugar')) {
      NutrientFlag.upperBound => '< ${grams.toStringAsFixed(1)} g', // The label said "less than"
      NutrientFlag.approximate => '~${grams.toStringAsFixed(1)} g',
      _ => '${grams.toStringAsFixed(1)} g',
    };
```

`foodApi.nutrientStats(food.id)` has the full details behind each value (samples, spread, how it was obtained),
where the source gives them.

## Testing your app

Pass your own `http.Client` (for example `MockClient` from `package:http/testing.dart`) as `httpClient:`. The
SDK's own live test runs against the API with a key:

```bash
FOOD_API_KEY=... flutter test test/live_test.dart
```
