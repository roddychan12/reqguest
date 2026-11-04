import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/tokens.dart';

/// Material Symbols Rounded icon with optional fill.
class RgIcon extends StatelessWidget {
  const RgIcon(this.icon, {super.key, this.size = 24, this.color, this.fill = false, this.weight = 400});
  final IconData icon;
  final double size;
  final Color? color;
  final bool fill;
  final double weight;

  @override
  Widget build(BuildContext context) => Icon(
        icon,
        size: size,
        color: color ?? RgColors.of(context).textPrimary,
        fill: fill ? 1 : 0,
        weight: weight,
        opticalSize: size.clamp(20, 48).toDouble(),
      );
}

/// 0.5px hairline separator.
class Hairline extends StatelessWidget {
  const Hairline({super.key});
  @override
  Widget build(BuildContext context) => Container(height: 0.5, color: RgColors.of(context).separator);
}

BoxDecoration hairlineBottom(BuildContext context) =>
    BoxDecoration(border: Border(bottom: BorderSide(color: RgColors.of(context).separator, width: 0.5)));

/// Frosted glass bar background.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.top = false, this.bottom = false});
  final Widget child;
  final bool top, bottom;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    final side = BorderSide(color: c.separator, width: 0.5);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surfaceGlass,
            border: Border(top: top ? side : BorderSide.none, bottom: bottom ? side : BorderSide.none),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Scales down slightly on press, like the DS `press` motion.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.97, this.pressedColor});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final Color? pressedColor;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: widget.onTap,
      child: widget.pressedColor != null
          ? ColoredBox(color: _down ? widget.pressedColor! : Colors.transparent, child: widget.child)
          : AnimatedScale(
              scale: _down ? widget.scale : 1,
              duration: const Duration(milliseconds: 120),
              child: widget.child,
            ),
    );
  }
}

// ── StatusBadge ──────────────────────────────────────────────────────────────

class StatusBadge extends StatefulWidget {
  const StatusBadge({super.key, required this.kind, required this.label, this.small = false});
  final StatusKind kind;
  final String label;
  final bool small;

  @override
  State<StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<StatusBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (widget.kind == StatusKind.newReq) _pulse.repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = RgColors.of(context).status[widget.kind]!;
    final dot = AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: s.dot,
          shape: BoxShape.circle,
          boxShadow: widget.kind == StatusKind.newReq
              ? [
                  BoxShadow(
                    color: const Color(0x732F6FEB).withValues(alpha: 0.45 * (1 - _pulse.value)),
                    spreadRadius: 6 * _pulse.value,
                  ),
                ]
              : null,
        ),
      ),
    );
    return Container(
      height: widget.small ? 20 : 24,
      padding: EdgeInsets.symmetric(horizontal: widget.small ? 8 : 10),
      decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        dot,
        const SizedBox(width: 6),
        Text(widget.label,
            style: TextStyle(fontSize: widget.small ? 12 : 13, fontWeight: FontWeight.w600, color: s.fg, height: 1)),
      ]),
    );
  }
}

// ── PriorityTag ──────────────────────────────────────────────────────────────

class PriorityTag extends StatelessWidget {
  const PriorityTag({super.key, required this.priority, this.showLabel = true});

  /// low | normal | high | urgent. `low` renders as normal (DS has no low variant).
  final String priority;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    final (IconData icon, Color iconColor, Color textColor, String label) = switch (priority) {
      'urgent' => (Symbols.priority_high_rounded, const Color(0xFFD12C22), c.dangerFg, 'Urgent'),
      'high' => (Symbols.keyboard_double_arrow_up_rounded, const Color(0xFFF59E0B), c.warningFg, 'High'),
      'low' => (Symbols.remove_rounded, c.priorityNormal, c.textSecondary, 'Low'),
      _ => (Symbols.remove_rounded, c.priorityNormal, c.textSecondary, 'Normal'),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      RgIcon(icon, size: 18, color: iconColor, weight: 600),
      if (showLabel) ...[
        const SizedBox(width: 2),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
      ],
    ]);
  }
}

// ── Avatars ──────────────────────────────────────────────────────────────────

/// Round tile tinted by department with a glyph (request type icon).
class GlyphAvatar extends StatelessWidget {
  const GlyphAvatar({super.key, required this.icon, required this.tint, this.size = 52, this.iconSize = 26});
  final IconData icon;
  final Color tint;
  final double size, iconSize;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
        child: RgIcon(icon, size: iconSize),
      );
}

enum Presence { onShift, onBreak, off }

/// Person avatar with initials and optional presence dot.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, this.size = 36, this.presence});
  final String name;
  final double size;
  final Presence? presence;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.take(2).map((w) => w[0].toUpperCase()).join();
    final tone = c.avatarTones[name.isEmpty ? 0 : name.codeUnitAt(0) % 5];
    final dot = (size * 0.28).clamp(8, double.infinity).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          child: Text(initials,
              style: TextStyle(fontSize: (size * 0.38).roundToDouble(), fontWeight: FontWeight.w600, color: c.textPrimary)),
        ),
        if (presence != null)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: switch (presence!) {
                  Presence.onShift => const Color(0xFF22DD60),
                  Presence.onBreak => const Color(0xFFF59E0B),
                  Presence.off => const Color(0xFFA3A3A3),
                },
                border: Border.all(color: c.surfaceCard, width: 2),
              ),
            ),
          ),
      ]),
    );
  }
}

// ── Chip ─────────────────────────────────────────────────────────────────────

class RgChip extends StatelessWidget {
  const RgChip({super.key, required this.label, required this.selected, required this.onTap, this.count});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    final fg = selected ? c.textInverse : c.textPrimary;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? c.surfaceInverse : c.surfaceCard,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? c.surfaceInverse : c.borderDefault),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: fg)),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 6),
            Opacity(
              opacity: 0.7,
              child: Text('$count',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: fg, fontFeatures: RgType.tabular)),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── SearchField ──────────────────────────────────────────────────────────────

class RgSearchField extends StatelessWidget {
  const RgSearchField({super.key, required this.controller, required this.placeholder, this.onChanged});
  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: c.surfaceSunken, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        RgIcon(Symbols.search_rounded, size: 20, color: c.textTertiary),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: TextStyle(fontSize: 17, color: c.textPrimary),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: placeholder,
              hintStyle: TextStyle(fontSize: 17, color: c.textTertiary),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: controller,
          builder: (_, _) => controller.text.isEmpty
              ? const SizedBox.shrink()
              : GestureDetector(
                  onTap: () {
                    controller.clear();
                    onChanged?.call('');
                  },
                  child: RgIcon(Symbols.cancel_rounded, size: 18, fill: true, color: c.textTertiary),
                ),
        ),
      ]),
    );
  }
}

// ── Button ───────────────────────────────────────────────────────────────────

enum BtnVariant { primary, secondary, outline, ghost, danger }

enum BtnSize { sm, md, lg }

class RgButton extends StatelessWidget {
  const RgButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = BtnVariant.primary,
    this.size = BtnSize.md,
    this.icon,
    this.expand = false,
    this.loading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final BtnVariant variant;
  final BtnSize size;
  final IconData? icon;
  final bool expand, loading;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    final (double h, double r, double fs, double px, double isz) = switch (size) {
      BtnSize.lg => (52.0, 14.0, 17.0, 20.0, 22.0),
      BtnSize.md => (44.0, 12.0, 16.0, 16.0, 20.0),
      BtnSize.sm => (34.0, 10.0, 14.0, 12.0, 18.0),
    };
    final (Color bg, Color fg, Color? border) = switch (variant) {
      BtnVariant.primary => (c.brand, c.textOnPrimary, null),
      BtnVariant.secondary => (c.surfaceSunken, c.textPrimary, null),
      BtnVariant.outline => (c.surfaceCard, c.textPrimary, c.borderStrong),
      BtnVariant.ghost => (Colors.transparent, c.textBrand, null),
      BtnVariant.danger => (c.dangerSolid, Colors.white, null),
    };
    final disabled = onPressed == null || loading;
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Pressable(
        onTap: disabled ? null : onPressed,
        child: Container(
          height: h,
          width: expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: px),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(r),
            border: border != null ? Border.all(color: border) : null,
          ),
          child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (loading)
              SizedBox(width: isz - 4, height: isz - 4, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
            else if (icon != null)
              RgIcon(icon!, size: isz, color: fg, weight: 500),
            if (loading || icon != null) const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: fs, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: fg)),
          ]),
        ),
      ),
    );
  }
}

// ── Switch ───────────────────────────────────────────────────────────────────

class RgSwitch extends StatelessWidget {
  const RgSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 51,
        height: 31,
        decoration: BoxDecoration(color: value ? c.brand : c.trackOff, borderRadius: BorderRadius.circular(16)),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: const Cubic(.34, 1.3, .64, 1),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(2),
            width: 27,
            height: 27,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [
              BoxShadow(color: Color(0x26000000), offset: Offset(0, 3), blurRadius: 8),
              BoxShadow(color: Color(0x29000000), offset: Offset(0, 1), blurRadius: 1),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── EmptyState ───────────────────────────────────────────────────────────────

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title, message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 88, 24, 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: c.brandTint, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: RgIcon(icon, size: 32, color: c.textBrand),
        ),
        const SizedBox(height: 16),
        Text(title, style: RgType.headline.copyWith(color: c.textPrimary)),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(message, textAlign: TextAlign.center, style: RgType.subhead.copyWith(color: c.textSecondary)),
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

// ── Sheet ────────────────────────────────────────────────────────────────────

Future<T?> showRgSheet<T>(BuildContext context, {required String title, required Widget Function(BuildContext) builder}) {
  final c = RgColors.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: c.surfaceOverlay,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
      child: Container(
        decoration: BoxDecoration(
          color: c.surfaceCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(RgRadius.sheet)),
          boxShadow: c.shadowSheet,
        ),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.paddingOf(ctx).bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Center(
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(color: c.borderStrong, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 12),
            Text(title, style: RgType.title3.copyWith(color: c.textPrimary)),
            const SizedBox(height: 12),
            builder(ctx),
          ]),
        ),
      ),
    ),
  );
}

// ── Toast ────────────────────────────────────────────────────────────────────

enum ToastTone { neutral, success, danger, warning }

class Toaster {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(
    BuildContext context,
    String message, {
    ToastTone tone = ToastTone.neutral,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    hide();
    final overlay = Overlay.of(context, rootOverlay: true);
    final c = RgColors.of(context);
    final iconColor = switch (tone) {
      ToastTone.neutral => const Color(0xFFC7C7C7),
      ToastTone.success => const Color(0xFF22DD60),
      ToastTone.danger => const Color(0xFFEF4136),
      ToastTone.warning => const Color(0xFFFDBA2C),
    };
    final ic = icon ??
        switch (tone) {
          ToastTone.neutral => Symbols.info_rounded,
          ToastTone.success => Symbols.check_circle_rounded,
          ToastTone.danger => Symbols.error_rounded,
          ToastTone.warning => Symbols.warning_rounded,
        };
    _entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.paddingOf(ctx).top + 8,
        left: 12,
        right: 12,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 320),
          curve: const Cubic(0, 0, 0, 1),
          builder: (_, t, child) =>
              Opacity(opacity: t, child: Transform.translate(offset: Offset(0, -12 * (1 - t)), child: child)),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.surfaceToast,
                borderRadius: BorderRadius.circular(14),
                boxShadow: c.shadow3,
              ),
              child: Row(children: [
                RgIcon(ic, size: 22, fill: true, color: iconColor),
                const SizedBox(width: 10),
                Expanded(child: Text(message, style: RgType.subhead.copyWith(color: c.textToast))),
                if (actionLabel != null)
                  GestureDetector(
                    onTap: () {
                      hide();
                      onAction?.call();
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
                      child: Text(actionLabel,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF22DD60))),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
    _timer = Timer(const Duration(milliseconds: 3500), hide);
  }

  static void hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

/// Uppercase section header used on Alerts / Team / You.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 6)});
  final String text;
  final String? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    final style = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: c.textSecondary);
    return Padding(
      padding: padding,
      child: Row(children: [
        Expanded(child: Text(text.toUpperCase(), style: style)),
        if (trailing != null) Text(trailing!, style: style.copyWith(fontFeatures: RgType.tabular)),
      ]),
    );
  }
}

/// White rounded card with shadow-1.
class RgCard extends StatelessWidget {
  const RgCard({super.key, required this.child, this.margin = const EdgeInsets.symmetric(horizontal: 16), this.radius = 12, this.padding});
  final Widget child;
  final EdgeInsets margin;
  final EdgeInsets? padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return Container(
      margin: margin,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.surfaceCard, borderRadius: BorderRadius.circular(radius), boxShadow: c.shadow1),
      child: child,
    );
  }
}

/// Large 34pt title.
class LargeTitle extends StatelessWidget {
  const LargeTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: RgType.largeTitle.copyWith(color: RgColors.of(context).textPrimary));
}
