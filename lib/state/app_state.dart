import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/mapping.dart';
import '../models/models.dart';

enum Phase { booting, signedOut, pickTenant, loading, ready, error }

enum ListFilter { all, unread, mine, high }

/// A notification derived from a chat event on a visible request.
class Alert {
  Alert(this.req, this.event);
  final Req req;
  final ChatEvent event;
  String get key => '${req.id}/${event.key}';
}

/// Single source of truth for the signed-in session, lookups and request chats.
class AppState extends ChangeNotifier {
  AppState(this.api, this._prefs) {
    api.onUnauthorized = () {
      _stopPolling();
      phase = Phase.signedOut;
      notifyListeners();
    };
  }

  static Future<AppState> create() async {
    final s = AppState(await ApiClient.create(), await SharedPreferences.getInstance());
    unawaited(s.boot());
    return s;
  }

  final ApiClient api;
  final SharedPreferences _prefs;

  Phase phase = Phase.booting;
  String? error;

  Me? me;
  Tenant? tenant;
  List<Tenant> tenants = [];

  final Map<int, Department> departments = {};
  final Map<int, String> userNames = {};
  final Map<int, WfStatus> statuses = {};
  final List<WfTransition> transitions = [];
  final Map<int, RequestType> types = {};
  List<Staff> staff = [];

  /// Every tenant request, and the chat events loaded for each.
  final Map<int, Req> _all = {};
  final Map<int, List<ChatEvent>> events = {};
  final Map<int, List<Assignment>> assignments = {};
  final Set<int> _loadedEvents = {};

  /// Called with a newly arrived request so the UI can show a top toast.
  void Function(Req)? onIncoming;

  Timer? _poll;
  bool _polling = false;

  // ── Settings (persisted per device) ────────────────────────────────────────

  bool get onShift => _prefs.getBool('on_shift') ?? true;
  set onShift(bool v) => _setBool('on_shift', v);
  bool get alertSound => _prefs.getBool('alert_sound') ?? true;
  set alertSound(bool v) => _setBool('alert_sound', v);
  bool get showInternal => _prefs.getBool('show_internal') ?? true;
  set showInternal(bool v) => _setBool('show_internal', v);

  ThemeMode get themeMode => ThemeMode.values[_prefs.getInt('theme_mode') ?? 0];
  set themeMode(ThemeMode m) {
    _prefs.setInt('theme_mode', m.index);
    notifyListeners();
  }

  void _setBool(String k, bool v) {
    _prefs.setBool(k, v);
    notifyListeners();
  }

  // ── Boot / auth ────────────────────────────────────────────────────────────

  Future<void> boot() async {
    if (!api.hasSession) {
      phase = Phase.signedOut;
      notifyListeners();
      return;
    }
    await _afterLogin();
  }

  Future<void> signIn(String server, String email, String password) async {
    api.baseUrl = server;
    await api.login(email, password);
    await _afterLogin();
  }

  Future<void> signOut() async {
    _stopPolling();
    await api.logout();
    _reset();
    phase = Phase.signedOut;
    notifyListeners();
  }

  Future<void> _afterLogin() async {
    try {
      phase = Phase.loading;
      notifyListeners();
      final meJson = await api.me();
      tenantsForbidden = false;
      try {
        tenants = (await api.rgList('/tenants')).map(Tenant.fromJson).toList();
      } on ApiException catch (e) {
        // Staff accounts may not hold tenant.index; they open a known workspace by id instead.
        if (e.status != 403) rethrow;
        tenants = [];
        tenantsForbidden = true;
      }
      me = Me(
        userId: (meJson['id'] as num).toInt(),
        name: '${meJson['name'] ?? meJson['uid'] ?? 'Me'}',
        email: _emailOf(meJson),
        phone: meJson['phone']?.toString(),
        timezone: meJson['timezone']?.toString(),
        role: AppRole.staff,
      );
      _meJson = meJson;
      final saved = api.tenantId ?? (kDefaultTenantId > 0 ? kDefaultTenantId : null);
      final match = tenants.where((t) => t.id == saved);
      if (match.isNotEmpty) {
        await selectTenant(match.first);
      } else if (tenantsForbidden && saved != null) {
        await openTenantById(saved);
      } else if (tenants.length == 1) {
        await selectTenant(tenants.first);
      } else if (tenants.isEmpty && !tenantsForbidden) {
        throw ApiException(403, 'No workspace is set up on this server yet.');
      } else {
        phase = Phase.pickTenant;
        notifyListeners();
      }
    } on ApiException catch (e) {
      if (e.status == 401) {
        phase = Phase.signedOut;
      } else {
        error = e.message;
        phase = Phase.error;
      }
      notifyListeners();
    } catch (e) {
      error = 'Could not reach the server. Check the connection and try again.';
      phase = Phase.error;
      notifyListeners();
    }
  }

  Map<String, dynamic> _meJson = const {};

  String? _emailOf(Map<String, dynamic> j) {
    final v = j['email'] ?? j['uid'];
    return v != null && '$v'.contains('@') ? '$v' : null;
  }

  Future<void> retry() => api.hasSession ? _afterLogin() : boot();

  /// True when the account may not list workspaces (no `tenant.index` permission).
  bool tenantsForbidden = false;

  /// Opens a workspace the user cannot list, looking up its name when allowed.
  Future<void> openTenantById(int id) async {
    Tenant t = Tenant(id, 'Workspace $id', '', null);
    try {
      final j = await api.rg('GET', '/tenants/$id');
      if (j is Map<String, dynamic>) t = Tenant.fromJson(j);
    } catch (_) {}
    await selectTenant(t);
  }

  Future<void> selectTenant(Tenant t) async {
    _stopPolling();
    _reset(keepSession: true);
    tenant = t;
    api.tenantId = t.id;
    phase = Phase.loading;
    notifyListeners();
    try {
      await _loadLookups();
      await _loadRequests(initial: true);
      phase = Phase.ready;
      notifyListeners();
      _startPolling();
    } on ApiException catch (e) {
      error = switch (e.status) {
        403 => 'Your account is not allowed to view requests in ${t.name}. '
            'Ask an administrator to give your role ReqGuest request access.',
        404 => 'Workspace ${t.id} was not found on this server.',
        _ => e.message,
      };
      phase = Phase.error;
      notifyListeners();
    }
  }

  int get totalRequests => _all.length;

  /// Runs a lookup that the account may not be allowed to read; returns [] when forbidden.
  Future<List<Map<String, dynamic>>> _optional(Future<List<Map<String, dynamic>>> f) async {
    try {
      return await f;
    } on ApiException catch (e) {
      if (e.status == 403 || e.status == 404) return [];
      rethrow;
    }
  }

  void switchWorkspace() {
    _stopPolling();
    phase = Phase.pickTenant;
    notifyListeners();
  }

  void _reset({bool keepSession = false}) {
    departments.clear();
    userNames.clear();
    statuses.clear();
    transitions.clear();
    types.clear();
    staff = [];
    _all.clear();
    events.clear();
    assignments.clear();
    _loadedEvents.clear();
    if (!keepSession) {
      me = null;
      tenant = null;
      tenants = [];
    }
  }

  Future<void> _loadLookups() async {
    final results = await Future.wait([
      _optional(api.rgList('/departments')),
      _optional(api.rgList('/workflows')),
      _optional(api.rgList('/request-types')),
      _optional(api.rgAll('/staff')),
      _optional(api.users()),
    ]);
    _applyTeam(results[0], results[3], results[4]);
    for (final t in results[2].map(RequestType.fromJson)) {
      types[t.id] = t;
    }
    // Workflow detail includes statuses + transitions.
    final wfs = await Future.wait(results[1].map((w) async {
      try {
        return await api.rg('GET', '/workflows/${w['id']}');
      } on ApiException {
        return null;
      }
    }));
    for (final w in wfs.whereType<Map<String, dynamic>>()) {
      for (final s in ((w['statuses'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
        final st = WfStatus.fromJson(s);
        statuses[st.id] = st;
      }
      transitions.addAll(((w['transitions'] as List?) ?? const []).cast<Map<String, dynamic>>().map(WfTransition.fromJson));
    }
    _resolveRole();
  }

  void _applyTeam(List<Map<String, dynamic>> depts, List<Map<String, dynamic>> staffRows, List<Map<String, dynamic>> users) {
    departments.clear();
    for (final d in depts.map(Department.fromJson)) {
      departments[d.id] = d;
    }
    staff = staffRows.map(Staff.fromJson).toList();
    userNames.clear();
    for (final u in users) {
      final id = (u['id'] as num?)?.toInt();
      if (id != null) userNames[id] = '${u['name'] ?? u['uid'] ?? 'User $id'}';
    }
  }

  /// Reloads departments, staff and names (changed in the CMS) along with requests.
  Future<void> refreshTeam() async {
    final results = await Future.wait([
      _optional(api.rgList('/departments')),
      _optional(api.rgAll('/staff')),
      _optional(api.users()),
    ]);
    _applyTeam(results[0], results[1], results[2]);
    _resolveRole();
    await _loadRequests();
  }

  void _resolveRole() {
    final m = me!;
    m.staff = staff.where((s) => s.userId == m.userId).firstOrNull;
    userNames.putIfAbsent(m.userId, () => m.name);
    if (_meJson['is_superuser'] == true || _meJson['is_superuser'] == 1) {
      m.role = AppRole.admin;
      return;
    }
    final roles = ((_meJson['roles'] as List?) ?? const []).cast<Map>();
    Map? role;
    if (m.staff?.systemRoleId != null) {
      role = roles.where((r) => (r['id'] as num?)?.toInt() == m.staff!.systemRoleId).firstOrNull;
    }
    final names = (role != null ? [role] : roles)
        .map((r) => '${r['name'] ?? ''} ${r['display_name'] ?? ''}'.toLowerCase())
        .join(' ');
    if (role?['is_superuser'] == 1 || names.contains('admin')) {
      m.role = AppRole.admin;
    } else if (names.contains('supervisor') || names.contains('manager')) {
      m.role = AppRole.supervisor;
    } else {
      m.role = AppRole.staff;
    }
  }

  // ── Requests & events ──────────────────────────────────────────────────────

  Future<void> refresh() => _loadRequests();

  Future<void> _loadRequests({bool initial = false}) async {
    final rows = (await api.rgAll('/requests')).map(Req.fromJson).toList();
    final changed = <int>[];
    final arrived = <Req>[];
    for (final r in rows) {
      final prev = _all[r.id];
      if (prev == null) {
        if (!initial) arrived.add(r);
        changed.add(r.id);
      } else if (prev.updatedAt != r.updatedAt || prev.currentStatusId != r.currentStatusId || !isFinal(r)) {
        // Comments do not bump updated_at, so open chats are always refreshed.
        changed.add(r.id);
      }
      _all[r.id] = r;
    }
    _all.removeWhere((id, _) => !rows.any((r) => r.id == id));
    await _loadEventsFor(changed);
    notifyListeners();
    for (final r in arrived) {
      if (isVisible(r) && onIncoming != null) onIncoming!(r);
    }
  }

  Future<void> _loadEventsFor(List<int> ids) async {
    const batch = 6;
    for (var i = 0; i < ids.length; i += batch) {
      await Future.wait(ids.skip(i).take(batch).map(loadEvents));
    }
  }

  /// Loads status history, assignments, comments and attachments for one request.
  Future<void> loadEvents(int id) async {
    try {
      final r = await Future.wait([
        api.rgList('/requests/$id/status-history'),
        api.rgList('/requests/$id/assignments'),
        api.rgList('/requests/$id/comments'),
        api.rgList('/requests/$id/attachments'),
      ]);
      final list = <ChatEvent>[
        ...r[0].map(ChatEvent.fromHistory),
        ...r[1].map(ChatEvent.fromAssignment),
        ...r[2].map((j) => ChatEvent.fromComment(j)),
        ...r[3].map(ChatEvent.fromAttachment),
      ];
      // Requests created without a status still need a guest card.
      final req = _all[id];
      if (req != null && !list.any((e) => e.kind == EventKind.guest)) {
        list.add(ChatEvent(kind: EventKind.guest, id: 0, at: req.createdAt, by: req.createdBy));
      }
      list.sort(ChatEvent.compare);
      events[id] = list;
      assignments[id] = r[1].map(Assignment.fromJson).toList();
      _loadedEvents.add(id);
    } on ApiException {
      // Keep whatever we had; the next poll retries.
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (_polling || phase != Phase.ready) return;
      _polling = true;
      try {
        await _loadRequests();
      } catch (_) {
      } finally {
        _polling = false;
      }
    });
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  // ── Derived data ───────────────────────────────────────────────────────────

  WfStatus? statusOf(Req r) => r.currentStatusId == null ? null : statuses[r.currentStatusId];
  bool isFinal(Req r) => statusOf(r)?.isFinal ?? (r.closedAt != null);

  Assignment? activeAssignment(int reqId) =>
      (assignments[reqId] ?? const []).where((a) => a.unassignedAt == null && a.userId != null).lastOrNull;

  int? assigneeOf(int reqId) => activeAssignment(reqId)?.userId;

  bool isVisible(Req r) {
    final m = me;
    if (m == null) return false;
    switch (m.role) {
      case AppRole.admin:
        return true;
      case AppRole.supervisor:
        final d = m.departmentId;
        if (d == null) return true;
        return r.departmentId == d ||
            (assignments[r.id] ?? const []).any((a) => a.unassignedAt == null && a.deptId == d);
      case AppRole.staff:
        final who = assigneeOf(r.id);
        // Own requests, plus unassigned ones in their department so they can pick them up.
        return who == m.userId || (who == null && m.departmentId != null && r.departmentId == m.departmentId);
    }
  }

  List<Req> get visible => _all.values.where(isVisible).toList();

  DateTime lastEventAt(Req r) => (events[r.id]?.lastOrNull?.at) ?? r.updatedAt ?? r.createdAt;

  List<Req> sorted(Iterable<Req> list) => list.toList()..sort((a, b) => lastEventAt(b).compareTo(lastEventAt(a)));

  List<Req> get openChats => sorted(visible.where((r) => !isFinal(r)));
  List<Req> get closedChats => sorted(visible.where(isFinal));

  List<ChatEvent> eventsFor(int id) {
    final list = events[id] ?? const [];
    if (showInternal) return list;
    return list.where((e) => !(e.kind == EventKind.comment && e.isInternal)).toList();
  }

  bool eventsLoaded(int id) => _loadedEvents.contains(id);

  String nameOf(int? userId) {
    if (userId == null) return 'System';
    if (userId == me?.userId) return me!.name;
    return userNames[userId] ?? 'User $userId';
  }

  String whoOf(int? userId, {bool short = true}) {
    if (userId != null && userId == me?.userId) return 'You';
    final n = nameOf(userId);
    return short ? shortName(n) : n;
  }

  /// Download address for an attachment. Media uploads store a full URL; direct
  /// uploads store a path relative to the server. Plain http is upgraded when the
  /// API itself is https (the server redirects anyway, and Android blocks cleartext).
  String? attachmentUrl(ChatEvent e) {
    final p = e.filePath?.trim();
    if (p == null || p.isEmpty) return null;
    if (p.startsWith('http://') || p.startsWith('https://')) {
      return api.baseUrl.startsWith('https://') ? p.replaceFirst('http://', 'https://') : p;
    }
    return '${api.baseUrl}${p.startsWith('/') ? '' : '/'}$p';
  }

  Department? deptOfUser(int? userId) {
    final s = staff.where((s) => s.userId == userId).firstOrNull;
    return s?.departmentId == null ? null : departments[s!.departmentId];
  }

  List<WfTransition> transitionsFor(Req r) =>
      transitions.where((t) => t.workflowId == r.workflowId && t.fromStatusId == r.currentStatusId).toList();

  // ── Unread ─────────────────────────────────────────────────────────────────

  DateTime? _seenAt(int reqId) {
    final ms = _prefs.getInt('seen_${tenant?.id}_$reqId');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  int unreadCount(Req r) {
    final seen = _seenAt(r.id);
    final list = events[r.id] ?? const [];
    if (seen == null) {
      // Never opened: everything since creation counts, capped for sanity.
      return list.where((e) => e.by != me?.userId).length.clamp(0, 99);
    }
    return list.where((e) => e.at.isAfter(seen) && e.by != me?.userId).length;
  }

  void markSeen(Req r) {
    final last = lastEventAt(r);
    final now = DateTime.now();
    final at = last.isAfter(now) ? last : now;
    _prefs.setInt('seen_${tenant?.id}_${r.id}', at.millisecondsSinceEpoch);
    notifyListeners();
  }

  int get unreadChats => openChats.where((r) => unreadCount(r) > 0).length;

  // ── Alerts ─────────────────────────────────────────────────────────────────

  DateTime? get _alertsReadAt {
    final ms = _prefs.getInt('alerts_read_${tenant?.id}');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Set<String> get _readAlerts => (_prefs.getStringList('alerts_keys_${tenant?.id}') ?? const []).toSet();

  List<Alert> get alerts {
    final out = <Alert>[];
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    for (final r in visible) {
      for (final e in eventsFor(r.id)) {
        if (e.at.isBefore(cutoff)) continue;
        if (e.by == me?.userId && e.kind != EventKind.assign) continue;
        out.add(Alert(r, e));
      }
    }
    out.sort((a, b) => b.event.at.compareTo(a.event.at));
    return out.take(200).toList();
  }

  bool isAlertUnread(Alert a) {
    final readAt = _alertsReadAt;
    if (readAt != null && !a.event.at.isAfter(readAt)) return false;
    return !_readAlerts.contains(a.key);
  }

  int get unreadAlerts => alerts.where(isAlertUnread).length;

  void markAlertRead(Alert a) {
    final s = _readAlerts..add(a.key);
    _prefs.setStringList('alerts_keys_${tenant?.id}', s.take(500).toList());
    notifyListeners();
  }

  void markAllAlertsRead() {
    _prefs.setInt('alerts_read_${tenant?.id}', DateTime.now().millisecondsSinceEpoch);
    _prefs.remove('alerts_keys_${tenant?.id}');
    notifyListeners();
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  Req? byId(int id) => _all[id];

  Future<void> applyTransition(Req r, WfTransition t, {String? note}) async {
    final res = await api.rg('POST', '/requests/${r.id}/transition', body: {
      'transition_id': t.id,
      'note': ?note,
    });
    r.currentStatusId = (res is Map ? (res['current_status_id'] as num?)?.toInt() : null) ?? t.toStatusId;
    await _refreshOne(r.id);
  }

  /// Undo a transition by taking the reverse edge, if the workflow defines one.
  WfTransition? reverseOf(Req r, WfTransition t) => transitions
      .where((x) => x.workflowId == t.workflowId && x.fromStatusId == t.toStatusId && x.toStatusId == t.fromStatusId)
      .firstOrNull;

  /// Falls back to setting the status directly when no reverse edge exists.
  Future<void> undoTransition(Req r, WfTransition t) async {
    final rev = reverseOf(r, t);
    if (rev != null) {
      await applyTransition(r, rev, note: 'Undone');
    } else {
      await api.rg('PUT', '/requests/${r.id}', body: {'current_status_id': t.fromStatusId, 'closed_at': null});
      r.currentStatusId = t.fromStatusId;
      await _refreshOne(r.id);
    }
  }

  Future<void> sendComment(Req r, String body, {required bool internal}) async {
    final optimistic = ChatEvent.fromComment(
        {'user_id': me?.userId, 'body': body, 'is_internal': internal ? 1 : 0}, pending: true);
    events[r.id] = [...?events[r.id], optimistic];
    notifyListeners();
    try {
      await api.rg('POST', '/requests/${r.id}/comments', body: {'body': body, 'is_internal': internal ? 1 : 0});
    } finally {
      await loadEvents(r.id);
      markSeen(r);
    }
  }

  Future<void> uploadAttachment(Req r, List<int> bytes, String name, String mime) async {
    await api.uploadAttachment(r.id, bytes, name, mime);
    await loadEvents(r.id);
    markSeen(r);
  }

  Future<void> pick(Req r) async {
    await api.rg('POST', '/requests/${r.id}/pick');
    await loadEvents(r.id);
    notifyListeners();
  }

  Future<void> _refreshOne(int id) async {
    try {
      final j = await api.rg('GET', '/requests/$id');
      if (j is Map<String, dynamic>) _all[id] = Req.fromJson(j);
    } catch (_) {}
    await loadEvents(id);
    notifyListeners();
  }

  Future<void> reloadChat(int id) => _refreshOne(id);

  // ── Team ───────────────────────────────────────────────────────────────────

  /// Counts use only requests this user can see, so they match the Requests tab.
  int openCountForUser(int userId) => openChats.where((r) => assigneeOf(r.id) == userId).length;

  int openCountForDept(int deptId) => openChats.where((r) => r.departmentId == deptId).length;

  /// Whether this user sees every open request of [deptId], so its counts are complete.
  bool seesAllOf(int? deptId) => switch (me?.role) {
        AppRole.admin => true,
        AppRole.supervisor => me!.departmentId == null || me!.departmentId == deptId,
        _ => false,
      };
}
