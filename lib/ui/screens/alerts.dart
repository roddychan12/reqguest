import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../core/mapping.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../components/ds.dart';
import '../copy.dart';
import 'home.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final alerts = s.alerts;
    final unread = s.unreadAlerts;
    final groups = <String, List<Alert>>{};
    for (final a in alerts) {
      groups.putIfAbsent(dayLabel(a.event.at), () => []).add(a);
    }

    return RefreshIndicator(
      color: c.textBrand,
      onRefresh: () => refreshWithToast(context, s.refresh),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 36, 16, 8),
              // Title with the action beside it; the action only appears when there is something to clear.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: LargeTitle('Alerts')),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: unread > 0
                            ? RgButton(
                                key: const ValueKey('mark'),
                                label: 'Mark all read',
                                icon: Symbols.done_all_rounded,
                                variant: BtnVariant.secondary,
                                size: BtnSize.sm,
                                onPressed: s.markAllAlertsRead,
                              )
                            : const SizedBox.shrink(key: ValueKey('none')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    unread > 0 ? '$unread unread' : 'All caught up',
                    style: TextStyle(
                      fontSize: 15,
                      color: unread > 0 ? c.textBrand : c.textSecondary,
                      fontFeatures: RgType.tabular,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (alerts.isEmpty)
            const EmptyState(
              icon: Symbols.notifications_off_rounded,
              title: 'No alerts',
              message: 'Updates on your requests will appear here.',
            )
          else
            for (final MapEntry(key: day, value: items) in groups.entries) ...[
              SectionHeader(day, padding: const EdgeInsets.fromLTRB(16, 16, 16, 6)),
              RgCard(
                child: Column(
                  children: [for (final (i, a) in items.indexed) _AlertRow(alert: a, last: i == items.length - 1)],
                ),
              ),
            ],
          const BottomBarSpacer(),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, required this.last});
  final Alert alert;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final (title, body, icon, kind) = Copy(s).alert(alert);
    final unread = s.isAlertUnread(alert);
    final (Color bg, Color fg) = switch (kind) {
      'new' => (c.status[StatusKind.newReq]!.bg, c.status[StatusKind.newReq]!.fg),
      'status' => () {
        final st = c.status[statusKindFor(alert.event.toStatusCode ?? s.statuses[alert.event.toStatusId]?.code)]!;
        return (st.bg, st.fg);
      }(),
      'internal' => (c.warningBg, c.warningFg),
      _ => (c.avatarTones[1], c.textPrimary),
    };

    return Pressable(
      pressedColor: c.surfaceSunken,
      onTap: () {
        s.markAlertRead(alert);
        openChat(context, alert.req);
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: RgIcon(icon, size: 20, color: fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
                decoration: last ? null : hairlineBottom(context),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: RgType.subhead.copyWith(fontWeight: FontWeight.w600, color: c.textPrimary),
                          ),
                          Text(
                            body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: RgType.subhead.copyWith(color: c.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          hhmm(alert.event.at),
                          style: TextStyle(fontSize: 13, color: c.textSecondary, fontFeatures: RgType.tabular),
                        ),
                        const SizedBox(height: 8),
                        if (unread)
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
                          ),
                      ],
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
