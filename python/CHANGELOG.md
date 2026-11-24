## 0.4.0

- First release of the Python SDK, matching the Go and Dart SDKs at 0.4.0: search, autocomplete, food by ID and by
  barcode (plain, GS1 codes and Digital Links), nutrient stats, the nutrient list and the image set of the Food API
  v2, with food images (`Food.image`), generic servings, nutrient flags, and the search page's region and brand
  (`SearchPage.brand`). HTTP 403 is its own error, `FoodApiForbidden`.
- Standard library only (Python 3.9+): kept-alive connections shared by threads, gzip, retries with `Retry-After`,
  typed errors, a per-call `timeout=`, and the user's IP for servers (`client_ip=`, `with_client_ip`).
