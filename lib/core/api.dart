import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default server; override with `--dart-define=API_BASE=https://host` or on the sign-in screen.
const kDefaultApiBase = String.fromEnvironment('API_BASE', defaultValue: 'https://dev-hotel4.hasuite.ai');

/// Workspace opened for accounts that cannot list workspaces; `--dart-define=TENANT_ID=1`.
const kDefaultTenantId = int.fromEnvironment('TENANT_ID');

/// Largest attachment the app will send.
const kMaxUploadBytes = 25 * 1024 * 1024;

class ApiException implements Exception {
  ApiException(this.status, this.message, [this.errors]);
  final int status;
  final String message;
  final Object? errors;
  @override
  String toString() => message;
}

/// A user-facing sentence for any failure, so network problems are not confused with server errors.
String friendlyError(Object e) => switch (e) {
  ApiException() => e.message,
  TimeoutException() => 'The server took too long to respond. Try again.',
  http.ClientException() => 'Could not reach the server. Check your connection.',
  _ => 'Something went wrong. Try again.',
};

class Page<T> {
  Page(this.items, this.nextCursor);
  final List<T> items;
  final int? nextCursor;
}

/// Thin HTTP client for the HA Suite backend.
///
/// * System endpoints (`/api/system/v1/...`) wrap payloads in `{data: ...}`.
/// * ReqGuest endpoints (`/api/reqguest/v1/...`) return raw objects/arrays,
///   except cursor-paged lists which return `{data: [...], meta: {next_cursor}}`.
class ApiClient {
  ApiClient._(this._prefs, this._accessToken, this._refreshToken);

  static const _secure = FlutterSecureStorage();

  /// Tokens live in the platform keystore; older installs kept them in plain
  /// preferences, so those are moved across once and then removed.
  static Future<ApiClient> create() async {
    final prefs = await SharedPreferences.getInstance();
    String? access, refresh;
    try {
      access = await _secure.read(key: 'access_token');
      refresh = await _secure.read(key: 'refresh_token');
    } catch (_) {}
    final oldAccess = prefs.getString('access_token');
    if (oldAccess != null) {
      access ??= oldAccess;
      refresh ??= prefs.getString('refresh_token');
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      final client = ApiClient._(prefs, access, refresh);
      await client._persistTokens();
      return client;
    }
    return ApiClient._(prefs, access, refresh);
  }

  final SharedPreferences _prefs;
  final _http = http.Client();
  String? _accessToken, _refreshToken;
  Future<bool>? _refreshing;

  /// Called when the session can no longer be refreshed.
  void Function()? onUnauthorized;

  String get baseUrl => _prefs.getString('api_base') ?? kDefaultApiBase;
  set baseUrl(String v) {
    final clean = v.trim().replaceAll(RegExp(r'/+$'), '');
    clean.isEmpty || clean == kDefaultApiBase ? _prefs.remove('api_base') : _prefs.setString('api_base', clean);
  }

  String? get accessToken => _accessToken;
  int? get tenantId => _prefs.getInt('tenant_id');
  set tenantId(int? v) => v == null ? _prefs.remove('tenant_id') : _prefs.setInt('tenant_id', v);

  bool get hasSession => _accessToken != null;

  // ── Auth ───────────────────────────────────────────────────────────────────

  /// Signs in against [server] without saving it; the address is kept only once sign-in works.
  Future<Map<String, dynamic>> login(String email, String password, {String? server}) async {
    final res = await _send(
      'POST',
      '/system/v1/auth/login',
      body: {'provider': 'email', 'provider_uid': email, 'password': password},
      auth: false,
      base: server,
    );
    final data = (res as Map)['data'] as Map<String, dynamic>;
    if (server != null) baseUrl = server;
    await _storeTokens(data);
    return data;
  }

  Future<void> logout() async {
    try {
      await _send('POST', '/system/v1/auth/logout', retry: false);
    } catch (_) {}
    await clearSession();
  }

  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    await _persistTokens();
    await _prefs.remove('tenant_id');
  }

  Future<Map<String, dynamic>> me() async =>
      ((await _send('GET', '/system/v1/auth/me')) as Map)['data'] as Map<String, dynamic>;

  /// All system users (page-numbered). Used to resolve names for user ids.
  Future<List<Map<String, dynamic>>> users() async {
    final out = <Map<String, dynamic>>[];
    for (var page = 1; page < 50; page++) {
      final res = await _send('GET', '/system/v1/users', query: {'page': '$page', 'per_page': '100'}) as Map;
      out.addAll(((res['data'] as List?) ?? const []).cast<Map<String, dynamic>>());
      final totalPages = ((res['meta'] as Map?)?['total_pages'] as num?)?.toInt() ?? 1;
      if (page >= totalPages) break;
    }
    return out;
  }

  Future<void> _storeTokens(Map data) async {
    _accessToken = data['access_token'] as String;
    if (data['refresh_token'] != null) _refreshToken = data['refresh_token'] as String;
    await _persistTokens();
  }

  Future<void> _persistTokens() async {
    try {
      for (final (k, v) in [('access_token', _accessToken), ('refresh_token', _refreshToken)]) {
        v == null ? await _secure.delete(key: k) : await _secure.write(key: k, value: v);
      }
    } catch (_) {
      // Keystore unavailable (rare); the session still works until the app restarts.
    }
  }

  /// One refresh at a time. The shared future is cleared when it settles, so a
  /// failed attempt never blocks later ones.
  Future<bool> _refresh() {
    final pending = _refreshing;
    if (pending != null) return pending;
    final rt = _refreshToken;
    if (rt == null) return Future.value(false);
    final f = () async {
      try {
        final res = await _send('POST', '/system/v1/auth/refresh', body: {'refresh_token': rt}, auth: false);
        await _storeTokens((res as Map)['data'] as Map);
        return true;
      } catch (_) {
        return false;
      }
    }();
    _refreshing = f;
    f.whenComplete(() => _refreshing = null);
    return f;
  }

  // ── ReqGuest ───────────────────────────────────────────────────────────────

  Future<dynamic> rg(String method, String path, {Map<String, String>? query, Object? body}) =>
      _send(method, '/reqguest/v1$path', query: query, body: body, tenant: true);

  Future<List<Map<String, dynamic>>> rgList(String path, {Map<String, String>? query}) async {
    final res = await rg('GET', path, query: query);
    final list = res is Map ? res['data'] : res;
    return ((list as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// Walks every page of a cursor-paged ReqGuest list.
  Future<List<Map<String, dynamic>>> rgAll(String path, {Map<String, String>? query}) async {
    final out = <Map<String, dynamic>>[];
    int? cursor;
    for (var i = 0; i < 50; i++) {
      final q = {...?query, 'per_page': '100', if (cursor != null) 'cursor': '$cursor'};
      final res = await rg('GET', path, query: q);
      if (res is List) return res.cast<Map<String, dynamic>>();
      out.addAll(((res['data'] as List?) ?? const []).cast<Map<String, dynamic>>());
      cursor = ((res['meta'] as Map?)?['next_cursor'] as num?)?.toInt();
      if (cursor == null) break;
    }
    return out;
  }

  Future<void> uploadAttachment(int requestId, List<int> bytes, String filename, String mime) async {
    if (bytes.length > kMaxUploadBytes) {
      throw ApiException(413, 'This file is too large. The limit is ${kMaxUploadBytes ~/ (1024 * 1024)} MB.');
    }
    Future<http.StreamedResponse> go() {
      final req = http.MultipartRequest('POST', _uri('/reqguest/v1/requests/$requestId/attachments'))
        ..headers.addAll(_headers(auth: true, tenant: true, json: false))
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: _mediaType(mime)));
      return _http.send(req).timeout(const Duration(minutes: 3));
    }

    var streamed = await go();
    if (streamed.statusCode == 401) {
      if (await _refresh()) {
        streamed = await go();
      } else {
        await clearSession();
        onUnauthorized?.call();
      }
    }
    // The body is not needed; a 2xx reply of any shape means the file was stored.
    _decode(await http.Response.fromStream(streamed));
  }

  // ── Plumbing ───────────────────────────────────────────────────────────────

  Uri _uri(String path, [Map<String, String>? query, String? base]) =>
      Uri.parse('${base ?? baseUrl}/api$path').replace(queryParameters: query?.isEmpty ?? true ? null : query);

  Map<String, String> _headers({required bool auth, bool tenant = false, bool json = true}) => {
    'Accept': 'application/json',
    if (json) 'Content-Type': 'application/json',
    if (auth && _accessToken != null) 'Authorization': 'Bearer $_accessToken',
    if (tenant && tenantId != null) 'X-Tenant-Id': '$tenantId',
  };

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool auth = true,
    bool tenant = false,
    bool retry = true,
    String? base,
  }) async {
    final req = http.Request(method, _uri(path, query, base))..headers.addAll(_headers(auth: auth, tenant: tenant));
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 30)));
    if (res.statusCode == 401 && auth && retry) {
      if (await _refresh()) {
        return _send(method, path, query: query, body: body, auth: auth, tenant: tenant, retry: false);
      }
      await clearSession();
      onUnauthorized?.call();
    }
    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    final text = utf8.decode(res.bodyBytes);
    final dynamic json = text.isEmpty ? null : _tryJson(text);
    if (res.statusCode >= 200 && res.statusCode < 300) return json;
    final msg = json is Map && json['message'] is String ? json['message'] as String : _statusMessage(res.statusCode);
    throw ApiException(res.statusCode, msg, json is Map ? json['errors'] : null);
  }

  String _statusMessage(int code) => switch (code) {
    413 => 'This file is too large for the server.',
    >= 500 => 'The server had a problem (error $code). Try again shortly.',
    _ => 'Request failed (error $code).',
  };

  dynamic _tryJson(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return s;
    }
  }
}

MediaType? _mediaType(String mime) {
  final parts = mime.split('/');
  return parts.length == 2 ? MediaType(parts[0], parts[1]) : null;
}
