import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'pack/preview_factory.dart';
import 'ui/chaos_app.dart';
import 'ui/prefs.dart';
import 'ui/theme/paper_palette.dart';
import 'ui/theme/tone.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 液态玻璃着色器要在首帧前预热, 否则底栏会先闪一帧纯色再变成玻璃。
  await LiquidGlassWidgets.initialize();
  // 预览块光栅化时用的字族。pubspec 把 MiSans 注册成 style 字族, 这里也交给
  // 预览工厂 —— 预览里那行中文要和手环上看到的字形一致, 不能落回系统字体。
  PreviewFactory.fontFamily = 'MiSans';
  final UiPrefs prefs = await UiPrefs.load();
  TonePalette.style = prefs.style;
  runApp(LiquidGlassWidgets.wrap(
    // MaterialApp 的 ThemeMode 与系统明暗可能不一致, 交给玻璃组件按主题走。
    brightnessResolver: Theme.maybeBrightnessOf,
    child: ChaosBandpackApp(prefs: prefs),
  ));
}

class ChaosBandpackApp extends StatelessWidget {
  const ChaosBandpackApp({required this.prefs, super.key});

  final UiPrefs prefs;

  @override
  Widget build(BuildContext context) {
    // 外观与风格都能在设置页改, 所以这里跟着偏好重建整棵树。
    return AnimatedBuilder(
      animation: prefs,
      builder: (BuildContext context, Widget? _) {
        return UiPrefsScope(
          prefs: prefs,
          child: MaterialApp(
            title: 'Chaos 同步器',
            debugShowCheckedModeBanner: false,
            theme: PaperPalette.theme(Brightness.light),
            darkTheme: PaperPalette.theme(Brightness.dark),
            themeMode: prefs.appearance.mode,
            home: const ChaosApp(),
          ),
        );
      },
    );
  }
}