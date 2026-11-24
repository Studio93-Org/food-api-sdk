## 0.4.0

- First release of the Swift SDK (iOS 15+, macOS 12+, Swift 6), matching the Go and Dart SDKs at 0.4.0: search,
  autocomplete, food by ID and by barcode (plain, GS1 codes and Digital Links), nutrient stats, the nutrient list
  and the image set (`ImageSet`, `ImageGroup`, `ImageEntry`) of the Food API v2.
- `Food.image` (`FoodImage`: key, a public URL that never changes, and `match`: `variant`, `food`, `category` or
  `fallback`), generic servings (`Serving.generic`), nutrient flags and `SearchPage.region`.
- One `Sendable` client on `URLSession` with kept-alive connections (HTTP/2, HTTP/3, gzip); no dependencies.
- Cancellation through Swift task cancellation, and `FoodSearchSession` for search as the user types.
- `withClientIP(_:)` for servers calling the API for their users (`X-Client-IP`).
- Retries with `Retry-After`; typed errors (`FoodAPIError`), including `forbidden` for a 403 such as a v1 key.
