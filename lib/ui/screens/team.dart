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

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// You first, then everyone else by name.
  List<Staff> _sorted(AppState s, Iterable<Staff> list) {
    final me = s.me?.userId;
    return list.toList()..sort((a, b) {
      if (a.userId == me) return -1;
      if (b.userId == me) return 1;
      return s.nameOf(a.userId).toLowerCase().compareTo(s.nameOf(b.userId).toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final q = _search.text.trim().toLowerCase();
    final deptId = s.me?.departmentId;
    final dept = deptId == null ? null : s.departments[deptId];

    // Only the signed-in user's own department.
    final all = deptId == null ? <Staff>[] : _sorted(s, s.staff.where((st) => st.departmentId == deptId));
    final members = all.where((st) => q.isEmpty || s.nameOf(st.userId).toLowerCase().contains(q)).toList();
    final openTotal = deptId == null ? 0 : s.openCountForDept(deptId);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RgIcon(Symbols.chevron_left_rounded, size: 30, weight: 500, color: c.textBrand),
                          Text('You', style: TextStyle(fontSize: 17, color: c.textBrand)),
                        ],
                      ),
                    ),
                  ),
                  Text('Team', style: RgType.headline.copyWith(color: c.textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: c.textBrand,
                onRefresh: () => refreshWithToast(context, s.refreshTeam),
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    if (deptId == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: EmptyState(
                          icon: Symbols.domain_disabled_rounded,
                          title: 'No department',
                          message: "You aren't in a department yet, so there is no team to show.",
                        ),
                      )
                    else ...[
                      // At-a-glance numbers.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: _Stat(icon: Symbols.group_rounded, value: all.length, label: 'Members'),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _Stat(
                                icon: Symbols.forum_rounded,
                                value: openTotal,
                                label: 'Open',
                                accent: openTotal > 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (all.length > 5)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: RgSearchField(
                            controller: _search,
                            placeholder: 'Search people',
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      if (q.isNotEmpty && members.isEmpty)
                        const EmptyState(
                          icon: Symbols.search_off_rounded,
                          title: 'No matches',
                          message: 'Try another name.',
                        )
                      else
                        _DepartmentCard(dept: dept, members: members),
                    ],
                    SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One number in the summary row.
class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label, this.accent = false});
  final IconData icon;
  final int value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return Semantics(
      label: '$value $label',
      excludeSemantics: true,
      child: RgCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RgIcon(icon, size: 20, color: accent ? c.textBrand : c.textTertiary),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: RgType.title2.copyWith(color: c.textPrimary, fontFeatures: RgType.tabular),
            ),
            Text(label, style: RgType.footnote.copyWith(color: c.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// A department with its members in one card. [dept] is null for staff without a department.
class _DepartmentCard extends StatelessWidget {
  const _DepartmentCard({required this.dept, required this.members});
  final Department? dept;
  final List<Staff> members;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final d = dept;
    final name = d?.name ?? 'No department';
    final showOpen = d != null && s.seesAllOf(d.id);
    final open = d == null ? 0 : s.openCountForDept(d.id);

    return RgCard(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      radius: 16,
      child: Column(
        children: [
          // Department header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              children: [
                _DeptBadge(dept: d),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RgType.headline.copyWith(color: c.textPrimary),
                      ),
                      Text(
                        '${members.length} ${members.length == 1 ? 'member' : 'members'}',
                        style: RgType.footnote.copyWith(color: c.textSecondary, fontFeatures: RgType.tabular),
                      ),
                    ],
                  ),
                ),
                if (showOpen) _CountPill(count: open),
              ],
            ),
          ),
          Container(height: 0.5, color: c.separator),
          if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  RgIcon(Symbols.person_off_rounded, size: 18, color: c.textTertiary),
                  const SizedBox(width: 8),
                  Text('No members yet', style: RgType.subhead.copyWith(color: c.textTertiary)),
                ],
              ),
            )
          else
            for (final (i, m) in members.indexed) _MemberRow(member: m, last: i == members.length - 1),
        ],
      ),
    );
  }
}

/// Rounded-square badge with the department code (HK, ENG…) in the department's colour.
class _DeptBadge extends StatelessWidget {
  const _DeptBadge({required this.dept});
  final Department? dept;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    final d = dept;
    final code = (d?.code?.trim().isNotEmpty ?? false)
        ? d!.code!.trim().toUpperCase()
        : (d?.name ?? '')
              .trim()
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .take(2)
              .map((w) => w[0])
              .join()
              .toUpperCase();
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: d == null ? c.surfaceSunken : c.avatarTones[d.tone % c.avatarTones.length],
        borderRadius: BorderRadius.circular(12),
      ),
      child: d == null || code.isEmpty
          ? RgIcon(Symbols.groups_rounded, size: 22, color: c.textSecondary)
          : Text(
              code.length > 3 ? code.substring(0, 3) : code,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: c.textPrimary),
            ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.last});
  final Staff member;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final m = member;
    final isMe = m.userId == s.me?.userId;
    final name = s.nameOf(m.userId);
    final presence = presenceOf(s, m);
    // Only people with work get a pill, so busy members stand out.
    final open = (isMe || s.seesAllOf(m.departmentId)) ? s.openCountForUser(m.userId) : 0;
    final subline = [
      if (isMe && s.me != null) roleLabel(s.me!.role),
      if (presence != null) presenceLabel(presence),
      if (!m.isActive) 'Inactive',
    ].join(' · ');

    return Opacity(
      opacity: m.isActive ? 1 : 0.55,
      child: Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Row(
          children: [
            PersonAvatar(name: name, size: 40, presence: presence),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 60),
                padding: const EdgeInsets.fromLTRB(0, 10, 14, 10),
                decoration: last ? null : hairlineBottom(context),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: RgType.body.copyWith(
                                    color: c.textPrimary,
                                    fontWeight: isMe ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (isMe) ...[const SizedBox(width: 6), const _YouTag()],
                            ],
                          ),
                          if (subline.isNotEmpty)
                            Text(subline, style: RgType.footnote.copyWith(color: c.textSecondary)),
                        ],
                      ),
                    ),
                    if (open > 0) ...[const SizedBox(width: 8), _CountPill(count: open)],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YouTag extends StatelessWidget {
  const _YouTag();

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.successBg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        'You',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.successFg),
      ),
    );
  }
}

/// "3 open" pill: highlighted when there is work, quiet when there is none.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    final busy = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: busy ? c.successBg : c.surfaceSunken, borderRadius: BorderRadius.circular(999)),
      child: Text(
        '$count open',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: busy ? c.successFg : c.textSecondary,
          fontFeatures: RgType.tabular,
        ),
      ),
    );
  }
}
