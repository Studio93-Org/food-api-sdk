## 0.2.0

- `Serving.generic`: the API now adds generic servings (100 g, 1 oz, 1 fl oz, 1 cup, 1 tbsp, 1 tsp where they make
  sense) after a food's own; this flag tells them apart.

## 0.1.0

- First release: search, autocomplete, food by ID and by barcode (plain, GS1 codes and Digital Links), nutrient
  stats and the nutrient list of the Food API v2.
- The platform's own HTTP stack by default (URLSession on iOS and macOS, Cronet on Android), with kept-alive
  connections.
- `FoodSearchSession` cancels superseded searches; retries with `Retry-After`; typed exceptions.
