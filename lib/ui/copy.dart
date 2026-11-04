import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/mapping.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

/// Copy for chat previews, pills and alerts, kept in one place so the
/// chat list, thread and alerts feed read the same way.
class Copy {
  Copy(this.s);
  final AppState s;

  bool _mine(ChatEvent e) => e.by != null && e.by == s.me?.userId;

  String statusName(ChatEvent e) => e.toStatusName ?? s.statuses[e.toStatusId]?.name ?? 'Updated';

  String typeName(Req r) => s.types[r.requestTypeId]?.name ?? 'Request';

  IconData typeIcon(Req r) {
    final t = s.types[r.requestTypeId];
    return requestTypeIcon(code: t?.code, name: t?.name ?? r.title);
  }

  Color tint(BuildContext context, Req r) {
    final c = RgColors.of(context);
    final d = s.departments[r.departmentId];
    return c.avatarTones[d?.tone ?? 1];
  }

  String _assignee(ChatEvent e) =>
      e.assignedTo == s.me?.userId ? 'you' : (e.assignedTo != null ? s.nameOf(e.assignedTo) : _dept(e.assignedDept));

  String _dept(int? id) => s.departments[id]?.name ?? 'the team';

  String assignText(ChatEvent e) {
    final to = _assignee(e);
    switch (e.assignmentType) {
      case 'auto':
        return 'Auto-assigned to $to';
      case 'pick':
        return e.assignedTo == s.me?.userId ? 'You picked this up' : '${s.nameOf(e.assignedTo)} picked this up';
      default:
        final by = e.by == s.me?.userId ? 'You' : s.whoOf(e.by);
        final note = e.note;
        final withNote = note != null && note.isNotEmpty && !note.toLowerCase().startsWith('assigned');
        return '$by assigned $to${withNote ? ' · $note' : ''}';
    }
  }

  String statusLine(ChatEvent e) {
    final who = s.whoOf(e.by);
    final note = e.note?.trim();
    if (note == null || note.isEmpty || note.toLowerCase() == statusName(e).toLowerCase()) return who;
    return '$who · $note';
  }

  String mediaLabel(ChatEvent e) => isVideo(e.mimeType) ? 'Video' : (isImage(e.mimeType) ? 'Photo' : 'File');

  /// (icon, text, isOwnMessage) for the chat-list preview line.
  (IconData?, String, bool, bool) preview(Req r) {
    final e = s.eventsFor(r.id).lastOrNull;
    if (e == null) return (null, r.description ?? r.chatTitle, false, false);
    final mine = _mine(e);
    switch (e.kind) {
      case EventKind.guest:
        return (Symbols.concierge_rounded, r.description?.isNotEmpty == true ? r.description! : r.chatTitle, false, false);
      case EventKind.status:
        return (Symbols.swap_horiz_rounded, '${statusName(e)} · ${s.whoOf(e.by)}', false, false);
      case EventKind.assign:
        return (Symbols.person_add_rounded,
            e.assignedTo == s.me?.userId ? 'Assigned to you' : 'Assigned to ${_assignee(e)}', false, false);
      case EventKind.attach:
        final label = mediaLabel(e);
        return (
          mine ? Symbols.done_all_rounded : (isVideo(e.mimeType) ? Symbols.videocam_rounded : Symbols.photo_camera_rounded),
          mine ? label : '${s.whoOf(e.by)}: $label',
          mine,
          false
        );
      case EventKind.comment:
        final body = e.body ?? '';
        if (e.isInternal) return (Symbols.lock_rounded, mine ? body : '${s.whoOf(e.by)}: $body', false, true);
        return (mine ? Symbols.done_all_rounded : null, mine ? body : '${s.whoOf(e.by)}: $body', mine, false);
    }
  }

  /// (title, body, icon, kind) for an alert row.
  (String, String, IconData, String) alert(Alert a) {
    final r = a.req, e = a.event;
    final room = r.chatName;
    switch (e.kind) {
      case EventKind.guest:
        return ('New request · $room', '${r.chatTitle} · ${typeName(r)}', Symbols.notifications_active_rounded, 'new');
      case EventKind.status:
        final note = e.note?.trim();
        final withNote = note != null && note.isNotEmpty && note.toLowerCase() != statusName(e).toLowerCase();
        return (
          '$room · ${statusName(e)}',
          withNote ? '${s.nameOf(e.by)}: $note' : s.nameOf(e.by),
          Symbols.swap_horiz_rounded,
          'status'
        );
      case EventKind.assign:
        final to = e.assignedTo == s.me?.userId ? 'Assigned to you' : 'Assigned to ${_assignee(e)}';
        final by = e.by != null && e.by != e.assignedTo ? ' by ${s.nameOf(e.by)}' : '';
        return ('$room · Assigned', '$to$by', Symbols.person_add_rounded, 'neutral');
      case EventKind.attach:
        return ('$room · ${mediaLabel(e)}', '${s.nameOf(e.by)} shared ${e.fileName ?? 'a file'}', Symbols.image_rounded, 'neutral');
      case EventKind.comment:
        return (
          '$room · ${e.isInternal ? 'Internal note' : 'New message'}',
          '${s.nameOf(e.by)}: ${e.body ?? ''}',
          e.isInternal ? Symbols.lock_rounded : Symbols.chat_rounded,
          e.isInternal ? 'internal' : 'neutral'
        );
    }
  }

  /// "In Progress · Suresh Nair" / "Assigned to you" / "Unassigned · Kitchen".
  String subline(Req r) {
    final st = s.statusOf(r)?.name ?? 'Unclassified';
    final who = s.assigneeOf(r.id);
    final String a;
    if (who == null) {
      a = 'Unassigned · ${s.departments[r.departmentId]?.name ?? 'No department'}';
    } else if (who == s.me?.userId) {
      a = 'Assigned to you';
    } else {
      a = s.nameOf(who);
    }
    return '$st · $a';
  }
}
