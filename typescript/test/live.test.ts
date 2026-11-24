import assert from 'node:assert/strict';
import { test } from 'node:test';

import { FoodApiClient, FoodApiNotFound, FoodApiUnauthorized } from '../dist/index.js';

// Calls the real API. It runs only with an API key:
//
//     FOOD_API_KEY=... node --test test/live.test.ts
const key = process.env['FOOD_API_KEY'];

test('live API', { skip: key ? false : 'FOOD_API_KEY not set', timeout: 60_000 }, async () => {
  const client = new FoodApiClient({ apiKey: key!, userAgent: 'food-api-sdk-tests' });
  const signal = AbortSignal.timeout(30_000);

  const page = await client.search('whole milk', { page: 1, limit: 5, signal }); // Page 1: catalog only
  assert.ok(page.foods.length > 0, 'search found nothing');
  const first = page.foods[0]!;
  assert.notEqual(first.servings[0]?.nutrients.calories ?? null, null, 'first result has no calories');

  const food = await client.food(first.id, { signal });
  assert.equal(food.id, first.id);
  assert.ok(food.image, 'food without an image');

  assert.ok((await client.autocomplete('chick', { limit: 5, signal })).suggestions.length > 0);
  assert.ok((await client.foodByBarcode('https://id.gs1.org/01/03017624010701', { signal })).name !== '');
  await assert.rejects(client.food('01a163d2-0000-7000-8000-000000000000', { signal }), FoodApiNotFound);
  await client.nutrientStats(first.id, { signal });
  assert.ok((await client.nutrients({ signal })).nutrients.length >= 17);

  const images = await client.images({ signal });
  assert.ok(images.images.length > 0);
  assert.ok(images.image(images.fallback), `the fallback image ${images.fallback} isn't in the set`);

  const badKey = new FoodApiClient({ apiKey: 'not-a-key' });
  await assert.rejects(badKey.search('apple', { page: 1, signal }), FoodApiUnauthorized);
});
