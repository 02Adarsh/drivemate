import 'dart:convert';

import 'package:http/http.dart' as http;

/// Public health checks never carry an access token, password or user data.
/// A successful HTTP status alone is NOT proof that this is DriveMate.
class ServerCheck {
  final String baseUrl;
  final bool ok;
  final int? statusCode;
  final int elapsedMs;
  final String message;
  const ServerCheck(
      {required this.baseUrl,
      required this.ok,
      this.statusCode,
      this.elapsedMs = 0,
      required this.message});
}

class ServerConnection {
  /// Accept a server root or /api base; reject credentials, query strings and
  /// unrelated paths. "localhost" here is the PHONE, not the user's computer.
  static String normalize(String raw) {
    final text = raw.trim();
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      throw const FormatException(
          'Use a full http:// or https:// server address.');
    }
    if (RegExp(r'\s').hasMatch(text) ||
        !RegExp(r'^[a-zA-Z0-9.:-]+$').hasMatch(uri.host)) {
      throw const FormatException(
          'Use a hostname or IP without spaces or encoded credentials.');
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const FormatException(
          'Do not put passwords, query strings or fragments in the server address.');
    }
    if (uri.port < 1 || uri.port > 65535) {
      throw const FormatException('Use a port between 1 and 65535.');
    }
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path.isNotEmpty && path != '/api') {
      throw const FormatException(
          'Use the server root or a base ending in /api, not an auth or admin URL.');
    }
    return uri
        .replace(
            scheme: uri.scheme.toLowerCase(),
            host: uri.host.toLowerCase(),
            path: '/api')
        .toString();
  }

  static Future<ServerCheck> probe(http.Client client, String raw,
      {required Duration timeout}) async {
    final base = normalize(raw);
    final watch = Stopwatch()..start();
    try {
      final request = http.Request('GET', Uri.parse('$base/health/'))
        ..headers['Accept'] = 'application/json'
        ..followRedirects = false;
      final response = await http.Response.fromStream(
              await client.send(request).timeout(timeout))
          .timeout(timeout);
      bool identity = false;
      int version = 0;
      try {
        final body = jsonDecode(response.body);
        identity = body is Map &&
            body['status'] == 'ok' &&
            body['service'] == 'drivemate-api';
        if (body is Map) version = (body['api_version'] as num?)?.toInt() ?? 0;
      } catch (_) {/* HTML/another app is not a DriveMate health response. */}
      final ok = response.statusCode == 200 && identity && version >= 10;
      final String message;
      if (ok) {
        message =
            'DriveMate API answered. This checks reachability, not migrations, GPS or payments.';
      } else if (response.statusCode == 200 && identity && version < 10) {
        message =
            'This app needs the V9.1 backend (API 10). Restart with tools/run_backend.ps1 to install requirements and migrate. The old backend is reachable but lacks the new contract.';
      } else if (response.statusCode == 400) {
        message =
            'HTTP 400. Check Django ALLOWED_HOSTS for this exact host, then restart the backend.';
      } else if (response.statusCode == 404) {
        message =
            'Health route not found. Check the /api base and whether the updated backend is running.';
      } else if (response.statusCode >= 300 && response.statusCode < 400) {
        message =
            'Server redirected the health check. Enter the final trusted API address directly.';
      } else if (response.statusCode == 200) {
        message =
            'Something answered, but it is not the DriveMate health response. Do not enter credentials here.';
      } else {
        message =
            'Health check returned HTTP ${response.statusCode}. Check the backend terminal.';
      }
      return ServerCheck(
          baseUrl: base,
          ok: ok,
          statusCode: response.statusCode,
          elapsedMs: watch.elapsedMilliseconds,
          message: message);
    } catch (_) {
      return ServerCheck(
          baseUrl: base,
          ok: false,
          elapsedMs: watch.elapsedMilliseconds,
          message:
              'No response. USB needs a detected/authorized phone and adb reverse. LAN needs the same network, '
              'the correct physical adapter IP, port access and runserver 0.0.0.0:8000.');
    } finally {
      watch.stop();
    }
  }
}
