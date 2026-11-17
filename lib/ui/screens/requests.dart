import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../core/mapping.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../components/ds.dart';
import '../copy.dart';
import 'gate.dart';
import 'home.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  final _search = TextEditingController();
  ListFilter _filter = ListFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(AppState s, Req r) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      r.chatName,
      r.title,
      r.referenceNo,
      r.description ?? '',
      s.statusOf(r)?.name ?? '',
    ].any((f) => f.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final searching = _search.text.trim().isNotEmpty;
    // Only requests this user handles or may accept; teammates' are under Team Requests,
    // closed ones under Closed. Chip counts use the same search as the list.
    final base = s.myChats.where((r) => _matches(s, r)).toList();
    final unread = base.where((r) => s.unreadCount(r) > 0).length;
    final mine = base.where((r) => s.assigneeOf(r.id) == s.me?.userId).length;
    final rows = base.where((r) {
      return switch (_filter) {
        ListFilter.all => true,
        ListFilter.unread => s.unreadCount(r) > 0,
        ListFilter.mine => s.assigneeOf(r.id) == s.me?.userId,
        ListFilter.high => r.isHighPriority,
      };
    }).toList();
    final closed = s.closedChats;

    return RefreshIndicator(
      color: c.textBrand,
      onRefresh: () => refreshWithToast(context, s.refresh),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 32,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.tenant?.name ?? '',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary),
                            ),
                          ),
                          if (s.syncFailed) ...[
                            RgIcon(Symbols.cloud_off_rounded, size: 18, color: c.warningFg),
                            const SizedBox(width: 4),
                            Text('Offline', style: TextStyle(fontSize: 13, color: c.warningFg)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const SizedBox(
                      height: 41,
                      child: Align(alignment: Alignment.centerLeft, child: Logo()),
                    ),
                    const SizedBox(height: 10),
                    RgSearchField(
                      controller: _search,
                      placeholder: 'Search rooms or requests',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          for (final (f, label, count) in [
                            (ListFilter.all, 'All', null),
                            (ListFilter.unread, 'Unread', unread),
                            (ListFilter.mine, 'Assigned to me', mine),
                            (ListFilter.high, 'High priority', null),
                          ]) ...[
                            RgChip(
                              label: label,
                              count: count,
                              selected: _filter == f,
                              onTap: () => setState(() => _filter = f),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!searching && closed.isNotEmpty) SliverToBoxAdapter(child: _ClosedRow(count: closed.length)),
          if (rows.isEmpty)
            SliverToBoxAdapter(
              child: switch (()) {
                _ when searching || _filter != ListFilter.all => const EmptyState(
                  icon: Symbols.search_off_rounded,
                  title: 'No matches',
                  message: 'Try another room, name or filter.',
                ),
                // Nothing at all in this workspace (not just nothing visible to this user).
                _ when s.totalRequests == 0 => EmptyState(
                  icon: Symbols.inbox_rounded,
                  title: 'No requests in ${s.tenant?.name.trim() ?? 'this workspace'}',
                  message: 'Requests created for this property will appear here.',
                  action: s.tenants.length > 1
                      ? RgButton(
                          label: 'Switch Workspace',
                          icon: Symbols.swap_horiz_rounded,
                          variant: BtnVariant.secondary,
                          onPressed: s.switchWorkspace,
                        )
                      : null,
                ),
                // Signed in, but no staff record here, so the app cannot place them in a department.
                _ when s.visible.isEmpty && s.me?.staff == null => EmptyState(
                  icon: Symbols.badge_rounded,
                  title: 'Not set up as staff',
                  message:
                      'Your account is not added as staff in ${s.tenant?.name.trim() ?? 'this workspace'}. '
                      'Ask an administrator to add you under Staff with your department.',
                ),
                _ when s.visible.isEmpty => const EmptyState(
                  icon: Symbols.visibility_off_rounded,
                  title: 'Nothing assigned to you',
                  message: 'Requests assigned to you or your department will appear here.',
                ),
                _ => const EmptyState(
                  icon: Symbols.task_alt_rounded,
                  title: 'All caught up',
                  message: 'New guest requests will appear here.',
                ),
              },
            )
          else
            SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) => ChatRow(req: rows[i]),
            ),
          // Few requests: the footer fills the leftover space and sits at the bottom, just above the tab bar.
          // Many requests: it is simply the last thing in the list, seen once scrolled to the end.
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [_Footer(), const BottomBarSpacer()]),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        children: [
          // Room for the New button, which sits just above the text (see HomeShell),
          // so it never covers the last request.
          SizedBox(height: 72),
          // Last thing in the list, just above the tab bar.
          PoweredBy(),
        ],
      ),
    );
  }
}

class _ClosedRow extends StatelessWidget {
  const _ClosedRow({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return Pressable(
      pressedColor: c.surfaceSunken,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClosedScreen())),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Center(child: RgIcon(Symbols.inventory_2_rounded, color: c.textSecondary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: hairlineBottom(context),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Closed', style: RgType.headline.copyWith(color: c.textPrimary)),
                    ),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textBrand,
                        fontFeatures: RgType.tabular,
                      ),
                    ),
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

class ClosedScreen extends StatelessWidget {
  const ClosedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final rows = s.closedChats;
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
                          Text('Requests', style: TextStyle(fontSize: 17, color: c.textBrand)),
                        ],
                      ),
                    ),
                  ),
                  Text('Closed', style: RgType.headline.copyWith(color: c.textPrimary)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Text(
                "Delivered, completed and cancelled requests. New messages here don't reopen them.",
                textAlign: TextAlign.center,
                style: RgType.footnote.copyWith(color: c.textSecondary),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const EmptyState(
                      icon: Symbols.inventory_2_rounded,
                      title: 'Nothing closed yet',
                      message: 'Closed requests move here automatically.',
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) => ChatRow(req: rows[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatRow extends StatelessWidget {
  const ChatRow({super.key, required this.req, this.showHandler = false});
  final Req req;

  /// Adds a "Handled by …" line (Team Requests).
  final bool showHandler;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final copy = Copy(s);
    final unread = s.unreadCount(req);
    final (icon, text, own, internal) = copy.preview(req);
    final iconColor = own ? c.infoFg : (internal ? c.warningFg : c.textTertiary);

    return Pressable(
      pressedColor: c.surfaceSunken,
      onTap: () => openChat(context, req),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            GlyphAvatar(icon: copy.typeIcon(req), tint: copy.tint(context, req)),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: hairlineBottom(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          flex: 0,
                          fit: FlexFit.loose,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 170),
                            child: Text(
                              req.chatName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: c.textPrimary,
                                fontFeatures: RgType.tabular,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            req.chatTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, color: c.textSecondary),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          listTime(s.lastEventAt(req)),
                          style: TextStyle(
                            fontSize: 13,
                            color: unread > 0 ? c.textBrand : c.textSecondary,
                            fontFeatures: RgType.tabular,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (icon != null) ...[RgIcon(icon, size: 18, color: iconColor), const SizedBox(width: 4)],
                        Expanded(
                          child: Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RgType.subhead.copyWith(color: c.textSecondary),
                          ),
                        ),
                        if (req.isHighPriority) ...[
                          const SizedBox(width: 4),
                          PriorityTag(priority: req.priorityName, showLabel: false),
                        ],
                        if (unread > 0) ...[
                          const SizedBox(width: 4),
                          Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            height: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(10)),
                            child: Text(
                              '$unread',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                height: 1,
                                color: c.textOnPrimary,
                                fontFeatures: RgType.tabular,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (showHandler && s.assigneeOf(req.id) != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          RgIcon(Symbols.person_rounded, size: 16, color: c.textTertiary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Handled by ${s.nameOf(s.assigneeOf(req.id))}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RgType.footnote.copyWith(color: c.textTertiary),
                            ),
                          ),
                        ],
                      ),
                    ],
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
