import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// bandpack 的默认主题「纸」: 冷灰页底 + 暖白卡片, 三个点缀色。
///
/// 数值逐个对照 Kotlin 版 ui/theme/PaperPalette.kt, 不要凭感觉调 —— 手环上的
/// 预览块与 App 里的配色是同一套观感, 改这里也要改 preview 的常量。
abstract final class PaperPalette {
  static const Color page = Color(0xFFF1F1F1);
  static const Color card = Color(0xFFFCFBF9);
  static const Color blue = Color(0xFF4890CC);
  static const Color sage = Color(0xFF7E9C90);
  static const Color peach = Color(0xFFD89C84);

  /// 深色档刻意不用纯黑: 页面 #1B1A18、卡片 #262422, 纸片比页底亮一档,
  /// 卡片才浮得起来。纯黑底 + 近黑卡片会糊成一块, 分不清哪里能点。
  static const Color pageDark = Color(0xFF1B1A18);
  static const Color cardDark = Color(0xFF262422);
  static const Color blueDark = Color(0xFF9CC7EC);
  static const Color sageDark = Color(0xFFAEC7BC);
  static const Color peachDark = Color(0xFFE8BCA8);

  /// 形状尺度(dp)。刻意不做 pill: 20 dp 的圆角在 400dp 宽的卡片上才是
  /// “纸片”的比例, 再大就成了胶囊。
  static const double shapeXs = 8;
  static const double shapeSm = 12;
  static const double shapeMd = 16;
  static const double shapeLg = 20;
  static const double shapeXl = 24;

  /// 无边框输入框。圆角必须显式给: 留空时 Material 默认 4 dp,
  /// 在 shapeMd/shapeLg 的卡片里会显得像另一个应用。
  static const OutlineInputBorder none = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(shapeMd)),
    borderSide: BorderSide.none,
  );

  static const RoundedRectangleBorder cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(shapeLg)),
  );

  static ThemeData theme(Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    final ColorScheme scheme = dark ? _darkScheme : _lightScheme;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      fontFamily: 'MiSans',
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: _textTheme(scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: cardShape,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: none,
        enabledBorder: none,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapeMd),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(shapeMd)),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(shapeSm)),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(shapeMd)),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme s) => TextTheme(
        displaySmall: TextStyle(color: s.onSurface, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        headlineMedium: TextStyle(color: s.onSurface, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.4),
        headlineSmall: TextStyle(color: s.onSurface, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        titleLarge: TextStyle(color: s.onSurface, fontSize: 18, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: s.onSurface, fontSize: 16, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: s.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3),
        bodyLarge: TextStyle(color: s.onSurface, fontSize: 15, height: 1.45),
        bodyMedium: TextStyle(color: s.onSurface, fontSize: 14, height: 1.45),
        bodySmall: TextStyle(color: s.onSurfaceVariant, fontSize: 12.5, height: 1.4),
        labelLarge: TextStyle(color: s.onSurface, fontSize: 14, fontWeight: FontWeight.w600),
        labelSmall: TextStyle(color: s.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.4),
      );

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF3E86C4),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDCEBFA),
    onPrimaryContainer: Color(0xFF10314D),
    secondary: Color(0xFF5F7F73),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFDCE8E3),
    onSecondaryContainer: Color(0xFF1B2A24),
    tertiary: Color(0xFFB87A5F),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFF7E3DA),
    onTertiaryContainer: Color(0xFF3D221A),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B),
    surface: page,
    onSurface: Color(0xFF1C1B1A),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F5F3),
    surfaceContainer: Color(0xFFF2F0EE),
    surfaceContainerHigh: Color(0xFFECE9E6),
    surfaceContainerHighest: Color(0xFFE6E3DF),
    onSurfaceVariant: Color(0xFF4A4744),
    outline: Color(0xFF8A8580),
    outlineVariant: Color(0xFFDCD8D3),
    inverseSurface: Color(0xFF2C2B29),
    onInverseSurface: Color(0xFFF3F1EF),
    shadow: Color(0x1A000000),
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF9CC7EC),
    onPrimary: Color(0xFF06263D),
    primaryContainer: Color(0xFF24455F),
    onPrimaryContainer: Color(0xFFDCEBFA),
    secondary: Color(0xFFAEC7BC),
    onSecondary: Color(0xFF16241F),
    secondaryContainer: Color(0xFF37473F),
    onSecondaryContainer: Color(0xFFDCE8E3),
    tertiary: Color(0xFFE8BCA8),
    onTertiary: Color(0xFF3B2218),
    tertiaryContainer: Color(0xFF57382A),
    onTertiaryContainer: Color(0xFFF7E3DA),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFF9DEDC),
    surface: pageDark,
    onSurface: Color(0xFFEDEAE7),
    surfaceContainerLowest: cardDark,
    surfaceContainerLow: Color(0xFF201F1D),
    surfaceContainer: Color(0xFF2C2A27),
    surfaceContainerHigh: Color(0xFF353230),
    surfaceContainerHighest: Color(0xFF403C39),
    onSurfaceVariant: Color(0xFFC6C0BA),
    outline: Color(0xFF8A8580),
    outlineVariant: Color(0xFF3E3B37),
    inverseSurface: Color(0xFFEDEAE7),
    onInverseSurface: Color(0xFF2C2B29),
    shadow: Color(0x1A000000),
  );
}
