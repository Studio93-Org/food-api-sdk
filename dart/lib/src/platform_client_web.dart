import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// In a browser, requests go through fetch, which already uses HTTP/2 or HTTP/3.
http.Client createPlatformClient() => BrowserClient();
