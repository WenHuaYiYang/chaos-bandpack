import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../font/charset.dart';
import 'theme/tone.dart';

/// 玻璃底栏的两种光学版本。iOS 26 的折射更重、边缘更亮; iOS 27 更克制。
enum NavGlassStyle { ios26, ios27 }

extension NavGlassStyleInfo on NavGlassStyle {
  String get label => switch (this) {
        NavGlassStyle.ios26 => 'iOS 26',
        NavGlassStyle.ios27 => 'iOS 27',
      };
}

/// 外观模式: 跟随系统 / 强制浅色 / 强制深色。
enum Appearance { system, light, dark }

extension AppearanceInfo on Appearance {
  String get label => switch (this) {
        Appearance.system => '跟随系统',
        Appearance.light => '浅色',
        Appearance.dark => '深色',
      };

  ThemeMode get mode => switch (this) {
        Appearance.system => ThemeMode.system,
        Appearance.light => ThemeMode.light,
        Appearance.dark => ThemeMode.dark,
      };
}

/// 界面偏好: 外观 / 风格 / 底栏文字 / 制作默认值。
///
/// 为什么单拎一个对象: 这几项全应用读写、要落盘、还要让页面跟着刷新。
/// ChangeNotifier 负责刷新, SharedPreferences 负责落盘; 测试里没有插件时
/// 走内存档(_sp 为 null), 读写照常但不落盘。
class UiPrefs extends ChangeNotifier {
  UiPrefs._(this._sp);

  final SharedPreferences? _sp;
  static UiPrefs? _instance;

  /// 全局实例。main() 先 await load() 把落盘的偏好读进来; 测试直接拿默认值。
  static UiPrefs get instance => _instance ??= UiPrefs._(null);

  static Future<UiPrefs> load() async {
    SharedPreferences? sp;
    try {
      sp = await SharedPreferences.getInstance();
    } catch (_) {
      sp = null;
    }
    final UiPrefs prefs = UiPrefs._(sp);
    prefs._read();
    _instance = prefs;
    return prefs;
  }

  static const String _kAppearance = 'appearance';
  static const String _kStyle = 'theme_style';
  static const String _kNavLabels = 'nav_labels';
  static const String _kNavGlass = 'nav_glass';
  static const String _kGlassStyle = 'nav_glass_style';
  static const String _kGlassTint = 'nav_glass_tint';
  static const String _kGlassBlur = 'nav_glass_blur';
  static const String _kGlassGlow = 'nav_glass_glow';
  static const String _kRailCollapsed = 'rail_collapsed';
  static const String _kKind = 'kind';
  static const String _kNormalize = 'normalize';

  Appearance _appearance = Appearance.system;
  ThemeStyle _style = ThemeStyle.paper;
  bool _navLabels = true;
  bool _navGlass = false;
  NavGlassStyle _glassStyle = NavGlassStyle.ios27;
  int _glassTint = 50;
  int _glassBlur = 55;
  bool _glassGlow = true;
  bool _railCollapsed = false;
  Kind _kind = Kind.simplified;
  bool _normalize = true;

  Appearance get appearance => _appearance;
  ThemeStyle get style => _style;
  bool get navLabels => _navLabels;

  /// 底栏是否用液态玻璃。默认关闭: 老底栏是纸片风格的一部分, 新效果要用户主动开。
  bool get navGlass => _navGlass;
  NavGlassStyle get glassStyle => _glassStyle;

  /// 玻璃的染色浓度 0..100: 越大越不透明, 文字在花哨壁纸上也读得清。
  int get glassTint => _glassTint;

  /// 模糊强度 0..100, 映射到库里的 blur 半径。
  int get glassBlur => _glassBlur;

  /// 选中格的辉光。关掉更接近 iOS 的克制版本。
  bool get glassGlow => _glassGlow;

  /// 宽屏侧栏是否收起成图标条。窗口够宽时默认展开。
  bool get railCollapsed => _railCollapsed;
  Kind get defaultKind => _kind;
  bool get defaultNormalize => _normalize;

  /// 落盘的字段名一样, 读坏了就退回默认值 —— 老装机没有这些键是常态。
  void _read() {
    final SharedPreferences? sp = _sp;
    if (sp == null) return;
    _appearance = Appearance.values.firstWhere(
      (Appearance v) => v.name == sp.getString(_kAppearance),
      orElse: () => Appearance.system,
    );
    _style = ThemeStyle.values.firstWhere(
      (ThemeStyle v) => v.name == sp.getString(_kStyle),
      orElse: () => ThemeStyle.paper,
    );
    _navLabels = sp.getBool(_kNavLabels) ?? true;
    _navGlass = sp.getBool(_kNavGlass) ?? false;
    _glassStyle = NavGlassStyle.values.firstWhere(
      (NavGlassStyle v) => v.name == sp.getString(_kGlassStyle),
      orElse: () => NavGlassStyle.ios27,
    );
    _glassTint = (sp.getInt(_kGlassTint) ?? 50).clamp(0, 100);
    _glassBlur = (sp.getInt(_kGlassBlur) ?? 55).clamp(0, 100);
    _glassGlow = sp.getBool(_kGlassGlow) ?? true;
    _railCollapsed = sp.getBool(_kRailCollapsed) ?? false;
    _kind = Kind.values.firstWhere(
      (Kind v) => v.name == sp.getString(_kKind),
      orElse: () => Kind.simplified,
    );
    _normalize = sp.getBool(_kNormalize) ?? true;
  }

  void setAppearance(Appearance v) {
    if (v == _appearance) return;
    _appearance = v;
    _sp?.setString(_kAppearance, v.name);
    notifyListeners();
  }

  void setStyle(ThemeStyle v) {
    if (v == _style) return;
    _style = v;
    TonePalette.style = v;
    _sp?.setString(_kStyle, v.name);
    notifyListeners();
  }

  void setNavLabels(bool v) {
    if (v == _navLabels) return;
    _navLabels = v;
    _sp?.setBool(_kNavLabels, v);
    notifyListeners();
  }

  void setNavGlass(bool v) {
    if (v == _navGlass) return;
    _navGlass = v;
    _sp?.setBool(_kNavGlass, v);
    notifyListeners();
  }

  void setGlassStyle(NavGlassStyle v) {
    if (v == _glassStyle) return;
    _glassStyle = v;
    _sp?.setString(_kGlassStyle, v.name);
    notifyListeners();
  }

  void setGlassTint(int v) {
    final int clamped = v.clamp(0, 100);
    if (clamped == _glassTint) return;
    _glassTint = clamped;
    _sp?.setInt(_kGlassTint, clamped);
    notifyListeners();
  }

  void setGlassBlur(int v) {
    final int clamped = v.clamp(0, 100);
    if (clamped == _glassBlur) return;
    _glassBlur = clamped;
    _sp?.setInt(_kGlassBlur, clamped);
    notifyListeners();
  }

  void setRailCollapsed(bool v) {
    if (v == _railCollapsed) return;
    _railCollapsed = v;
    _sp?.setBool(_kRailCollapsed, v);
    notifyListeners();
  }

  void setGlassGlow(bool v) {
    if (v == _glassGlow) return;
    _glassGlow = v;
    _sp?.setBool(_kGlassGlow, v);
    notifyListeners();
  }

  void setDefaultKind(Kind v) {
    if (v == _kind) return;
    _kind = v;
    _sp?.setString(_kKind, v.name);
    notifyListeners();
  }

  void setDefaultNormalize(bool v) {
    if (v == _normalize) return;
    _normalize = v;
    _sp?.setBool(_kNormalize, v);
    notifyListeners();
  }
}

/// 偏好注入。与 SessionScope / ProjectScope 同一个套路。
class UiPrefsScope extends InheritedNotifier<UiPrefs> {
  const UiPrefsScope({required UiPrefs prefs, required super.child, super.key})
      : super(notifier: prefs);

  static UiPrefs of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UiPrefsScope>()?.notifier ??
      UiPrefs.instance;

  static UiPrefs read(BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<UiPrefsScope>()?.widget is UiPrefsScope
              ? (context.getElementForInheritedWidgetOfExactType<UiPrefsScope>()!.widget as UiPrefsScope).notifier!
              : UiPrefs.instance;
}