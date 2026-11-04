import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../components/ds.dart';

/// Presence is only known for the signed-in user (the On shift switch); the
/// server has no shift data for anyone else, so they show none.
Presence? presenceOf(AppState s, Staff st) =>
    st.userId == s.me?.userId ? (s.onShift ? Presence.onShift : Presence.off) : null;

String presenceLabel(Presence p) => switch (p) {
      Presence.onShift => 'On shift',
      Presence.onBreak => 'On break',
      Presence.off => 'Off shift',
    };

class TeamScreen extends StatelessWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final depts = s.departments.values.where((d) => d.isActive).toList();
    final unplaced = s.staff.where((st) => st.departmentId == null || !s.departments.containsKey(st.departmentId)).toList();

    return RefreshIndicator(
      color: c.textBrand,
      onRefresh: s.refreshTeam,
      child: ListView(padding: EdgeInsets.zero, children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 36, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const LargeTitle('Team'),
              Text('${s.tenant?.name ?? ''} · ${s.staff.length} ${s.staff.length == 1 ? 'member' : 'members'}',
                  style: TextStyle(fontSize: 15, color: c.textSecondary, fontFeatures: RgType.tabular)),
            ]),
          ),
        ),
        if (s.staff.isEmpty)
          const EmptyState(
              icon: Symbols.groups_rounded, title: 'No team members', message: 'Staff added to this workspace appear here.'),
        for (final d in depts) ...[
          SectionHeader(d.name, trailing: s.seesAllOf(d.id) ? '${s.openCountForDept(d.id)} open' : null),
          _Members(members: s.staff.where((st) => st.departmentId == d.id).toList()),
        ],
        if (unplaced.isNotEmpty) ...[
          const SectionHeader('No department'),
          _Members(members: unplaced),
        ],
        const SizedBox(height: 110),
      ]),
    );
  }
}

class _Members extends StatelessWidget {
  const _Members({required this.members});
  final List<Staff> members;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    if (members.isEmpty) {
      return RgCard(
        padding: const EdgeInsets.all(14),
        child: Text('No members yet', style: TextStyle(fontSize: 15, color: c.textTertiary)),
      );
    }
    return RgCard(
      child: Column(children: [
        for (final (i, m) in members.indexed)
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Row(children: [
              PersonAvatar(name: s.nameOf(m.userId), size: 40, presence: presenceOf(s, m)),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(0, 11, 14, 11),
                  decoration: i < members.length - 1 ? hairlineBottom(context) : null,
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${s.nameOf(m.userId)}${m.userId == s.me?.userId ? ' (you)' : ''}',
                            style: RgType.body.copyWith(color: c.textPrimary)),
                        if (m.userId == s.me?.userId)
                          Text('${roleLabel(s.me!.role)} · ${presenceLabel(presenceOf(s, m)!)}',
                              style: RgType.footnote.copyWith(color: c.textSecondary)),
                      ]),
                    ),
                    if (m.userId == s.me?.userId || s.seesAllOf(m.departmentId))
                      Text('${s.openCountForUser(m.userId)} open',
                          style: TextStyle(fontSize: 15, color: c.textSecondary, fontFeatures: RgType.tabular)),
                  ]),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}
