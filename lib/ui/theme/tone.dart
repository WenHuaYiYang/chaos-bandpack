import 'package:flutter/material.dart';

import 'paper_palette.dart';

enum ThemeStyle { paper, md3 }

/// 每个页面的色相。制作台有一件事很讲究: 切页时**底色要跟着变**,
/// 用户不看标题也知道自己在哪一页。
@immutable
class PageTone {
  const PageTone({
    required this.field,
    required this.card,
    required this.capsule,
    required this.deep,
    required this.onDeep,
    required this.onField,
    required this.muted,
    required this.accent,
    required this.onAccent,
  });

  final Color field;
  final Color card;
  final Color capsule;
  final Color deep;
  final Color onDeep;
  final Color onField;
  final Color muted;
  final Color accent;
  final Color onAccent;

  /// 卡片按色相轻微染色。PAPER 档不动卡片(纸就该是白的), MD3 档才染。
  Color cardFor(Color tint) => card;
}

/// MD3 档的 cardFor 走插值; 抽成子类只是为了让默认档保持零开销。
class _Md3Tone extends PageTone {
  const _Md3Tone({
    required super.field,
    required super.card,
    required super.capsule,
    required super.deep,
    required super.onDeep,
    required super.onField,
    required super.muted,
    required super.accent,
    required super.onAccent,
  });

  @override
  Color cardFor(Color tint) => Color.lerp(card, tint, 0.30)!;
}

abstract final class TonePalette {
  static ThemeStyle style = ThemeStyle.paper;

  static PageTone of(BuildContext context) => home(context);

  static PageTone _make(ColorScheme s, Color tint) {
    if (style == ThemeStyle.md3) {
      return _Md3Tone(
        field: Color.lerp(s.surface, tint, 0.22)!,
        card: Color.lerp(s.surface, tint, 0.42)!,
        capsule: Color.lerp(s.surface, tint, 0.62)!,
        deep: tint,
        onDeep: _onColor(tint),
        onField: s.onSurface,
        muted: s.onSurfaceVariant,
        accent: tint,
        onAccent: _onColor(tint),
      );
    }
    // 深色下底栏与分段器底槽要比卡片暗, 滑块(=card)才像浮在上面;
    // 浅色下正好相反, 底槽本来就该比纸片暗一档。surfaceContainerHigh
    // 在深色语义里比 surface 亮, 直接拿来当底槽会把层次翻过来。
    final Color capsule = s.brightness == Brightness.dark
        ? Color.alphaBlend(const Color(0x4D000000), s.surface)
        : s.surfaceContainerHigh;
    return PageTone(
      field: s.surface,
      card: s.surfaceContainerLowest,
      capsule: capsule,
      deep: s.primary,
      onDeep: s.onPrimary,
      onField: s.onSurface,
      muted: s.onSurfaceVariant,
      accent: s.primary,
      onAccent: s.onPrimary,
    );
  }

  static Color _onColor(Color c) =>
      ThemeData.estimateBrightnessForColor(c) == Brightness.dark
          ? Colors.white
          : const Color(0xFF16150F);

  static PageTone home(BuildContext c) => _make(Theme.of(c).colorScheme, Theme.of(c).colorScheme.primary);
  static PageTone font(BuildContext c) => _make(Theme.of(c).colorScheme, Theme.of(c).colorScheme.secondary);
  static PageTone icon(BuildContext c) => _make(Theme.of(c).colorScheme, Theme.of(c).colorScheme.tertiary);
  static PageTone device(BuildContext c) => _make(Theme.of(c).colorScheme, Theme.of(c).colorScheme.secondary);
  static PageTone settings(BuildContext c) => _make(Theme.of(c).colorScheme, PaperPalette.sage);
  // 商店用桃色: 三个点缀色里只剩它没被一级页占用, 而且它最“货架”。
  static PageTone store(BuildContext c) => _make(Theme.of(c).colorScheme, PaperPalette.peach);
}

/// 按页面切换的色相, 由外层页面注入。
class ToneScope extends InheritedWidget {
  const ToneScope({required this.tone, required super.child, super.key});

  final PageTone tone;

  static PageTone of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ToneScope>()?.tone ??
      TonePalette.of(context);

  @override
  bool updateShouldNotify(ToneScope oldWidget) => oldWidget.tone != tone;
}
