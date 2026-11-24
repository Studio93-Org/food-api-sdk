/**
 * Client for the Studio93 Food API (v2): typo-tolerant food search, autocomplete, barcode lookups and detailed
 * nutrition, for browsers, React Native and Node 18+. Start with {@link FoodApiClient}. The API reference is at
 * https://api.studio93.io/food/docs.
 *
 * @packageDocumentation
 */
export { FoodApiClient, defaultBaseUrl, sdkVersion, } from './client.js';
export { FoodApiBadRequest, FoodApiCancelledError, FoodApiError, FoodApiForbidden, FoodApiHttpError, FoodApiInvalidInput, FoodApiNetworkError, FoodApiNotFound, FoodApiRateLimited, FoodApiServerError, FoodApiTimeoutError, FoodApiUnauthorized, FoodApiUnavailable, } from './errors.js';
export { Food, FoodImage, FoodType, ImageMatch, ImageSet, ImageTier, NutrientFlag, Nutrients, } from './models.js';
export { FoodSearchSession } from './session.js';
