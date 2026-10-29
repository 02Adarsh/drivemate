import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'server_connection.dart';

/// One exception type for the whole app, carrying a message that is safe to
/// show to a person (never a raw stack trace).
class ApiException implements Exception {
  final String message;
  final List<String> missingFields;
  final int? statusCode;

  /// Raw response body, so a screen can react to flags such as
  /// `needs_verification` (email not verified yet) without string matching.
  final Map<String, dynamic>? payload;

  ApiException(this.message,
      {this.missingFields = const [], this.statusCode, this.payload});

  @override
  String toString() => message;
}

/// All backend calls live here. Screens never talk to `http` directly.
///
/// Session handling: the JWT access token is cached in memory and in
/// SharedPreferences, so the app keeps working if the phone is rotated or the
/// screen is rebuilt.
class AuthService {
  static const String _accessKey = 'dm_access_token';
  static const String _refreshKey = 'dm_refresh_token';
  static const String _userKey = 'dm_user';
  static const String _serverKey = 'dm_api_base_override_v8';
  static const String _sessionBaseKey = 'dm_session_base_v8';
  static const String _contractKey = 'dm_session_contract';
  static String? _customBase;
  static String? _sessionBase;
  static Future<void>? _backendInitialization;
  static Future<void>? _backendChange;
  static Future<void>? _sessionWrites;
  static Future<bool>? _ongoingRefresh;
  static int _backendRevision = 0;

  static String? _cachedToken;
  static http.Client _client = http.Client();

  /// Deterministic network injection used by widget/API contract tests only.
  @visibleForTesting
  static void setHttpClientForTests(http.Client? client) {
    _client = client ?? http.Client();
    _cachedToken = null;
    _customBase = null;
    _sessionBase = null;
    _backendInitialization = null;
    _backendChange = null;
    _sessionWrites = null;
    _ongoingRefresh = null;
    _backendRevision++;
    resetBaseUrl();
  }

  // ---------------------------------------------------------------- session

  static Future<void> saveSession(Map<String, dynamic> data) async {
    await _readyForRequests();
    final revision = data['_dm_revision'] is int
        ? data['_dm_revision'] as int
        : _backendRevision;
    final origin = (data['_dm_base'] ?? activeBaseUrl).toString();
    _requireRevision(revision);
    if (origin != activeBaseUrl) {
      throw ApiException(
          'The sign-in response belongs to a different server. Sign in again.');
    }
    final previous = _sessionWrites;
    final gate = Completer<void>();
    _sessionWrites = gate.future;
    try {
      await previous;
      _requireRevision(revision);
      final prefs = await SharedPreferences.getInstance();
      _requireRevision(revision);
      final access = data['access'] as String?;
      if (access != null) {
        _cachedToken = access;
        _sessionBase = origin;
        await prefs.setString(_accessKey, access);
        await prefs.setString(_sessionBaseKey, origin);
        await prefs.setInt(_contractKey, 9);
      }
      if (data['refresh'] != null) {
        await prefs.setString(_refreshKey, data['refresh'] as String);
      }
      if (data['user'] != null) {
        await prefs.setString(_userKey, jsonEncode(data['user']));
      }
      _requireRevision(revision);
    } finally {
      gate.complete();
    }
  }

  static Future<void> clearSession() async {
    _backendRevision++;
    _cachedToken = null;
    await _sessionWrites;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_userKey);
    await prefs.remove(_sessionBaseKey);
    await prefs.remove(_contractKey);
    _sessionBase = null;
  }

  static Future<String?> token() async {
    await initializeBackend();
    if (_cachedToken != null) return _cachedToken;
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(_accessKey);
    return _cachedToken;
  }

  static Future<bool> hasSession() async => (await token()) != null;

  /// Locally cached user data (id, name, email, role). Server data always wins.
  static Future<Map<String, dynamic>?> cachedUser() async {
    await initializeBackend();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // --------------------------------------------------------------- requests

  // ------------------------------------------------------------- base address

  /// Base URL that answered last. `null` = nothing answered yet.
  static String? _activeBase;

  /// Address the app is currently using (for messages and debugging).
  static String get activeBaseUrl =>
      _sessionBase ?? _activeBase ?? _customBase ?? apiBaseUrl;

  static String? get customBaseUrl => _customBase;
  static String get backendScope => activeBaseUrl;

  static String _clean(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// One initialization per process. A v7 token has no trustworthy server pin,
  /// so the v8 upgrade signs in again rather than sending it to a guessed host.
  static Future<void> initializeBackend() =>
      _backendInitialization ??= _loadBackendPreference();

  static Future<void> _loadBackendPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_serverKey);
    final session = prefs.getString(_sessionBaseKey);
    var invalid = false;
    try {
      if (custom != null) _customBase = ServerConnection.normalize(custom);
    } on FormatException {
      invalid = true;
      await prefs.remove(_serverKey);
    }
    try {
      if (session != null) _sessionBase = ServerConnection.normalize(session);
    } on FormatException {
      invalid = true;
    }
    if ((prefs.containsKey(_accessKey) &&
            (_sessionBase == null || prefs.getInt(_contractKey) != 9)) ||
        invalid ||
        (_customBase != null &&
            _sessionBase != null &&
            _customBase != _sessionBase)) {
      await clearSession();
    }
  }

  /// Switch only after a user confirmation in the connection screen. No token
  /// or private response from the old backend may cross this boundary.
  static Future<bool> setBackendUrl(String? raw) async {
    final normalized = raw == null || raw.trim().isEmpty
        ? null
        : ServerConnection.normalize(raw);
    await initializeBackend();
    if (_backendChange != null) await _backendChange;
    if (normalized == _customBase) return false;
    final gate = Completer<void>();
    _backendChange = gate.future;
    _backendRevision++;
    _cachedToken = null;
    try {
      await _sessionWrites;
      await clearSession();
      final prefs = await SharedPreferences.getInstance();
      if (normalized == null) {
        await prefs.remove(_serverKey);
      } else {
        await prefs.setString(_serverKey, normalized);
      }
      _customBase = normalized;
      _activeBase = null;
      return true;
    } finally {
      _backendChange = null;
      gate.complete();
    }
  }

  static Future<void> _readyForRequests() async {
    await initializeBackend();
    if (_backendChange != null) await _backendChange;
  }

  /// Public discovery candidates only. Custom addresses and signed-in sessions
  /// are pinned: a failed request never guesses another server with credentials.
  static List<String> candidateBaseUrls() {
    if (_sessionBase != null) return [_sessionBase!];
    if (_customBase != null) return [_customBase!];
    final bases = <String>[];
    for (final value in [_activeBase, apiBaseUrl, ...apiFallbackBaseUrls]) {
      if (value == null) continue;
      final clean = _clean(value);
      if (!bases.contains(clean)) bases.add(clean);
    }
    return bases;
  }

  static void resetBaseUrl() => _activeBase = null;

  static Future<ServerCheck> checkServer(String base) =>
      ServerConnection.probe(_client, base, timeout: apiProbeTimeout);

  static Future<String?> detectBaseUrl({bool force = false}) async {
    await _readyForRequests();
    final revision = _backendRevision;
    if (_activeBase != null && !force) return _activeBase;
    for (final base in candidateBaseUrls()) {
      final result = await checkServer(base);
      if (revision != _backendRevision) return null;
      if (result.ok) {
        _activeBase = result.baseUrl;
        return _activeBase;
      }
    }
    return null;
  }

  static Future<({String base, int revision})> _connectionBase() async {
    await _readyForRequests();
    final revision = _backendRevision;
    if (_sessionBase != null) return (base: _sessionBase!, revision: revision);
    if (_activeBase != null) return (base: _activeBase!, revision: revision);
    final found = await detectBaseUrl();
    _requireRevision(revision);
    if (found != null) return (base: found, revision: revision);
    throw ApiException(
        'No DriveMate backend answered the public health check. Open Server connection on '
        'Login or Account. A blank adb device list means Windows has not detected an authorized phone.');
  }

  static void _requireRevision(int revision) {
    if (revision != _backendRevision) {
      throw ApiException('The server changed. Sign in again to continue.');
    }
  }

  static Uri _uri(String path, [String? base]) =>
      Uri.parse('${base ?? activeBaseUrl}/$path');

  static bool _isConnectionFailure(Object error) =>
      error is TimeoutException ||
      error is SocketException ||
      error is http.ClientException;

  static Future<Map<String, String>> _headers(
      {bool withAuth = false, bool json = true}) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (json) headers['Content-Type'] = 'application/json';
    if (withAuth) {
      final access = await token();
      if (access != null) headers['Authorization'] = 'Bearer $access';
    }
    return headers;
  }

  static Never _networkError(Object error) {
    final tried = activeBaseUrl;
    if (error is TimeoutException) {
      throw ApiException(
        'The server took too long to respond.\n\nSelected server:\n$tried\n\n'
        'Keep the backend running on the computer and check the Wi-Fi/USB link.',
      );
    }
    if (_isConnectionFailure(error)) {
      throw ApiException(
        'Cannot reach the selected DriveMate server ($tried).\n\n'
        'On the computer, start it with:\n'
        '  python manage.py runserver 0.0.0.0:8000\n\n'
        'USB cable (recommended):\n'
        '  adb reverse tcp:8000 tcp:8000\n'
        'then select http://127.0.0.1:8000/api in Server connection.\n\n'
        'Same Wi-Fi: put your computer IPv4 address (ipconfig) in lib/config.dart\n'
        'and allow port 8000 in the firewall.',
      );
    }
    throw ApiException('Something went wrong. Please try again.');
  }

  static Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      body = decoded is Map<String, dynamic> ? decoded : {'data': decoded};
    } catch (_) {
      throw ApiException(
        'Unexpected server response (HTTP ${response.statusCode}). Check the backend address in lib/config.dart.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return body;
    throw ApiException(
      _messageFrom(body, response.statusCode),
      missingFields: _missingFieldsFrom(body),
      statusCode: response.statusCode,
      payload: body,
    );
  }

  static String _messageFrom(Map<String, dynamic> body, int statusCode) {
    final detail = body['detail'] ?? body['message'];
    if (detail is String && detail.trim().isNotEmpty) return detail;
    if (detail is List && detail.isNotEmpty) return detail.first.toString();
    // Field errors: {"email": ["..."]}
    for (final value in body.values) {
      if (value is List && value.isNotEmpty) return value.first.toString();
      if (value is String && value.isNotEmpty) return value;
    }
    if (statusCode == 401) {
      return 'Your session has expired. Please log in again.';
    }
    if (statusCode == 403) return 'You do not have access to this action.';
    return 'Request failed (HTTP $statusCode).';
  }

  static List<String> _missingFieldsFrom(Map<String, dynamic> body) {
    final raw = body['missing_fields'];
    if (raw is List) return raw.map((item) => item.toString()).toList();
    return [];
  }

  static Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    bool retryAuth = true,
    int? expectedRevision,
  }) async {
    final target = await _connectionBase();
    final base = target.base;
    final revision = target.revision;
    if (expectedRevision != null) _requireRevision(expectedRevision);
    final headers = await _headers(withAuth: auth);
    _requireRevision(revision);
    final uri = _uri(path, base);
    final encoded = jsonEncode(body ?? {});
    try {
      final request = http.Request(method, uri)
        ..headers.addAll(headers)
        ..followRedirects = false;
      if (method == 'POST' || method == 'PUT' || method == 'DELETE') {
        request.body = encoded;
      }
      final response = await http.Response.fromStream(
              await _client.send(request).timeout(apiTimeout))
          .timeout(apiTimeout);
      _requireRevision(revision);
      if (response.statusCode == 401 &&
          auth &&
          retryAuth &&
          await _refreshAccess()) {
        _requireRevision(revision);
        return await _send(method, path,
            body: body,
            auth: auth,
            retryAuth: false,
            expectedRevision: revision);
      }
      _requireRevision(revision);
      _activeBase = base;
      final decoded = _decode(response);
      if (decoded['access'] is String) {
        return {...decoded, '_dm_base': base, '_dm_revision': revision};
      }
      return decoded;
    } on ApiException {
      rethrow;
    } catch (error) {
      _requireRevision(revision);
      _networkError(error);
    }
  }

  static Future<bool> _refreshAccess() async {
    final pending = _ongoingRefresh;
    if (pending != null) return pending;
    final job = _performRefresh();
    _ongoingRefresh = job;
    try {
      return await job;
    } finally {
      _ongoingRefresh = null;
    }
  }

  static Future<bool> _performRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final refresh = prefs.getString(_refreshKey);
    if (refresh == null) return false;
    try {
      final data = await _send('POST', 'auth/token/refresh/',
          body: {'refresh': refresh}, auth: false, retryAuth: false);
      await saveSession(data);
      return true;
    } on ApiException {
      return false;
    }
  }

  /// File extension -> MIME type.
  ///
  /// Why this matters: `MultipartFile.fromPath` guesses nothing and sends
  /// `application/octet-stream`, which the server rejects as an invalid file
  /// type. That was the cause of "Allowed file types: jpg, png, webp" when
  /// uploading a profile photo. We now send the correct content type.
  static MediaType? _mediaTypeFor(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      case 'heic':
        return MediaType('image', 'heic');
      case 'heif':
        return MediaType('image', 'heif');
      case 'gif':
        return MediaType('image', 'gif');
      case 'pdf':
        return MediaType('application', 'pdf');
      default:
        return null;
    }
  }

  static Future<Map<String, dynamic>> _upload(
    String path, {
    required String filePath,
    Map<String, String> fields = const {},
    String fileField = 'file',
    bool retryAuth = true,
    int? expectedRevision,
  }) async {
    try {
      final mediaType = _mediaTypeFor(filePath);
      if (mediaType == null) {
        throw ApiException(
          'That file type cannot be uploaded. Use a JPG, PNG or WebP photo'
          '${fields['document_type'] != null ? ' (PDF is also allowed)' : ''}.',
        );
      }

      final target = await _connectionBase();
      final base = target.base;
      final revision = target.revision;
      if (expectedRevision != null) _requireRevision(expectedRevision);
      final headers = await _headers(withAuth: true, json: false);
      _requireRevision(revision);
      try {
        final request = http.MultipartRequest('POST', _uri(path, base))
          ..followRedirects = false;
        request.headers.addAll(headers);
        request.fields.addAll(fields);
        request.files.add(await http.MultipartFile.fromPath(fileField, filePath,
            contentType: mediaType));
        _requireRevision(revision);
        final response = await http.Response.fromStream(
                await _client.send(request).timeout(uploadTimeout))
            .timeout(uploadTimeout);
        _requireRevision(revision);
        if (response.statusCode == 401 && retryAuth && await _refreshAccess()) {
          _requireRevision(revision);
          return await _upload(path,
              filePath: filePath,
              fields: fields,
              fileField: fileField,
              retryAuth: false,
              expectedRevision: revision);
        }
        _requireRevision(revision);
        _activeBase = base;
        return _decode(response);
      } on ApiException {
        rethrow;
      } catch (error) {
        _requireRevision(revision);
        _networkError(error);
      }
    } on ApiException {
      rethrow;
    }
  }

  /// Private PDFs/photos use the same pinned server and auth boundary.
  static Future<Uint8List> getPrivateBytes(String path,
      {bool retryAuth = true, int? expectedRevision}) async {
    final target = await _connectionBase();
    if (expectedRevision != null) _requireRevision(expectedRevision);
    final headers = await _headers(withAuth: true, json: false);
    _requireRevision(target.revision);
    final request = http.Request('GET', _uri(path, target.base))
      ..headers.addAll(headers)
      ..followRedirects = false;
    try {
      final response = await http.Response.fromStream(
              await _client.send(request).timeout(apiTimeout))
          .timeout(apiTimeout);
      _requireRevision(target.revision);
      if (response.statusCode == 401 && retryAuth && await _refreshAccess()) {
        _requireRevision(target.revision);
        return await getPrivateBytes(path,
            retryAuth: false, expectedRevision: target.revision);
      }
      _requireRevision(target.revision);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _decode(response);
      }
      return response.bodyBytes;
    } on ApiException {
      rethrow;
    } catch (error) {
      _networkError(error);
    }
  }

  static Future<Map<String, dynamic>> uploadUpiProfile(
          String filePath, Map<String, String> fields) =>
      _upload('payments/driver/profile/', filePath: filePath, fields: fields);

  static Future<Map<String, dynamic>> requestLoginOtp(String email) =>
      _send('POST', 'auth/login/otp/', auth: false, body: {'email': email});

  // ------------------------------------------------------------------- auth

  static Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    required String confirmPassword,
    required String role,
    String referralCode = '',
  }) =>
      _send('POST', 'auth/register/', auth: false, body: {
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'password': password,
        'confirm_password': confirmPassword,
        if (referralCode.isNotEmpty) 'referral_code': referralCode,
        'role': role,
      });

  static Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
    required String role,
  }) =>
      _send('POST', 'auth/login/', auth: false, body: {
        'identifier': identifier,
        'password': password,
        'role': role,
      });

  static Future<Map<String, dynamic>> verifyOtp(String email, String otp) =>
      _send('POST', 'auth/verify-otp/',
          auth: false, body: {'email': email, 'otp': otp});

  static Future<Map<String, dynamic>> resendOtp(String email) =>
      _send('POST', 'auth/resend-otp/', auth: false, body: {'email': email});

  static Future<Map<String, dynamic>> requestPasswordReset(String email) =>
      _send('POST', 'auth/password/reset/request/',
          auth: false, body: {'email': email});

  static Future<Map<String, dynamic>> confirmPasswordReset(
          String email, String otp, String newPassword) =>
      _send('POST', 'auth/password/reset/confirm/',
          auth: false,
          body: {'email': email, 'otp': otp, 'new_password': newPassword});

  // ------------------------------------------------------- generic helpers
  // Public wrappers so other services (rides, notifications) reuse the same
  // base-address fallback, auth headers and error messages.

  static Future<Map<String, dynamic>> getJson(String path) =>
      _send('GET', path);

  static Future<Map<String, dynamic>> postJson(String path,
          [Map<String, dynamic>? body]) =>
      _send('POST', path, body: body);

  static Future<Map<String, dynamic>> putJson(String path,
          [Map<String, dynamic>? body]) =>
      _send('PUT', path, body: body);

  static Future<Map<String, dynamic>> deleteJson(String path) =>
      _send('DELETE', path);

  static Future<Map<String, dynamic>> me() => _send('GET', 'auth/me/');

  // ---------------------------------------------------------------- profile

  static Future<Map<String, dynamic>> getProfile() =>
      _send('GET', 'auth/profile/');

  /// [step] may be `PERSONAL` or `DRIVING` (driver steps) or `PROFILE`
  /// (customer). The server refuses to move on when a step is incomplete.
  static Future<Map<String, dynamic>> saveProfile(Map<String, dynamic> data,
          {String? step}) =>
      _send('PUT', 'auth/profile/', body: {
        ...data,
        if (step != null) 'step': step,
      });

  static Future<Map<String, dynamic>> uploadProfilePhoto(String path) =>
      _upload('auth/profile/photo/', filePath: path);

  static Future<Map<String, dynamic>> uploadDriverDocument({
    required String path,
    required String documentType,
    String? documentNumber,
    String? expiresAt,
  }) =>
      _upload('auth/driver/documents/', filePath: path, fields: {
        'document_type': documentType,
        if (documentNumber != null && documentNumber.isNotEmpty)
          'document_number': documentNumber,
        if (expiresAt != null && expiresAt.isNotEmpty) 'expires_at': expiresAt,
      });

  // ------------------------------------------------------- driver application

  static Future<Map<String, dynamic>> driverApplication() =>
      _send('GET', 'auth/driver/application/');

  // ------------------------------------------------------------------ admin
  // The admin queue in the app talks to the same endpoints the Django panel
  // uses, so verification really works from the phone.

  static Future<Map<String, dynamic>> adminDrivers(
      {String status = '', String search = ''}) {
    final query = <String>[];
    if (status.isNotEmpty) query.add('status=$status');
    if (search.trim().isNotEmpty) {
      query.add('search=${Uri.encodeQueryComponent(search.trim())}');
    }
    final suffix = query.isEmpty ? '' : '?${query.join('&')}';
    return _send('GET', 'auth/admin/drivers/$suffix');
  }

  static Future<Map<String, dynamic>> adminDriverApplication(int userId) =>
      _send('GET', 'auth/admin/drivers/$userId/application/');

  /// [action] is one of: approve | reject | suspend | reinstate | mark_under_review
  static Future<Map<String, dynamic>> adminReviewDriver(
          int userId, String action, {String reason = ''}) =>
      _send('POST', 'auth/admin/drivers/$userId/review/',
          body: {'action': action, 'reason': reason});

  static Future<Map<String, dynamic>> adminReviewDocument(
          int documentId, String action, {String reason = ''}) =>
      _send('POST', 'auth/admin/documents/$documentId/review/',
          body: {'action': action, 'reason': reason});

  static Future<Map<String, dynamic>> saveConsents() =>
      _send('POST', 'auth/driver/consents/', body: {
        'consent_background_check': true,
        'consent_terms': true,
        'consent_data_accuracy': true,
      });

  static Future<Map<String, dynamic>> training() =>
      _send('GET', 'auth/driver/training/');

  static Future<Map<String, dynamic>> completeTraining(String module) =>
      _send('POST', 'auth/driver/training/$module/complete/');

  static Future<Map<String, dynamic>> emergencyContacts() =>
      _send('GET', 'auth/driver/emergency-contacts/');

  static Future<Map<String, dynamic>> addEmergencyContact({
    required String name,
    required String phone,
    String relationship = '',
  }) =>
      _send('POST', 'auth/driver/emergency-contacts/',
          body: {'name': name, 'phone': phone, 'relationship': relationship});

  static Future<Map<String, dynamic>> deleteEmergencyContact(int id) =>
      _send('DELETE', 'auth/driver/emergency-contacts/$id/');
}
