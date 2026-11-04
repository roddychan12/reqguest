import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/tokens.dart';

/// Maps workflow status codes to the DS StatusBadge variant (SKILL.md).
StatusKind statusKindFor(String? code) => switch (code) {
      'requested' || 'raised' || 'received' => StatusKind.newReq,
      'accepted' || 'assigned' || 'on_hold' => StatusKind.acknowledged,
      'collected' || 'delivering' || 'in_progress' || 'preparing' || 'ready' => StatusKind.inProgress,
      'delivered' || 'completed' => StatusKind.completed,
      'cancelled' => StatusKind.cancelled,
      _ => StatusKind.acknowledged,
    };

/// Request type → avatar glyph. Matches on code first, then on name keywords.
IconData requestTypeIcon({String? code, String? name}) {
  final key = '${code ?? ''} ${name ?? ''}'.toLowerCase();
  if (key.contains('pillow') || key.contains('linen')) return Symbols.bed_rounded;
  if (key.contains('towel')) return Symbols.dry_cleaning_rounded;
  if (key.contains('ac_') || key.contains('ac ') || key.contains('air')) return Symbols.ac_unit_rounded;
  if (key.contains('plumb') || key.contains('water') || key.contains('tap')) return Symbols.plumbing_rounded;
  if (key.contains('food') || key.contains('order') || key.contains('dining')) return Symbols.restaurant_rounded;
  if (key.contains('clean') || key.contains('housekeep')) return Symbols.cleaning_services_rounded;
  return Symbols.chat_rounded;
}

/// Department → avatar tone index (into RgColors.avatarTones).
/// Known seed departments use the prototype's tints; others hash on the name.
int departmentTone({int? id, String? code, String? name}) {
  switch ((code ?? '').toUpperCase()) {
    case 'HK':
      return 0;
    case 'ENG':
    case 'DEL':
      return 2;
    case 'FNB':
    case 'KIT':
      return 3;
    case 'FO':
    case 'CS':
      return 1;
  }
  final n = name ?? '';
  if (n.isEmpty) return ((id ?? 1) - 1) % 4;
  return const [0, 2, 3, 1][n.codeUnitAt(0) % 4];
}

/// Transition name → leading icon for the action strip.
IconData transitionIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('cancel')) return Symbols.close_rounded;
  if (n.contains('accept')) return Symbols.check_rounded;
  if (n.contains('collect')) return Symbols.inventory_rounded;
  if (n.contains('start delivery')) return Symbols.directions_walk_rounded;
  if (n.contains('deliver') || n.contains('complete')) return Symbols.task_alt_rounded;
  if (n.contains('assign')) return Symbols.person_add_rounded;
  if (n.contains('hold')) return Symbols.pause_rounded;
  if (n.contains('start') || n.contains('resume')) return Symbols.play_arrow_rounded;
  if (n.contains('prepar')) return Symbols.skillet_rounded;
  if (n.contains('ready')) return Symbols.room_service_rounded;
  if (n.contains('dispatch')) return Symbols.two_wheeler_rounded;
  return Symbols.arrow_forward_rounded;
}

bool isCancelTransition(String name) => name.toLowerCase().contains('cancel');
bool isHoldTransition(String name) => name.toLowerCase().contains('hold');

/// "Extra pillows for Room 402" → "Extra pillows"; " x2" → " ×2"; " - " → " · ".
String cleanTitle(String title) => title
    .replaceAll(RegExp(r'\s+(for|in)\s+Room\s+\d+\s*$', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s+Room\s+\d+\s*$', caseSensitive: false), '')
    .replaceAllMapped(RegExp(r' x(\d+)'), (m) => ' ×${m[1]}')
    .replaceAll(' - ', ' · ')
    .trim();

/// "Suresh Nair" → "Suresh N."
String shortName(String full) {
  final p = full.trim().split(RegExp(r'\s+'));
  if (p.length < 2) return full;
  return '${p.first} ${p[1][0]}.';
}

// ── Dates ────────────────────────────────────────────────────────────────────

DateTime? parseDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  // Server returns "YYYY-MM-DD HH:MM:SS" in tenant local time.
  return DateTime.tryParse(s.contains('T') ? s : s.replaceFirst(' ', 'T'));
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String dayLabel(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (_sameDay(d, n)) return 'Today';
  if (_sameDay(d, n.subtract(const Duration(days: 1)))) return 'Yesterday';
  return DateFormat('d MMMM yyyy').format(d);
}

String hhmm(DateTime d) => DateFormat('HH:mm').format(d);

/// Chat list time: HH:mm today, else Yesterday, else date.
String listTime(DateTime d) {
  final l = dayLabel(d);
  return l == 'Today' ? hhmm(d) : l;
}

String fileSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes > 1000000) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).round()} KB';
}

bool isVideo(String? mime) => (mime ?? '').startsWith('video/');
bool isImage(String? mime) => (mime ?? '').startsWith('image/');
