## 0.4.0

- First release of the TypeScript / JavaScript SDK, matching the Go and Dart SDKs at 0.4.0: search, autocomplete,
  food by ID and by barcode (plain, GS1 codes and Digital Links), nutrient stats, the nutrient list and the image
  set (`ImageSet`, `ImageGroup`, `ImageEntry`) of the Food API v2.
- One package for browsers, React Native and Node 18+, on the platform's `fetch`, with no dependencies; ES module
  with type declarations.
- Foods carry `image` (`FoodImage`: key, a public URL that never changes, and `match`: `variant`, `food`,
  `category` or `fallback`), nutrient flags, generic servings, and search pages their `region` and `brand`.
- Every call takes an `AbortSignal`; `FoodSearchSession` cancels superseded searches. Retries with `Retry-After`;
  typed errors; `clientIp` for servers calling for their users (`X-Client-IP`).
