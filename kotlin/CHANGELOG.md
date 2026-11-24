## 0.4.0

- First release of the Kotlin SDK, matching the Go and Dart SDKs at 0.4.0: search, autocomplete, food by ID and by
  barcode (plain, GS1 codes and Digital Links), nutrient stats, the nutrient list and the image set of the Food API
  v2, for Android (`minSdk` 24) and JVM 11+ servers.
- Suspend functions over OkHttp (kept-alive connections, HTTP/2, gzip); cancelling the coroutine cancels the request
  and any wait before a retry. `FoodSearchSession` cancels superseded searches.
- Retries with `Retry-After`; typed exceptions, including `FoodApiForbidden` for 403.
- `Food.image` (`FoodImage`: key, a public URL that never changes, and `match`), `SearchPage.region` and
  `SearchPage.brand`, generic servings (`Serving.generic`) and nutrient flags.
- `withClientIP` for servers calling for their users (`X-Client-IP`).
- Installed from JitPack at the tag `kotlin-v0.4.0`.
