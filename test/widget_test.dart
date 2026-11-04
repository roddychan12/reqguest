import 'package:flutter_test/flutter_test.dart';
import 'package:reqguest/core/mapping.dart';
import 'package:reqguest/models/models.dart';
import 'package:reqguest/theme/tokens.dart';

void main() {
  group('status codes map to StatusBadge variants', () {
    test('per SKILL.md', () {
      for (final c in ['requested', 'raised', 'received']) {
        expect(statusKindFor(c), StatusKind.newReq, reason: c);
      }
      for (final c in ['accepted', 'assigned', 'on_hold']) {
        expect(statusKindFor(c), StatusKind.acknowledged, reason: c);
      }
      for (final c in ['collected', 'delivering', 'in_progress', 'preparing', 'ready']) {
        expect(statusKindFor(c), StatusKind.inProgress, reason: c);
      }
      expect(statusKindFor('delivered'), StatusKind.completed);
      expect(statusKindFor('completed'), StatusKind.completed);
      expect(statusKindFor('cancelled'), StatusKind.cancelled);
    });
  });

  test('titles drop the room suffix and normalise separators', () {
    expect(cleanTitle('Extra pillows for Room 402'), 'Extra pillows');
    expect(cleanTitle('AC not cooling in Room 515'), 'AC not cooling');
    expect(cleanTitle('Bathroom tap leaking Room 301'), 'Bathroom tap leaking');
    expect(cleanTitle('Order #1001 - Veg Thali x2'), 'Order #1001 · Veg Thali ×2');
  });

  test('priority integers map to tag keys', () {
    expect(priorityKey(1), 'low');
    expect(priorityKey(2), 'normal');
    expect(priorityKey(3), 'high');
    expect(priorityKey(4), 'urgent');
  });

  test('file sizes format like the prototype', () {
    expect(fileSize(245678), '240 KB');
    expect(fileSize(1548200), '1.5 MB');
  });

  test('events sort by time, ties ordered guest → assign → status → comment', () {
    final t = DateTime(2026, 4, 9, 7, 45);
    ChatEvent e(EventKind k, int id, [DateTime? at]) => ChatEvent(kind: k, id: id, at: at ?? t);
    final list = [
      e(EventKind.comment, 1),
      e(EventKind.status, 2),
      e(EventKind.assign, 3),
      e(EventKind.guest, 4, DateTime(2026, 4, 9, 7, 30)),
      e(EventKind.attach, 5, DateTime(2026, 4, 9, 8)),
    ]..sort(ChatEvent.compare);
    expect(list.map((x) => x.kind), [
      EventKind.guest,
      EventKind.assign,
      EventKind.status,
      EventKind.comment,
      EventKind.attach,
    ]);
  });

  test('status history with no from-status becomes the guest card', () {
    final guest = ChatEvent.fromHistory({
      'id': 1,
      'changed_by': 1,
      'note': 'Request created',
      'changed_at': '2026-04-09 07:30:00',
      'from_status': null,
      'to_status': {'id': 7, 'code': 'raised', 'name': 'Raised'},
    });
    expect(guest.kind, EventKind.guest);
    final status = ChatEvent.fromHistory({
      'id': 2,
      'changed_at': '2026-04-09 07:45:00',
      'from_status': {'id': 7, 'code': 'raised', 'name': 'Raised'},
      'to_status': {'id': 8, 'code': 'assigned', 'name': 'Assigned'},
    });
    expect(status.kind, EventKind.status);
    expect(status.toStatusName, 'Assigned');
    expect(status.at, DateTime(2026, 4, 9, 7, 45));
  });

  test('request rows parse integer priority and requester as chat name', () {
    final r = Req.fromJson({
      'id': 3,
      'reference_no': 'ENG-2026-0001',
      'title': 'AC not cooling in Room 515',
      'priority': 3,
      'requester_name': 'Room 515',
      'current_status_id': 9,
      'created_at': '2026-04-09 07:30:00',
    });
    expect(r.chatName, 'Room 515');
    expect(r.chatTitle, 'AC not cooling');
    expect(r.isHighPriority, isTrue);
  });
}
