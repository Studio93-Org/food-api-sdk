package io.studio93.foodapi

import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Assumptions.assumeTrue
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Calls the real API. It runs only with an API key:
 *
 *     FOOD_API_KEY=... ./gradlew test --tests '*LiveTest*'
 */
class LiveTest {
    @Test
    fun `live API`() {
        val key = System.getenv("FOOD_API_KEY")
        assumeTrue(!key.isNullOrEmpty(), "FOOD_API_KEY not set")
        runBlocking {
            withTimeout(60_000) {
                FoodApiClient(key, userAgent = "food-api-sdk-tests").use { client ->
                    val page = client.search("whole milk", page = 1, limit = 5) // Page 1: catalog only
                    assertTrue(page.foods.isNotEmpty())
                    assertNotNull(page.foods.first().servings.first().nutrients.calories)

                    val food = client.food(page.foods.first().id)
                    assertEquals(page.foods.first().id, food.id)

                    assertTrue(client.autocomplete("chick", limit = 5).suggestions.isNotEmpty())
                    assertTrue(client.foodByBarcode("https://id.gs1.org/01/03017624010701").name.isNotEmpty())
                    assertFailsWith<FoodApiNotFound> { client.food("01a163d2-0000-7000-8000-000000000000") }
                    client.nutrientStats(page.foods.first().id)
                    assertTrue(client.nutrients().nutrients.size >= 17)
                    assertNotNull(food.image)
                    val images = client.images()
                    assertTrue(images.images.isNotEmpty())
                    assertNotNull(images.image(images.fallback))
                    // A documentation address (RFC 5737): it only chooses the country, so any valid one works
                    client.withClientIP("192.0.2.1").search("cheddar", page = 1, limit = 5)
                }
                FoodApiClient("not-a-key").use { badKey ->
                    assertFailsWith<FoodApiUnauthorized> { badKey.search("apple", page = 1) }
                }
            }
        }
    }
}
