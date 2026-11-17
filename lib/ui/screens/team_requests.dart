import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../components/ds.dart';
import 'gate.dart';
import 'requests.dart';

/// Open requests a teammate is handling. They open read-only (see [AppState.canManage]);
/// once closed they move to Closed.
class TeamRequestsScreen extends StatefulWidget {
  const TeamRequestsScreen({super.key});

  @override
  State<TeamRequestsScreen> createState() => _TeamRequestsScreenState();
}

class _TeamRequestsScreenState extends State<TeamRequestsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(AppState s, Req r, String q) =>
      q.isEmpty ||
      [
        r.chatName,
        r.title,
        r.referenceNo,
        r.description ?? '',
        s.statusOf(r)?.name ?? '',
        s.nameOf(s.assigneeOf(r.id)),
      ].any((f) => f.toLowerCase().contains(q));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final q = _search.text.trim().toLowerCase();
    final all = s.teamChats;
    final rows = all.where((r) => _matches(s, r, q)).toList();

    return RefreshIndicator(
      color: c.textBrand,
      onRefresh: () => refreshWithToast(context, s.refresh),
      child: PoweredByList(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 36, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LargeTitle('Team Requests'),
                  Text(
                    'Requests your teammates are handling',
                    style: TextStyle(fontSize: 15, color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          if (all.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyState(
                icon: Symbols.diversity_3_rounded,
                title: 'No team requests',
                message: 'When a teammate accepts a request, it appears here.',
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: RgSearchField(
                controller: _search,
                placeholder: 'Search rooms, requests or people',
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (rows.isEmpty)
              const EmptyState(
                icon: Symbols.search_off_rounded,
                title: 'No matches',
                message: 'Try another room, request or name.',
              )
            else
              for (final r in rows) ChatRow(req: r, showHandler: true),
          ],
        ],
      ),
    );
  }
}
