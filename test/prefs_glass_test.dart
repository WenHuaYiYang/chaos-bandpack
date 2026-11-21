import 'package:chaos_bandpack/ui/prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('液态玻璃默认关闭，开关与参数都能落盘', () {
    final prefs = UiPrefs.instance;
    // 默认必须是原来的纸片底栏: 新效果不该替用户擅自打开。
    expect(prefs.navGlass, isFalse);
    prefs.setNavGlass(true);
    expect(prefs.navGlass, isTrue);
    prefs.setGlassStyle(NavGlassStyle.ios26);
    expect(prefs.glassStyle, NavGlassStyle.ios26);
    prefs.setGlassTint(140);
    expect(prefs.glassTint, 100); // 越界夹住
    prefs.setGlassTint(-20);
    expect(prefs.glassTint, 0);
    prefs.setGlassBlur(30);
    expect(prefs.glassBlur, 30);
    prefs.setGlassGlow(false);
    expect(prefs.glassGlow, isFalse);
    prefs.setNavGlass(false);
    expect(prefs.navGlass, isFalse);
  });
}
