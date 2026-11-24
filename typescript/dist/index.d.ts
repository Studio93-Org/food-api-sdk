/**
 * Client for the Studio93 Food API (v2): typo-tolerant food search, autocomplete, barcode lookups and detailed
 * nutrition, for browsers, React Native and Node 18+. Start with {@link FoodApiClient}. The API reference is at
 * https://api.studio93.io/food/docs.
 *
 * @packageDocumentation
 */
export { FoodApiClient, defaultBaseUrl, sdkVersion, type AutocompleteOptions, type CallOptions, type FetchFunction, type FoodApiClientOptions, type SearchOptions, } from './client.js';
export { FoodApiBadRequest, FoodApiCancelledError, FoodApiError, FoodApiForbidden, FoodApiHttpError, FoodApiInvalidInput, FoodApiNetworkError, FoodApiNotFound, FoodApiRateLimited, FoodApiServerError, FoodApiTimeoutError, FoodApiUnauthorized, FoodApiUnavailable, } from './errors.js';
export { Food, FoodImage, FoodType, ImageMatch, ImageSet, ImageTier, NutrientFlag, Nutrients, type AutocompleteResult, type FoodFields, type FoodSource, type ImageEntry, type ImageGroup, type NutrientDefinition, type NutrientList, type NutrientStat, type NutrientStats, type OtherNutrient, type SearchPage, type Serving, type Suggestion, } from './models.js';
export { FoodSearchSession } from './session.js';
