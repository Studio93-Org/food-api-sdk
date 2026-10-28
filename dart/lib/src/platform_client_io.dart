import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// The platform's own HTTP stack: URLSession on iOS and macOS, Cronet on Android. Both pool connections, speak
/// HTTP/2 and HTTP/3 when the server offers them, and handle network changes better than dart:io, which only speaks
/// HTTP/1.1. Elsewhere, or when Cronet isn't available on the device, dart:io with kept-alive connections.
http.Client createPlatformClient() {
  try {
    if (Platform.isIOS || Platform.isMacOS) {
      return CupertinoClient.defaultSessionConfiguration();
    }
    if (Platform.isAndroid) {
      final engine = CronetEngine.build(enableHttp2: true, enableQuic: true, enableBrotli: true);
      return CronetClient.fromCronetEngine(engine, closeEngine: true);
    }
  } catch (_) {
    // No native stack (Cronet missing from the device, or running in a plain Dart VM such as tests)
  }
  return IOClient(
    HttpClient()
      ..idleTimeout = const Duration(seconds: 60)
      ..connectionTimeout = const Duration(seconds: 10),
  );
}
