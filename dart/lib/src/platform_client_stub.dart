import 'package:http/http.dart' as http;

/// Fallback for platforms with neither dart:io nor a browser.
http.Client createPlatformClient() => http.Client();
