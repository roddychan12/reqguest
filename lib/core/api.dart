import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default server; override with `--dart-define=API_BASE=https://host` or on the sign-in screen.
const kDefaultApiBase = String.fromEnvironment('API_BASE', defaultValue: 'https://dev-hotel4.hasuite.ai');

/// Workspace opened for accounts that cannot list workspaces; `--dart-define=TENANT_ID=1`.
const kDefaultTenantId = int.fromEnvironment('TENANT_ID');

class ApiException implements Exception {
  ApiException(this.status, this.message, [this.errors]);
  final int status;
  final String message;
  final Object? errors;
  @override
  String toString() => message;
}

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
  ApiClient._(this._prefs);

  static Future<ApiClient> create() async => ApiClient._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;
  final _http = http.Client();
  Future<bool>? _refreshing;

  /// Called when the session can no longer be refreshed.
  void Function()? onUnauthorized;

  String get baseUrl => _prefs.getString('api_base') ?? kDefaultApiBase;
  set baseUrl(String v) => _prefs.setString('api_base', v.trim().replaceAll(RegExp(r'/+$'), ''));

  String? get accessToken => _prefs.getString('access_token');
  String? get _refreshToken => _prefs.getString('refresh_token');
  int? get tenantId => _prefs.getInt('tenant_id');
  set tenantId(int? v) => v == null ? _prefs.remove('tenant_id') : _prefs.setInt('tenant_id', v);

  bool get hasSession => accessToken != null;

  // ── Auth ───────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await _send('POST', '/system/v1/auth/login',
        body: {'provider': 'email', 'provider_uid': email, 'password': password}, auth: false);
    final data = (res as Map)['data'] as Map<String, dynamic>;
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
    await _prefs.remove('access_token');
    await _prefs.remove('refresh_token');
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
    await _prefs.setString('access_token', data['access_token'] as String);
    if (data['refresh_token'] != null) await _prefs.setString('refresh_token', data['refresh_token'] as String);
  }

  Future<bool> _refresh() {
    return _refreshing ??= () async {
      try {
        final rt = _refreshToken;
        if (rt == null) return false;
        final res = await _send('POST', '/system/v1/auth/refresh', body: {'refresh_token': rt}, auth: false);
        await _storeTokens((res as Map)['data'] as Map);
        return true;
      } catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    }();
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

  Future<Map<String, dynamic>> uploadAttachment(int requestId, List<int> bytes, String filename, String mime) async {
    Future<http.StreamedResponse> go() {
      final req = http.MultipartRequest('POST', _uri('/reqguest/v1/requests/$requestId/attachments'))
        ..headers.addAll(_headers(auth: true, tenant: true, json: false))
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: _mediaType(mime)));
      return _http.send(req);
    }

    var streamed = await go();
    if (streamed.statusCode == 401 && await _refresh()) streamed = await go();
    final res = await http.Response.fromStream(streamed);
    return _decode(res) as Map<String, dynamic>;
  }

  // ── Plumbing ───────────────────────────────────────────────────────────────

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl/api$path').replace(queryParameters: query?.isEmpty ?? true ? null : query);

  Map<String, String> _headers({required bool auth, bool tenant = false, bool json = true}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (auth && accessToken != null) 'Authorization': 'Bearer $accessToken',
        if (tenant && tenantId != null) 'X-Tenant-Id': '$tenantId',
      };

  Future<dynamic> _send(String method, String path,
      {Map<String, String>? query, Object? body, bool auth = true, bool tenant = false, bool retry = true}) async {
    final req = http.Request(method, _uri(path, query))..headers.addAll(_headers(auth: auth, tenant: tenant));
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
    final msg = json is Map && json['message'] is String ? json['message'] as String : 'Request failed (${res.statusCode})';
    throw ApiException(res.statusCode, msg, json is Map ? json['errors'] : null);
  }

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
