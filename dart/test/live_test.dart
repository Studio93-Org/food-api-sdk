import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:studio93_food_api/studio93_food_api.dart';

/// Calls the real API. It runs only with an API key:
///
///     FOOD_API_KEY=... flutter test test/live_test.dart
void main() {
  final key = Platform.environment['FOOD_API_KEY'];

  test(
    'live API',
    () async {
      // dart:io here: the platform clients need a device or simulator
      final client = FoodApiClient(apiKey: key!, httpClient: IOClient(), userAgent: 'food-api-sdk-tests');

      final page = await client.search('whole milk', page: 1, limit: 5); // Page 1: catalog only
      expect(page.foods, isNotEmpty);
      expect(page.foods.first.servings.first.nutrients.calories, isNotNull);

      final food = await client.food(page.foods.first.id);
      expect(food.id, page.foods.first.id);

      expect((await client.autocomplete('chick', limit: 5)).suggestions, isNotEmpty);
      expect((await client.foodByBarcode('https://id.gs1.org/01/03017624010701')).name, isNotEmpty);
      await expectLater(client.food('01a163d2-0000-7000-8000-000000000000'), throwsA(isA<FoodApiNotFound>()));
      await client.nutrientStats(page.foods.first.id);
      expect((await client.nutrients()).nutrients.length, greaterThanOrEqualTo(17));

      final badKey = FoodApiClient(apiKey: 'not-a-key', httpClient: IOClient());
      await expectLater(badKey.search('apple', page: 1), throwsA(isA<FoodApiUnauthorized>()));
    },
    skip: key == null ? 'FOOD_API_KEY not set' : null,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
