"""Calls the real API. It runs only with an API key:

    FOOD_API_KEY=... python3 -m unittest tests.test_live
"""

import os
import unittest

from studio93_food_api import FoodApiClient, FoodApiNotFound, FoodApiUnauthorized

KEY = os.environ.get("FOOD_API_KEY", "")


@unittest.skipUnless(KEY, "FOOD_API_KEY not set")
class TestLive(unittest.TestCase):
    def test_live_api(self) -> None:
        with FoodApiClient(KEY, user_agent="food-api-sdk-tests") as client:
            page = client.search("whole milk", page=1, limit=5)  # Page 1: catalog only
            self.assertTrue(page.foods)
            self.assertIsNotNone(page.foods[0].servings[0].nutrients.calories)

            food = client.food(page.foods[0].id)
            self.assertEqual(food.id, page.foods[0].id)
            self.assertIsNotNone(food.image)

            self.assertTrue(client.autocomplete("chick", 5).suggestions)
            self.assertTrue(client.food_by_barcode("https://id.gs1.org/01/03017624010701").name)
            with self.assertRaises(FoodApiNotFound):
                client.food("01a163d2-0000-7000-8000-000000000000")
            client.nutrient_stats(page.foods[0].id)
            self.assertGreaterEqual(len(client.nutrients().nutrients), 17)

            images = client.images()
            self.assertTrue(images.images)
            self.assertIsNotNone(images.image(images.fallback))

        with FoodApiClient("not-a-key") as bad_key:
            with self.assertRaises(FoodApiUnauthorized):
                bad_key.search("apple", page=1)


if __name__ == "__main__":
    unittest.main()
