import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../components/ds.dart';
import 'gate.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final me = s.me!;
    final dept = s.departments[me.departmentId]?.name;

    Widget switchRow(String label, bool value, ValueChanged<bool> onChanged, {bool last = false}) => Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: last ? null : hairlineBottom(context),
          child: Row(children: [
            Expanded(child: Text(label, style: RgType.body.copyWith(color: c.textPrimary))),
            RgSwitch(value: value, onChanged: onChanged),
          ]),
        );

    final account = <(String, String)>[
      ('Email', me.email ?? '–'),
      ('Phone', me.phone ?? '–'),
      ('Department', dept ?? '–'),
      ('Workspace', s.tenant?.name ?? '–'),
      ('Time zone', s.tenant?.timezone ?? me.timezone ?? '–'),
    ];

    return ListView(padding: EdgeInsets.zero, children: [
      const SafeArea(
        bottom: false,
        child: Padding(padding: EdgeInsets.fromLTRB(16, 36, 16, 8), child: LargeTitle('You')),
      ),
      RgCard(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        radius: 16,
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          PersonAvatar(name: me.name, size: 64, presence: s.onShift ? Presence.onShift : Presence.off),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(me.name, style: RgType.title2.copyWith(color: c.textPrimary)),
              Text([roleLabel(me.role), ?dept].join(' · '), style: TextStyle(fontSize: 15, color: c.textSecondary)),
            ]),
          ),
        ]),
      ),
      const SectionHeader('Status', padding: EdgeInsets.fromLTRB(16, 22, 16, 6)),
      RgCard(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(children: [
          switchRow('On shift', s.onShift, (v) => s.onShift = v),
          switchRow('Alert sound', s.alertSound, (v) => s.alertSound = v),
          switchRow('Show internal notes in chats', s.showInternal, (v) => s.showInternal = v, last: true),
        ]),
      ),
      const SectionHeader('Appearance', padding: EdgeInsets.fromLTRB(16, 22, 16, 6)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          for (final (m, label) in [(ThemeMode.system, 'System'), (ThemeMode.light, 'Light'), (ThemeMode.dark, 'Dark')]) ...[
            RgChip(label: label, selected: s.themeMode == m, onTap: () => s.themeMode = m),
            const SizedBox(width: 8),
          ],
        ]),
      ),
      const SectionHeader('Account', padding: EdgeInsets.fromLTRB(16, 22, 16, 6)),
      RgCard(
        child: Column(children: [
          for (final (i, (k, v)) in account.indexed)
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(0, 13, 14, 13),
                decoration: i < account.length - 1 ? hairlineBottom(context) : null,
                child: Row(children: [
                  Text(k, style: RgType.body.copyWith(color: c.textPrimary)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(v,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RgType.body.copyWith(color: c.textSecondary)),
                  ),
                ]),
              ),
            ),
        ]),
      ),
      if (s.tenants.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: RgButton(
            label: 'Switch Workspace',
            icon: Symbols.swap_horiz_rounded,
            variant: BtnVariant.secondary,
            size: BtnSize.lg,
            expand: true,
            onPressed: s.switchWorkspace,
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        child: RgButton(
          label: 'Sign Out',
          icon: Symbols.logout_rounded,
          variant: BtnVariant.outline,
          size: BtnSize.lg,
          expand: true,
          onPressed: s.signOut,
        ),
      ),
      const Center(child: Opacity(opacity: 0.8, child: Logo(height: 18))),
      const SizedBox(height: 110),
    ]);
  }
}
