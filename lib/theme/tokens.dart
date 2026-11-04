import 'package:flutter/material.dart';

/// ReqGuest Design System tokens, mirrored from the reference prototype.
/// Light and dark values live side by side; read them via `RgColors.of(context)`.
@immutable
class RgColors extends ThemeExtension<RgColors> {
  const RgColors({
    required this.brand,
    required this.brandPressed,
    required this.brandTint,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.textInverse,
    required this.textOnPrimary,
    required this.textBrand,
    required this.surfaceApp,
    required this.surfaceCard,
    required this.surfaceSunken,
    required this.surfaceRaised,
    required this.surfaceInverse,
    required this.surfaceOverlay,
    required this.surfaceGlass,
    required this.surfaceToast,
    required this.textToast,
    required this.trackOff,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderStrong,
    required this.separator,
    required this.successFg,
    required this.successBg,
    required this.dangerFg,
    required this.dangerBg,
    required this.dangerSolid,
    required this.warningFg,
    required this.warningBg,
    required this.infoFg,
    required this.infoBg,
    required this.ownBubble,
    required this.avatarTones,
    required this.priorityNormal,
    required this.status,
    required this.shadow1,
    required this.shadow3,
    required this.shadowSheet,
  });

  final Color brand, brandPressed, brandTint;
  final Color textPrimary, textSecondary, textTertiary, textDisabled, textInverse, textOnPrimary, textBrand;
  final Color surfaceApp, surfaceCard, surfaceSunken, surfaceRaised, surfaceInverse, surfaceOverlay, surfaceGlass;
  final Color surfaceToast, textToast, trackOff;
  final Color borderSubtle, borderDefault, borderStrong, separator;
  final Color successFg, successBg, dangerFg, dangerBg, dangerSolid, warningFg, warningBg, infoFg, infoBg;
  final Color ownBubble, priorityNormal;
  final List<Color> avatarTones;
  final Map<StatusKind, StatusColors> status;
  final List<BoxShadow> shadow1, shadow3, shadowSheet;

  static RgColors of(BuildContext context) => Theme.of(context).extension<RgColors>()!;

  static const light = RgColors(
    brand: Color(0xFF22DD60),
    brandPressed: Color(0xFF14B54C),
    brandTint: Color(0xFFEAFCF0),
    textPrimary: Color(0xFF141414),
    textSecondary: Color(0xFF666666),
    textTertiary: Color(0xFF7F7F7F),
    textDisabled: Color(0xFFA3A3A3),
    textInverse: Color(0xFFFFFFFF),
    textOnPrimary: Color(0xFF062B14),
    textBrand: Color(0xFF0B7A34),
    surfaceApp: Color(0xFFF5F5F5),
    surfaceCard: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEDEDED),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceInverse: Color(0xFF141414),
    surfaceOverlay: Color(0x66141414),
    surfaceGlass: Color(0xD1FFFFFF),
    surfaceToast: Color(0xFF141414),
    textToast: Color(0xFFFFFFFF),
    trackOff: Color(0xFFE0E0E0),
    borderSubtle: Color(0xFFEDEDED),
    borderDefault: Color(0xFFE0E0E0),
    borderStrong: Color(0xFFC7C7C7),
    separator: Color(0x1A141414),
    successFg: Color(0xFF0B7A34),
    successBg: Color(0xFFEAFCF0),
    dangerFg: Color(0xFFD12C22),
    dangerBg: Color(0xFFFDEDEC),
    dangerSolid: Color(0xFFD12C22),
    warningFg: Color(0xFF9A5B00),
    warningBg: Color(0xFFFFF5DB),
    infoFg: Color(0xFF1F5AD0),
    infoBg: Color(0xFFEAF1FE),
    ownBubble: Color(0xFFCFF8DC),
    priorityNormal: Color(0xFFA3A3A3),
    avatarTones: [Color(0xFFCFF8DC), Color(0xFFE0E0E0), Color(0xFFEAF1FE), Color(0xFFFFF5DB), Color(0xFFFDEDEC)],
    status: {
      StatusKind.newReq: StatusColors(Color(0xFF1F5AD0), Color(0xFFEAF1FE), Color(0xFF2F6FEB)),
      StatusKind.acknowledged: StatusColors(Color(0xFF333333), Color(0xFFEDEDED), Color(0xFF666666)),
      StatusKind.inProgress: StatusColors(Color(0xFF9A5B00), Color(0xFFFFF5DB), Color(0xFFF59E0B)),
      StatusKind.completed: StatusColors(Color(0xFF0B7A34), Color(0xFFEAFCF0), Color(0xFF22DD60)),
      StatusKind.cancelled: StatusColors(Color(0xFF666666), Color(0xFFF5F5F5), Color(0xFFA3A3A3)),
      StatusKind.overdue: StatusColors(Color(0xFFD12C22), Color(0xFFFDEDEC), Color(0xFFEF4136)),
    },
    shadow1: [
      BoxShadow(color: Color(0x0F141414), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(color: Color(0x0A141414), spreadRadius: 1),
    ],
    shadow3: [BoxShadow(color: Color(0x29141414), offset: Offset(0, 12), blurRadius: 32)],
    shadowSheet: [BoxShadow(color: Color(0x24141414), offset: Offset(0, -8), blurRadius: 30)],
  );

  static const dark = RgColors(
    brand: Color(0xFF22DD60),
    brandPressed: Color(0xFF14B54C),
    brandTint: Color(0x2422DD60),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFFA3A3A3),
    textTertiary: Color(0xFF8A8A8A),
    textDisabled: Color(0xFF5C5C5C),
    textInverse: Color(0xFF141414),
    textOnPrimary: Color(0xFF062B14),
    textBrand: Color(0xFF3FE276),
    surfaceApp: Color(0xFF0B0B0B),
    surfaceCard: Color(0xFF1A1A1A),
    surfaceSunken: Color(0xFF2A2A2A),
    surfaceRaised: Color(0xFF242424),
    surfaceInverse: Color(0xFFF5F5F5),
    surfaceOverlay: Color(0x99000000),
    surfaceGlass: Color(0xC7161616),
    surfaceToast: Color(0xFF2E2E2E),
    textToast: Color(0xFFF5F5F5),
    trackOff: Color(0xFF3A3A3A),
    borderSubtle: Color(0xFF242424),
    borderDefault: Color(0xFF333333),
    borderStrong: Color(0xFF474747),
    separator: Color(0x1FFFFFFF),
    successFg: Color(0xFF3FE276),
    successBg: Color(0x2422DD60),
    dangerFg: Color(0xFFFF6B61),
    dangerBg: Color(0x29EF4136),
    dangerSolid: Color(0xFFD12C22),
    warningFg: Color(0xFFFDBA2C),
    warningBg: Color(0x29F59E0B),
    infoFg: Color(0xFF7EA6FF),
    infoBg: Color(0x332F6FEB),
    ownBubble: Color(0xFF094620),
    priorityNormal: Color(0xFF666666),
    avatarTones: [Color(0xFF0F3D20), Color(0xFF333333), Color(0xFF1B2D52), Color(0xFF4A3508), Color(0xFF4D1A17)],
    status: {
      StatusKind.newReq: StatusColors(Color(0xFF8AB0FF), Color(0x332F6FEB), Color(0xFF5B8CFF)),
      StatusKind.acknowledged: StatusColors(Color(0xFFE0E0E0), Color(0xFF2A2A2A), Color(0xFFA3A3A3)),
      StatusKind.inProgress: StatusColors(Color(0xFFFDBA2C), Color(0x29F59E0B), Color(0xFFF59E0B)),
      StatusKind.completed: StatusColors(Color(0xFF3FE276), Color(0x2422DD60), Color(0xFF22DD60)),
      StatusKind.cancelled: StatusColors(Color(0xFF8A8A8A), Color(0xFF202020), Color(0xFF5C5C5C)),
      StatusKind.overdue: StatusColors(Color(0xFFFF6B61), Color(0x29EF4136), Color(0xFFEF4136)),
    },
    shadow1: [BoxShadow(color: Color(0x0FFFFFFF), spreadRadius: 1)],
    shadow3: [
      BoxShadow(color: Color(0x99000000), offset: Offset(0, 12), blurRadius: 32),
      BoxShadow(color: Color(0x14FFFFFF), spreadRadius: 1),
    ],
    shadowSheet: [BoxShadow(color: Color(0x80000000), offset: Offset(0, -8), blurRadius: 30)],
  );

  @override
  RgColors copyWith() => this;

  @override
  RgColors lerp(RgColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

enum StatusKind { newReq, acknowledged, inProgress, completed, cancelled, overdue }

@immutable
class StatusColors {
  const StatusColors(this.fg, this.bg, this.dot);
  final Color fg, bg, dot;
}

/// Text roles (size / line height / weight / tracking) from the DS type scale.
class RgType {
  static const _tab = [FontFeature.tabularFigures()];

  static TextStyle _s(double size, double lh, FontWeight w, double ls) =>
      TextStyle(fontSize: size, height: lh / size, fontWeight: w, letterSpacing: ls);

  static final largeTitle = _s(34, 41, FontWeight.w700, 0.37);
  static final title2 = _s(22, 28, FontWeight.w700, 0.35);
  static final title3 = _s(20, 25, FontWeight.w600, 0.38);
  static final headline = _s(17, 22, FontWeight.w600, -0.41);
  static final body = _s(17, 22, FontWeight.w400, -0.41);
  static final callout = _s(16, 21, FontWeight.w400, -0.32);
  static final subhead = _s(15, 20, FontWeight.w400, -0.24);
  static final footnote = _s(13, 18, FontWeight.w400, -0.08);
  static final caption1 = _s(12, 16, FontWeight.w400, 0);
  static final caption2 = _s(11, 13, FontWeight.w500, 0.06);

  static const tabular = _tab;
}

class RgRadius {
  static const xs = 6.0, sm = 10.0, md = 12.0, lg = 16.0, xl = 20.0, sheet = 24.0;
}

ThemeData buildTheme(Brightness b) {
  final c = b == Brightness.light ? RgColors.light : RgColors.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    scaffoldBackgroundColor: c.surfaceApp,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.brand,
      brightness: b,
      primary: c.brand,
      onPrimary: c.textOnPrimary,
      surface: c.surfaceCard,
      onSurface: c.textPrimary,
    ),
    textTheme: Typography.material2021(platform: TargetPlatform.iOS).black.apply(
          bodyColor: c.textPrimary,
          displayColor: c.textPrimary,
        ),
    dividerColor: c.separator,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.textBrand),
    extensions: [c],
  );
}
