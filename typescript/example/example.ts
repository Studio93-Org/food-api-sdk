// The snippets in README.md as code that type-checks (`npm run typecheck`), so the README stays correct.

import {
  FoodApiCancelledError,
  FoodApiClient,
  FoodApiError,
  FoodApiNetworkError,
  FoodApiNotFound,
  FoodApiRateLimited,
  FoodApiTimeoutError,
  FoodApiUnavailable,
  NutrientFlag,
  type Food,
} from '../dist/index.js';

declare const apiKey: string;
declare function show(text: string): void;

// Create one client for the whole app and share it
export const foodApi = new FoodApiClient({ apiKey, userAgent: 'my-app/1.4.0' });

export async function quickStart(): Promise<void> {
  const page = await foodApi.search('greek yogurt'); // Typos are fine: 'chiken brest' works
  for (const food of page.foods) {
    show(`${food.name}: ${food.servings[0]?.nutrients.calories} kcal`);
  }
}

// Search as the user types: one session per search screen
const session = foodApi.session();

export async function onQueryChanged(text: string): Promise<void> {
  try {
    const page = await session.search(text);
    show(page.foods.map((f) => f.name).join(', '));
  } catch (e) {
    if (e instanceof FoodApiCancelledError) return; // The user typed on; a newer search is running
    throw e;
  }
}

export async function scanned(code: string): Promise<Food | null> {
  try {
    return await foodApi.foodByBarcode(code);
  } catch (e) {
    if (e instanceof FoodApiNotFound) return null; // No source knows this barcode
    throw e;
  }
}

export function errorText(e: unknown): string | null {
  if (e instanceof FoodApiCancelledError) return null; // Superseded by a newer search
  if (e instanceof FoodApiNotFound) return 'Not found';
  if (e instanceof FoodApiRateLimited || e instanceof FoodApiUnavailable) return 'Try again in a moment'; // Already retried
  if (e instanceof FoodApiNetworkError || e instanceof FoodApiTimeoutError) return "You're offline";
  if (e instanceof FoodApiError) return e.message;
  throw e;
}

export async function withDeadline(): Promise<void> {
  const page = await foodApi.search('cheddar', { page: 1, limit: 10, signal: AbortSignal.timeout(5000) });
  show(String(page.total));
}

// A server calling for its users
export async function searchForUser(query: string, userIp: string) {
  return foodApi.search(query, { clientIp: userIp });
}

export function nutrition(food: Food): string {
  const n = food.servings[0]!.nutrients; // The source's first serving
  return `${n.calories} kcal, ${n.protein} g protein, ${n.get('magnesium')} mg magnesium`;
}

export function sugarText(food: Food, grams: number): string {
  switch (food.flag('sugar')) {
    case NutrientFlag.upperBound:
      return `< ${grams.toFixed(1)} g`; // The label said "less than"
    case NutrientFlag.approximate:
      return `~${grams.toFixed(1)} g`;
    default:
      return `${grams.toFixed(1)} g`;
  }
}

export function pictureUrl(food: Food): string | null {
  const image = food.image;
  if (image === null || image.isFallback) return null;
  return image.url;
}

export async function prefetchImages(): Promise<string[]> {
  const set = await foodApi.images();
  return set.images.map((image) => image.url);
}
