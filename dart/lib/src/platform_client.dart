// The HTTP client the SDK uses unless you pass one: the platform's own stack where there is one.
export 'platform_client_stub.dart'
    if (dart.library.io) 'platform_client_io.dart'
    if (dart.library.js_interop) 'platform_client_web.dart';
