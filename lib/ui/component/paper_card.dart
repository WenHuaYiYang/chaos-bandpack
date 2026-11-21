import 'package:flutter/material.dart';

import '../theme/paper_palette.dart';
import '../theme/tone.dart';

/// 纸片卡。默认档是纯白(比页底亮), MD3 档按色相轻微染色。
///
/// 卡片自己就是一层 Material: 里面的 ListTile / SwitchListTile 会把底色与
/// 水波纹画在最近的 Material 上, 如果中间隔着带底色的 DecoratedBox, Flutter 会
/// 在 debug 下断言 "ListTile background color or ink splashes may be invisible"。
/// 所以阴影与描边只留在外层 DecoratedBox, 底色交给 Material。
class PaperCard extends StatelessWidget {
  const PaperCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.tint = Colors.transparent,
    this.onTap,
    this.border = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color tint;
  final VoidCallback? onTap;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final PageTone tone = ToneScope.of(context);
    final ColorScheme s = Theme.of(context).colorScheme;
    final BorderRadius radius = BorderRadius.circular(PaperPalette.shapeLg);
    final Widget inner = Padding(padding: padding, child: child);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: border ? Border.all(color: s.outlineVariant) : null,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: tone.cardFor(tint),
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? inner : InkWell(onTap: onTap, child: inner),
      ),
    );
  }
}

/// 一行的「标题 + 说明 + 右侧控件」。设置和表单里反复用到。
class SettingRow extends StatelessWidget {
  const SettingRow({
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.onTap,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PageTone tone = ToneScope.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PaperPalette.shapeSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: <Widget>[
            if (leading != null) ...<Widget>[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: theme.textTheme.titleMedium),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: tone.muted)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

/// 区块标题(小字全大写那种感觉, 中文用小字加间距)。
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final PageTone tone = ToneScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: tone.muted,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
