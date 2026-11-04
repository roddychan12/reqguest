import '../core/mapping.dart';

int? _i(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
bool _b(dynamic v) => v == true || v == 1 || v == '1';
String? _s(dynamic v) => v?.toString();

enum AppRole { admin, supervisor, staff }

String roleLabel(AppRole r) => switch (r) {
      AppRole.admin => 'Administrator',
      AppRole.supervisor => 'Supervisor',
      AppRole.staff => 'Staff',
    };

/// Priority is stored as an integer: 1 low · 2 normal · 3 high · 4 urgent.
String priorityKey(int? p) => switch (p) {
      1 => 'low',
      3 => 'high',
      4 => 'urgent',
      _ => 'normal',
    };

class Tenant {
  Tenant(this.id, this.name, this.slug, this.timezone);
  final int id;
  final String name, slug;
  final String? timezone;

  factory Tenant.fromJson(Map<String, dynamic> j) {
    final settings = j['settings'];
    return Tenant(_i(j['id'])!, _s(j['name']) ?? '', _s(j['slug']) ?? '',
        settings is Map ? _s(settings['timezone']) : null);
  }
}

class Department {
  Department(this.id, this.name, this.code, this.isActive);
  final int id;
  final String name;
  final String? code;
  final bool isActive;

  factory Department.fromJson(Map<String, dynamic> j) =>
      Department(_i(j['id'])!, _s(j['name']) ?? '', _s(j['code']), j['is_active'] == null || _b(j['is_active']));

  int get tone => departmentTone(id: id, code: code, name: name);
}

class Staff {
  Staff(this.id, this.userId, this.departmentId, this.systemRoleId, this.isActive);
  final int id, userId;
  final int? departmentId, systemRoleId;
  final bool isActive;

  factory Staff.fromJson(Map<String, dynamic> j) => Staff(
      _i(j['id'])!, _i(j['user_id'])!, _i(j['department_id']), _i(j['system_role_id']), _b(j['is_active'] ?? 1));
}

class WfStatus {
  WfStatus(this.id, this.workflowId, this.name, this.code, this.isInitial, this.isFinal, this.sortOrder);
  final int id, workflowId, sortOrder;
  final String name, code;
  final bool isInitial, isFinal;

  factory WfStatus.fromJson(Map<String, dynamic> j) => WfStatus(_i(j['id'])!, _i(j['workflow_id']) ?? 0,
      _s(j['name']) ?? '', _s(j['code']) ?? '', _b(j['is_initial']), _b(j['is_final']), _i(j['sort_order']) ?? 0);
}

class WfTransition {
  WfTransition(this.id, this.workflowId, this.fromStatusId, this.toStatusId, this.name);
  final int id, workflowId, fromStatusId, toStatusId;
  final String name;

  factory WfTransition.fromJson(Map<String, dynamic> j) => WfTransition(_i(j['id'])!, _i(j['workflow_id']) ?? 0,
      _i(j['from_status_id']) ?? 0, _i(j['to_status_id']) ?? 0, _s(j['name']) ?? '');
}

class RequestType {
  RequestType(this.id, this.name, this.code, this.departmentId, this.workflowId);
  final int id;
  final String name, code;
  final int? departmentId, workflowId;

  factory RequestType.fromJson(Map<String, dynamic> j) => RequestType(
      _i(j['id'])!, _s(j['name']) ?? '', _s(j['code']) ?? '', _i(j['department_id']), _i(j['workflow_id']));
}

class Req {
  Req({
    required this.id,
    required this.referenceNo,
    required this.title,
    this.description,
    this.requestTypeId,
    this.workflowId,
    this.currentStatusId,
    required this.priority,
    this.createdBy,
    this.requesterName,
    this.requesterContact,
    this.departmentId,
    this.locationId,
    this.locationNote,
    this.closedAt,
    this.dueAt,
    required this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String referenceNo, title;
  final String? description, requesterName, requesterContact, locationNote;
  final int? requestTypeId, workflowId, createdBy, departmentId, locationId;
  int? currentStatusId;
  final int priority;
  final DateTime createdAt;
  final DateTime? closedAt, dueAt, updatedAt;

  factory Req.fromJson(Map<String, dynamic> j) => Req(
        id: _i(j['id'])!,
        referenceNo: _s(j['reference_no']) ?? '#${j['id']}',
        title: _s(j['title']) ?? '',
        description: _s(j['description']),
        requestTypeId: _i(j['request_type_id']),
        workflowId: _i(j['workflow_id']),
        currentStatusId: _i(j['current_status_id']),
        priority: _i(j['priority']) ?? 2,
        createdBy: _i(j['created_by']),
        requesterName: _s(j['requester_name']),
        requesterContact: _s(j['requester_contact']),
        departmentId: _i(j['department_id']),
        locationId: _i(j['location_id']),
        locationNote: _s(j['location_note']),
        closedAt: parseDate(j['closed_at']),
        dueAt: parseDate(j['due_at']),
        createdAt: parseDate(j['created_at']) ?? DateTime.now(),
        updatedAt: parseDate(j['updated_at']),
      );

  String get priorityName => priorityKey(priority);
  bool get isHighPriority => priority >= 3;

  /// Chat name: requester (room) first, falling back to the reference.
  String get chatName => (requesterName?.trim().isNotEmpty ?? false) ? requesterName!.trim() : referenceNo;
  String get chatTitle => cleanTitle(title);
}

// ── Chat events ──────────────────────────────────────────────────────────────

enum EventKind { guest, assign, status, comment, attach }

/// One message in a request's chat. Built from status history, assignments,
/// comments and attachments, then sorted chronologically.
class ChatEvent {
  ChatEvent({
    required this.kind,
    required this.id,
    required this.at,
    this.by,
    this.note,
    this.fromStatus,
    this.toStatusId,
    this.toStatusName,
    this.toStatusCode,
    this.assignedTo,
    this.assignedDept,
    this.assignmentType,
    this.body,
    this.isInternal = false,
    this.fileName,
    this.filePath,
    this.mimeType,
    this.fileSize,
    this.pending = false,
  });

  final EventKind kind;
  final int id;
  final DateTime at;
  final int? by;
  final String? note;

  // status
  final String? fromStatus;
  final int? toStatusId;
  final String? toStatusName, toStatusCode;

  // assign
  final int? assignedTo, assignedDept;
  final String? assignmentType;

  // comment
  final String? body;
  final bool isInternal;

  // attach — filePath is either a full URL (media uploads) or a server-relative path
  final String? fileName, filePath, mimeType;
  final int? fileSize;

  /// Optimistic message not yet confirmed by the server.
  final bool pending;

  String get key => '${kind.name}:$id';

  static int _order(EventKind k) => switch (k) {
        EventKind.guest => 0,
        EventKind.assign => 1,
        EventKind.status => 2,
        EventKind.comment || EventKind.attach => 3,
      };

  static int compare(ChatEvent a, ChatEvent b) {
    final t = a.at.compareTo(b.at);
    if (t != 0) return t;
    final o = _order(a.kind) - _order(b.kind);
    return o != 0 ? o : a.id - b.id;
  }

  static ChatEvent fromHistory(Map<String, dynamic> j) {
    final from = j['from_status'];
    final to = (j['to_status'] as Map?) ?? const {};
    final isGuest = from == null && j['from_status_id'] == null;
    return ChatEvent(
      kind: isGuest ? EventKind.guest : EventKind.status,
      id: _i(j['id'])!,
      at: parseDate(j['changed_at']) ?? DateTime.now(),
      by: _i(j['changed_by']),
      note: _s(j['note']),
      fromStatus: from is Map ? _s(from['name']) : null,
      toStatusId: _i(to['id'] ?? j['to_status_id']),
      toStatusName: _s(to['name']),
      toStatusCode: _s(to['code']),
    );
  }

  static ChatEvent fromAssignment(Map<String, dynamic> j) => ChatEvent(
        kind: EventKind.assign,
        id: _i(j['id'])!,
        at: parseDate(j['assigned_at']) ?? DateTime.now(),
        by: _i(j['assigned_by']),
        note: _s(j['note']),
        assignedTo: _i(j['assigned_to_user']),
        assignedDept: _i(j['assigned_to_dept']),
        assignmentType: _s(j['assignment_type']),
      );

  static ChatEvent fromComment(Map<String, dynamic> j, {bool pending = false}) => ChatEvent(
        kind: EventKind.comment,
        id: _i(j['id']) ?? -DateTime.now().microsecondsSinceEpoch,
        at: parseDate(j['created_at']) ?? DateTime.now(),
        by: _i(j['user_id']),
        body: _s(j['body']) ?? '',
        isInternal: _b(j['is_internal']),
        pending: pending,
      );

  static ChatEvent fromAttachment(Map<String, dynamic> j) => ChatEvent(
        kind: EventKind.attach,
        id: _i(j['id'])!,
        at: parseDate(j['created_at']) ?? DateTime.now(),
        by: _i(j['uploaded_by']),
        fileName: _s(j['file_name']),
        filePath: _s(j['file_path']),
        mimeType: _s(j['mime_type']),
        fileSize: _i(j['file_size']),
      );
}

/// Active assignment (not unassigned) on a request.
class Assignment {
  Assignment(this.id, this.userId, this.deptId, this.type, this.at, this.unassignedAt);
  final int id;
  final int? userId, deptId;
  final String type;
  final DateTime at;
  final DateTime? unassignedAt;

  factory Assignment.fromJson(Map<String, dynamic> j) => Assignment(_i(j['id'])!, _i(j['assigned_to_user']),
      _i(j['assigned_to_dept']), _s(j['assignment_type']) ?? 'manual', parseDate(j['assigned_at']) ?? DateTime.now(),
      parseDate(j['unassigned_at']));
}

/// The signed-in person.
class Me {
  Me({required this.userId, required this.name, this.email, this.phone, this.timezone, required this.role, this.staff});
  final int userId;
  final String name;
  final String? email, phone, timezone;
  AppRole role;
  Staff? staff;

  int? get departmentId => staff?.departmentId;
}
