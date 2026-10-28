import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The visual language used by the app.
///
/// * [apple]  - macOS: SF typography, grouped inset cards, hairline borders.
/// * [fluent] - Windows 11: Mica-like surfaces, 8px layers, 4px controls.
/// * [yaru]   - Ubuntu: Yaru palette, Ubuntu orange, soft 6px controls.
/// * [material] - Android / iOS: the original rounded, gradient look.
enum DesignStyle {
  material,
  apple,
  fluent,
  yaru;

  static DesignStyle get current {
    if (kIsWeb) return material;
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS => apple,
      TargetPlatform.windows => fluent,
      TargetPlatform.linux => yaru,
      _ => material,
    };
  }

  bool get isDesktop => this != material;
}

/// Design tokens attached to the [ThemeData] so every widget can adapt.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.style,
    required this.accent,
    required this.onAccent,
    required this.sidebar,
    required this.background,
    required this.card,
    required this.border,
    required this.radiusCard,
    required this.radiusControl,
    required this.controlHeight,
    required this.shadows,
    required this.success,
  });

  final DesignStyle style;
  final Color accent;
  final Color onAccent;

  /// Left pane (desktop) background.
  final Color sidebar;

  /// Page background.
  final Color background;
  final Color card;
  final Color border;
  final double radiusCard;
  final double radiusControl;
  final double controlHeight;
  final List<BoxShadow> shadows;
  final Color success;

  @override
  AppTokens copyWith({DesignStyle? style}) => AppTokens(
    style: style ?? this.style,
    accent: accent,
    onAccent: onAccent,
    sidebar: sidebar,
    background: background,
    card: card,
    border: border,
    radiusCard: radiusCard,
    radiusControl: radiusControl,
    controlHeight: controlHeight,
    shadows: shadows,
    success: success,
  );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) => this;
}

extension AppTokensX on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;

  /// Layout breakpoint shared by the home screen and the mini player.
  ///
  /// The design style still follows the host platform, but web and tablets
  /// can be wide even when they use the Material theme. Keeping this separate
  /// from [AppTokens.style] makes the responsive behaviour predictable.
  bool get isDesktopLayout =>
      tokens.style.isDesktop || MediaQuery.sizeOf(this).width >= 900;
}

class AppTheme {
  AppTheme._();

  /// Legacy brand colours used by the mobile look.
  static const red = Color(0xFFE53935);
  static const brandGradient = LinearGradient(
    colors: [Color(0xFFFF5252), Color(0xFFD50000)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData light([DesignStyle? style]) =>
      _build(style ?? DesignStyle.current, Brightness.light);

  static ThemeData dark([DesignStyle? style]) =>
      _build(style ?? DesignStyle.current, Brightness.dark);

  static AppTokens _tokens(DesignStyle style, Brightness b) {
    final dark = b == Brightness.dark;
    switch (style) {
      case DesignStyle.apple:
        return AppTokens(
          style: style,
          accent: dark ? const Color(0xFFFF4D5E) : const Color(0xFFFA233B),
          onAccent: Colors.white,
          sidebar: dark ? const Color(0xFF262628) : const Color(0xFFE9E9EC),
          background: dark ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F7),
          card: dark ? const Color(0xFF2C2C2E) : Colors.white,
          border: dark ? const Color(0x1FFFFFFF) : const Color(0x14000000),
          radiusCard: 12,
          radiusControl: 8,
          controlHeight: 34,
          shadows: const [],
          success: const Color(0xFF30B454),
        );
      case DesignStyle.fluent:
        return AppTokens(
          style: style,
          accent: dark ? const Color(0xFF4CC2FF) : const Color(0xFF0067C0),
          onAccent: dark ? const Color(0xFF000000) : Colors.white,
          sidebar: dark ? const Color(0xFF1B1B1B) : const Color(0xFFEEEEEE),
          background: dark ? const Color(0xFF202020) : const Color(0xFFF3F3F3),
          card: dark ? const Color(0xFF2B2B2B) : const Color(0xFFFBFBFB),
          border: dark ? const Color(0xFF3B3B3B) : const Color(0xFFE5E5E5),
          radiusCard: 8,
          radiusControl: 4,
          controlHeight: 36,
          shadows: dark
              ? const []
              : const [
                  BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
          success: dark ? const Color(0xFF6CCB5F) : const Color(0xFF0F7B0F),
        );
      case DesignStyle.yaru:
        return AppTokens(
          style: style,
          accent: const Color(0xFFE95420),
          onAccent: Colors.white,
          sidebar: dark ? const Color(0xFF232323) : const Color(0xFFEFEFEF),
          background: dark ? const Color(0xFF2B2B2B) : const Color(0xFFFAFAFA),
          card: dark ? const Color(0xFF353535) : Colors.white,
          border: dark ? const Color(0xFF484848) : const Color(0xFFDADADA),
          radiusCard: 8,
          radiusControl: 6,
          controlHeight: 38,
          shadows: const [],
          success: dark ? const Color(0xFF4CAF50) : const Color(0xFF2E7D32),
        );
      case DesignStyle.material:
        return AppTokens(
          style: style,
          accent: dark ? const Color(0xFFFFFFFF) : const Color(0xFF111318),
          onAccent: dark ? const Color(0xFF111318) : Colors.white,
          sidebar: dark ? const Color(0xFF17191E) : const Color(0xFFE8EBEF),
          background: dark ? const Color(0xFF0D0E11) : const Color(0xFFF1F3F5),
          card: dark ? const Color(0xFF191B20) : Colors.white,
          border: dark ? const Color(0x33FFFFFF) : const Color(0xFFE3E6EA),
          radiusCard: 18,
          radiusControl: 12,
          controlHeight: 52,
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
          success: const Color(0xFF238636),
        );
    }
  }

  static ThemeData _build(DesignStyle style, Brightness brightness) {
    final t = _tokens(style, brightness);
    final dark = brightness == Brightness.dark;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: t.accent,
          brightness: brightness,
        ).copyWith(
          primary: t.accent,
          onPrimary: t.onAccent,
          surface: t.card,
          surfaceContainerLowest: t.background,
          surfaceContainerHighest: dark
              ? Color.alphaBlend(const Color(0x1AFFFFFF), t.card)
              : Color.alphaBlend(const Color(0x0D000000), t.card),
          outlineVariant: t.border,
        );

    final fontFamily = switch (style) {
      DesignStyle.fluent => 'Segoe UI Variable Text',
      DesignStyle.yaru => 'Ubuntu',
      _ => null,
    };
    final fallback = switch (style) {
      DesignStyle.fluent => const ['Segoe UI', 'Arial'],
      DesignStyle.yaru => const ['Cantarell', 'Noto Sans', 'DejaVu Sans'],
      _ => null,
    };

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      fontFamilyFallback: fallback,
      scaffoldBackgroundColor: t.background,
      visualDensity: style.isDesktop
          ? VisualDensity.compact
          : VisualDensity.standard,
    );

    // Desktop UIs use slightly smaller type (13px body) than touch UIs.
    final textTheme = style.isDesktop
        ? _scaleText(base.textTheme, 0.93)
        : base.textTheme;

    final controlRadius = BorderRadius.circular(t.radiusControl);
    final fieldFill = style == DesignStyle.material
        ? t.card
        : (dark ? const Color(0x14FFFFFF) : const Color(0x0A000000));

    OutlineInputBorder field(Color color, double width) => OutlineInputBorder(
      borderRadius: controlRadius,
      borderSide: width == 0
          ? BorderSide.none
          : BorderSide(color: color, width: width),
    );

    final isMaterial = style == DesignStyle.material;

    return base.copyWith(
      extensions: [t],
      textTheme: textTheme,
      dividerColor: t.border,
      dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: scheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        isDense: style.isDesktop,
        border: field(t.border, isMaterial ? 0 : 1),
        enabledBorder: field(t.border, isMaterial ? 0 : 1),
        focusedBorder: field(t.accent, isMaterial ? 1.6 : 2),
        contentPadding: EdgeInsets.symmetric(
          horizontal: isMaterial ? 18 : 12,
          vertical: isMaterial ? 18 : 11,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          minimumSize: Size(0, t.controlHeight),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
          elevation: 0,
          textStyle: TextStyle(
            fontSize: isMaterial ? 16 : 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: t.border),
          minimumSize: Size(0, t.controlHeight),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
          textStyle: TextStyle(
            fontSize: isMaterial ? 16 : 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.accent,
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.accent,
        linearTrackColor: dark
            ? const Color(0x22FFFFFF)
            : const Color(0x14000000),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(style.isDesktop ? 8 : 4),
        radius: const Radius.circular(8),
        thumbColor: WidgetStateProperty.all(
          dark ? const Color(0x55FFFFFF) : const Color(0x44000000),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            isMaterial ? 14 : t.radiusControl,
          ),
        ),
        width: isMaterial ? null : 420,
      ),
    );
  }

  /// Scales every Material 3 text style (sizes may be unset on the base theme).
  static TextTheme _scaleText(TextTheme t, double f) {
    TextStyle? sc(TextStyle? s, double size) => s?.copyWith(fontSize: size * f);
    return t.copyWith(
      displayLarge: sc(t.displayLarge, 57),
      displayMedium: sc(t.displayMedium, 45),
      displaySmall: sc(t.displaySmall, 36),
      headlineLarge: sc(t.headlineLarge, 32),
      headlineMedium: sc(t.headlineMedium, 28),
      headlineSmall: sc(t.headlineSmall, 24),
      titleLarge: sc(t.titleLarge, 22),
      titleMedium: sc(t.titleMedium, 16),
      titleSmall: sc(t.titleSmall, 14),
      bodyLarge: sc(t.bodyLarge, 16),
      bodyMedium: sc(t.bodyMedium, 14),
      bodySmall: sc(t.bodySmall, 12),
      labelLarge: sc(t.labelLarge, 14),
      labelMedium: sc(t.labelMedium, 12),
      labelSmall: sc(t.labelSmall, 11),
    );
  }

  /// True on the desktop operating systems.
  static bool get isDesktopOs =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
}
