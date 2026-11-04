import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../components/ds.dart';
import 'alerts.dart';
import 'chat.dart';
import 'profile.dart';
import 'requests.dart';
import 'team.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().onIncoming = _incoming;
  }

  void _incoming(Req r) {
    if (!mounted) return;
    Toaster.show(
      context,
      'New request · ${r.chatName} · ${r.chatTitle}',
      icon: Symbols.notifications_active_rounded,
      actionLabel: 'Open',
      onAction: () => openChat(context, r),
    );
  }

  void _go(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pages = [
      RequestsScreen(onOpenProfile: () => _go(3)),
      const AlertsScreen(),
      const TeamScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: _TabBar(index: _tab, onTap: _go, badges: [s.unreadChats, s.unreadAlerts, 0, 0]),
    );
  }
}

Future<void> openChat(BuildContext context, Req r) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(requestId: r.id)));

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onTap, required this.badges});
  final int index;
  final ValueChanged<int> onTap;
  final List<int> badges;

  static const _items = [
    (Symbols.forum_rounded, 'Requests'),
    (Symbols.notifications_rounded, 'Alerts'),
    (Symbols.groups_rounded, 'Team'),
    (Symbols.account_circle_rounded, 'You'),
  ];

  static const _height = 64.0, _inset = 5.0;

  /// Floating glass pill; a capsule slides behind the selected tab.
  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(_height / 2);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.4 : 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                height: _height,
                padding: const EdgeInsets.all(_inset),
                decoration: BoxDecoration(
                  color: c.surfaceGlass,
                  borderRadius: radius,
                  border: Border.all(
                    color: (dark ? Colors.white : Colors.black).withValues(alpha: dark ? 0.12 : 0.06),
                    width: 0.5,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final w = box.maxWidth / _items.length;
                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          left: w * index,
                          top: 0,
                          bottom: 0,
                          width: w,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: (dark ? Colors.white : Colors.black).withValues(alpha: dark ? 0.12 : 0.06),
                              borderRadius: BorderRadius.circular((_height - _inset * 2) / 2),
                            ),
                          ),
                        ),
                        Row(children: [for (final (i, item) in _items.indexed) Expanded(child: _item(c, i, item))]),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(RgColors c, int i, (IconData, String) item) {
    final (icon, label) = item;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(i),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                RgIcon(
                  icon,
                  size: 26,
                  fill: i == index,
                  weight: i == index ? 500 : 400,
                  color: i == index ? c.brand : c.textTertiary,
                ),
                if (badges[i] > 0)
                  Positioned(
                    top: -3,
                    left: 16,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: c.dangerSolid, borderRadius: BorderRadius.circular(9)),
                      child: Text(
                        '${badges[i]}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1,
                          fontFeatures: RgType.tabular,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                height: 1.2,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
                color: i == index ? c.textBrand : c.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
