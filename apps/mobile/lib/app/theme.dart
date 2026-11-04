/// 丧萌纸感视觉 token，与 docs/02-interaction-and-visual.md 对齐。
library;

import 'package:flutter/material.dart';

@immutable
final class FjobPalette extends ThemeExtension<FjobPalette> {
  const FjobPalette({
    required this.paper,
    required this.panel,
    required this.ink,
    required this.muted,
    required this.line,
    required this.soft,
    required this.yellow,
    required this.rose,
    required this.negative,
    required this.positive,
  });

  static const FjobPalette light = FjobPalette(
    paper: Color(0xFFF7F2E9),
    panel: Color(0xFFFFFDF7),
    ink: Color(0xFF323A32),
    muted: Color(0xFF686E61),
    line: Color(0xFFD5D6C8),
    soft: Color(0xFFE9EDDF),
    yellow: Color(0xFFF2DFAC),
    rose: Color(0xFFF0D2C5),
    negative: Color(0xFFAD4736),
    positive: Color(0xFF46644E),
  );

  final Color paper;
  final Color panel;
  final Color ink;
  final Color muted;
  final Color line;
  final Color soft;
  final Color yellow;
  final Color rose;
  final Color negative;
  final Color positive;

  @override
  FjobPalette copyWith({
    Color? paper,
    Color? panel,
    Color? ink,
    Color? muted,
    Color? line,
    Color? soft,
    Color? yellow,
    Color? rose,
    Color? negative,
    Color? positive,
  }) =>
      FjobPalette(
        paper: paper ?? this.paper,
        panel: panel ?? this.panel,
        ink: ink ?? this.ink,
        muted: muted ?? this.muted,
        line: line ?? this.line,
        soft: soft ?? this.soft,
        yellow: yellow ?? this.yellow,
        rose: rose ?? this.rose,
        negative: negative ?? this.negative,
        positive: positive ?? this.positive,
      );

  @override
  FjobPalette lerp(ThemeExtension<FjobPalette>? other, double t) {
    if (other is! FjobPalette) return this;
    return FjobPalette(
      paper: Color.lerp(paper, other.paper, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
      yellow: Color.lerp(yellow, other.yellow, t)!,
      rose: Color.lerp(rose, other.rose, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
      positive: Color.lerp(positive, other.positive, t)!,
    );
  }
}

extension PaletteContext on BuildContext {
  FjobPalette get palette => Theme.of(this).extension<FjobPalette>()!;
}

abstract final class FjobTheme {
  static ThemeData light() => _build(Brightness.light, FjobPalette.light);

  static ThemeData _build(Brightness brightness, FjobPalette palette) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Microsoft YaHei',
      scaffoldBackgroundColor: palette.paper,
      canvasColor: palette.paper,
      dividerColor: palette.line,
      splashFactory: InkSparkle.splashFactory,
    );
    final textTheme = base.textTheme.copyWith(
      displayLarge: TextStyle(
        fontSize: 42,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.4,
        color: palette.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      headlineMedium: TextStyle(
        fontSize: 25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: palette.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: palette.ink,
      ),
      bodyMedium: TextStyle(fontSize: 14, color: palette.ink, height: 1.5),
      bodySmall: TextStyle(fontSize: 12, color: palette.muted, height: 1.5),
      labelSmall: TextStyle(
        fontSize: 10,
        color: palette.muted,
        letterSpacing: 1.2,
      ),
    );
    return base.copyWith(
      textTheme: textTheme.apply(fontFamily: 'Microsoft YaHei'),
      extensions: <ThemeExtension<dynamic>>[palette],
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.positive,
        brightness: brightness,
        primary: palette.positive,
        onPrimary: palette.panel,
        secondary: palette.yellow,
        onSecondary: palette.ink,
        surface: palette.panel,
        onSurface: palette.ink,
        error: palette.negative,
      ),
      cardTheme: CardThemeData(
        color: palette.panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.ink, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(color: palette.line, space: 1, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.paper,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.positive, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.negative),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.negative, width: 1.6),
        ),
        labelStyle: TextStyle(color: palette.muted, fontSize: 12),
        errorStyle: TextStyle(color: palette.negative, fontSize: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.soft,
          foregroundColor: palette.ink,
          minimumSize: const Size.fromHeight(48),
          textStyle: const TextStyle(
            fontFamily: 'Microsoft YaHei',
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: palette.ink),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.ink,
          minimumSize: const Size(44, 44),
          side: BorderSide(color: palette.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: palette.muted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.panel,
        indicatorColor: palette.soft,
        height: 66,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            color: palette.muted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w400,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 20,
            color: states.contains(WidgetState.selected)
                ? palette.ink
                : palette.muted,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.ink,
        contentTextStyle: TextStyle(color: palette.paper),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.ink, width: 1.5),
        ),
      ),
    );
  }
}

/// Reusable hand-drawn-looking panel with a heavy outline.
class PaperCard extends StatelessWidget {
  const PaperCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.radius = 18,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final decorated = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? palette.panel,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: palette.ink, width: 1.5),
      ),
      child: child,
    );
    if (onTap == null) return decorated;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: decorated,
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      );
}

class MoneyText extends StatelessWidget {
  const MoneyText(
    this.text, {
    super.key,
    this.color,
    this.size,
    this.weight = FontWeight.w700,
  });

  final String text;
  final Color? color;
  final double? size;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontFamily: 'Consolas',
          fontFamilyFallback: const ['monospace'],
          fontSize: size ?? 15,
          fontWeight: weight,
          letterSpacing: -0.2,
          color: color ?? context.palette.ink,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
}
