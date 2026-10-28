/// Client for the Studio93 Food API (v2): typo-tolerant food search, autocomplete, barcode lookups and detailed
/// nutrition. Start with [FoodApiClient]. The API reference is at https://api.studio93.io/food/docs.
library;

export 'src/client.dart' show FoodApiClient, defaultBaseUrl, sdkVersion;
export 'src/errors.dart';
export 'src/models.dart';
export 'src/session.dart';
