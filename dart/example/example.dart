// The examples in README.md; flutter analyze checks them, so the README stays correct.
// ignore_for_file: avoid_print

import 'package:studio93_food_api/studio93_food_api.dart';

// Create one client for the whole app (in your dependency injection, a provider or a top-level variable). Load the
// key from your app's configuration; don't commit it.
final foodApi = FoodApiClient(apiKey: const String.fromEnvironment('FOOD_API_KEY'), userAgent: 'my-app/1.4.0');

Future<void> search() async {
  final page = await foodApi.search('greek yogurt');
  for (final food in page.foods) {
    print('${food.name}: ${food.servings.first.nutrients.calories} kcal');
  }
}

/// Search as the user types: one session per search screen.
class SearchScreenLogic {
  final session = foodApi.session();
  List<Food> results = [];

  Future<void> onQueryChanged(String text) async {
    try {
      final page = await session.search(text);
      results = page.foods;
    } on FoodApiCancelledException {
      // The user typed on; a newer search is running
    }
  }

  Future<void> loadMore(String text, int nextPage) async {
    final page = await session.search(text, page: nextPage);
    results = [...results, ...page.foods];
  }

  void dispose() => session.cancel();
}

Future<void> scan(String scanned) async {
  // Whatever the scanner read: a plain barcode, a GS1 code or a GS1 Digital Link
  try {
    final food = await foodApi.foodByBarcode(scanned);
    print(food.name);
  } on FoodApiNotFound {
    print('No source knows this barcode');
  }
}

Future<void> handleErrors(String text) async {
  try {
    await foodApi.search(text);
  } on FoodApiException catch (e) {
    switch (e) {
      case FoodApiNotFound():
        print('not found');
      case FoodApiRateLimited() || FoodApiUnavailable():
        print('try again soon'); // Already retried; (e as FoodApiHttpException).retryAfter says when
      case FoodApiNetworkException() || FoodApiTimeoutException():
        print('offline');
      case FoodApiCancelledException():
        break; // Superseded by a newer search
      default:
        print(e.message);
    }
  }
}

void showNutrition(Food food) {
  final n = food.servings.last.nutrients; // The last serving is always 100 g (or 100 ml)
  print('${n.calories} kcal, ${n.protein} g protein, ${n['magnesium']} mg magnesium');
  final sugar = n.sugar;
  if (sugar != null) print(sugarText(food, sugar));
}

String sugarText(Food food, double grams) => switch (food.flag('sugar')) {
  NutrientFlag.upperBound => '< ${grams.toStringAsFixed(1)} g', // The label said "less than"
  NutrientFlag.approximate => '~${grams.toStringAsFixed(1)} g',
  _ => '${grams.toStringAsFixed(1)} g',
};

Future<void> main() async {
  await search();
  foodApi.close();
}
