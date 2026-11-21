import 'package:flutter/material.dart';

import '../../font/charset.dart';
import '../component/maker_scaffold.dart';
import '../component/segmented.dart';
import '../component/paper_card.dart';
import '../prefs.dart';
import '../theme/paper_palette.dart';
import '../theme/tone.dart';

/// 设置页: 外观 / 制作默认值 / 关于。
///
/// 每一项都是真控件(分段器、开关), 不做「读一段话再猜怎么改」。改动立刻落盘,
/// 下次启动还在。
///
/// 底栏四格之一是设置本身, 所以它是一级页, 没有返回箭头。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final UiPrefs prefs = UiPrefsScope.of(context);
    final ThemeData theme = Theme.of(context);
    final PageTone tone = ToneScope.of(context);

    return MakerScaffold(
      title: '设置',
      subtitle: '外观与打包默认值',
      children: <Widget>[
        StaggerIn(controller: _c, index: 0, child: const SectionLabel('外观')),
        StaggerIn(
          controller: _c,
          index: 1,
          child: PaperCard(
            child: Column(
              children: <Widget>[
                const SettingRow(title: '主题', subtitle: '浅色、深色与跟随系统'),
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Segmented<Appearance>(
                    value: prefs.appearance,
                    items: const <Appearance, String>{
                      Appearance.system: '跟随系统',
                      Appearance.light: '浅色',
                      Appearance.dark: '深色',
                    },
                    onChanged: prefs.setAppearance,
                  ),
                ),
                const Divider(height: 26),
                const SettingRow(title: '界面风格', subtitle: '纸片与色场两套配色'),
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Segmented<ThemeStyle>(
                    value: prefs.style,
                    items: const <ThemeStyle, String>{
                      ThemeStyle.paper: '纸片',
                      ThemeStyle.md3: '色场',
                    },
                    onChanged: prefs.setStyle,
                  ),
                ),
                const Divider(height: 26),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: prefs.navLabels,
                  onChanged: prefs.setNavLabels,
                  title: const Text('导航显示文字'),
                  subtitle: const Text('底栏文字开关'),
                ),
                const Divider(height: 26),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: prefs.navGlass,
                  onChanged: prefs.setNavGlass,
                  title: const Text('液态玻璃底栏'),
                  subtitle: const Text('苹果 iOS 那种折射玻璃。低端机可能掉帧'),
                ),
                if (prefs.navGlass) ...<Widget>[
                  const SizedBox(height: 6),
                  const SettingRow(title: '玻璃版本', subtitle: 'iOS 26 折射更重，iOS 27 更克制'),
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Segmented<NavGlassStyle>(
                      value: prefs.glassStyle,
                      items: const <NavGlassStyle, String>{
                        NavGlassStyle.ios26: 'iOS 26',
                        NavGlassStyle.ios27: 'iOS 27',
                      },
                      onChanged: prefs.setGlassStyle,
                    ),
                  ),
                  _GlassSlider(
                    label: '染色浓度',
                    hint: '越高越不透明，花哨壁纸上文字更清楚',
                    value: prefs.glassTint,
                    onChanged: prefs.setGlassTint,
                  ),
                  _GlassSlider(
                    label: '模糊强度',
                    hint: '背景透上来的糊度',
                    value: prefs.glassBlur,
                    onChanged: prefs.setGlassBlur,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: prefs.glassGlow,
                    onChanged: prefs.setGlassGlow,
                    title: const Text('选中格辉光'),
                    subtitle: const Text('关掉更接近系统原版'),
                  ),
                ],
              ],
            ),
          ),
        ),
        StaggerIn(controller: _c, index: 2, child: const SectionLabel('制作默认值')),
        StaggerIn(
          controller: _c,
          index: 3,
          child: PaperCard(
            child: Column(
              children: <Widget>[
                const SettingRow(title: '字集档', subtitle: '新建包的字集范围'),
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Segmented<Kind>(
                    value: prefs.defaultKind,
                    items: const <Kind, String>{
                      Kind.simplified: '精简',
                      Kind.withTraditional: '含繁体',
                    },
                    onChanged: prefs.setDefaultKind,
                  ),
                ),
                const Divider(height: 26),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: prefs.defaultNormalize,
                  onChanged: prefs.setDefaultNormalize,
                  title: const Text('归一化垂直度量'),
                  subtitle: const Text('行高与基线对齐'),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '必需字集 ' + (Charset.required.length ~/ 1000).toString() + 'k；' +
                        '含繁体再 +' + (Charset.big5.length ~/ 1000).toString() + 'k。',
                    style: theme.textTheme.bodySmall?.copyWith(color: tone.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
        StaggerIn(controller: _c, index: 4, child: const SectionLabel('关于')),
        StaggerIn(
          controller: _c,
          index: 5,
          child: PaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Chaos 同步器 2.0.0', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _Tag('10 Pro · 3.101.043'),
                    _Tag('9 Pro · 3.1.187'),
                    _Tag('CCN1 · 2048 B 块'),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '蓝牙 UUID 43434e31-0001-4a10-8000-4348414f5301',
                  style: theme.textTheme.bodySmall?.copyWith(color: tone.muted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PageTone tone = ToneScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tone.capsule,
        borderRadius: BorderRadius.circular(PaperPalette.shapeXs),
      ),
      child: Text(text, style: theme.textTheme.labelSmall?.copyWith(color: tone.muted)),
    );
  }
}

/// 玻璃参数滑块。显示当前值, 拖动即时生效 —— 用户能一边看底栏一边调。
class _GlassSlider extends StatelessWidget {
  const _GlassSlider({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final PageTone tone = ToneScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
            Text(value.toString(), style: TextStyle(fontSize: 12, color: tone.muted)),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: 0,
          max: 100,
          divisions: 20,
          label: value.toString(),
          onChanged: (double v) => onChanged(v.round()),
        ),
        Text(hint, style: TextStyle(fontSize: 11.5, color: tone.muted)),
      ],
    );
  }
}
