import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/tone.dart';
import 'layout.dart';
import 'paper_card.dart';

/// 内页统一骨架: 大标题 + 副标题 + 可滚动内容 + 底部留白(避开导航胶囊)。
///
/// 相邻内容块之间统一留 [gap]。间隔属于骨架的职责: 以前靠每个页面自己在 children
/// 里插 SizedBox, 漏一处两张卡片就贴在一起, 一页一页看过去很难发现。
///
/// 内容限宽到 [Layout.maxContent] 后居中。手机上本来就窄, 看不出差别; 平板横过来
/// 一千多逻辑像素时, 不限宽的话输入框会拉成一米长, 一行标题要转头去读。
///
/// 整页入场靠 [MakerScaffold] 自己驱动: 从下方 24dp 淡入上浮, 与首页的逐块错峰
/// 叠在一起就是「先进页面、再进内容」的两层节奏。
class MakerScaffold extends StatefulWidget {
  const MakerScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const <Widget>[],
    this.leading,
    this.bottomBar,
    this.navReserve = true,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget> actions;
  final Widget? leading;
  final Widget? bottomBar;

  /// 底栏是否被外壳的导航胶囊占着。底栏四格上是 true, 要给胶囊让出位置;
  /// 从首页推进来的制作页是一整屏, 没有胶囊, 传 false 把这段留白收掉。
  final bool navReserve;

  /// 相邻内容块之间的留白。卡片贴卡片会显得挤, 也给不出分组的界限。
  static const double gap = 14;

  @override
  State<MakerScaffold> createState() => _MakerScaffoldState();
}

class _MakerScaffoldState extends State<MakerScaffold> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
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
    final PageTone tone = ToneScope.of(context);
    final ThemeData theme = Theme.of(context);
    final bool bar = widget.bottomBar != null;
    // 有底栏时列表末尾要留够按钮本身的高度, 否则最后一行会永远躲在按钮背后。
    // 宽屏没有底栏胶囊, 这段留白就白留了 —— 侧栏模式只留正常页脚。
    final bool rail = Layout.isRail(context);
    final double tail = bar
        ? (widget.navReserve ? 150 : 96)
        : (widget.navReserve ? (rail ? 40 : 120) : 32);
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final double barPad =
        widget.navReserve && !rail ? 104 : 20 + MediaQuery.paddingOf(context).bottom;

    final Widget content = AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final double t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * 24), child: child),
        );
      },
      child: Column(
        children: <Widget>[
          _center(
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 6),
              child: Row(
                children: <Widget>[
                  if (widget.leading != null) ...<Widget>[
                    widget.leading!,
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.title,
                          style: theme.textTheme.headlineSmall?.copyWith(color: tone.onField),
                        ),
                        if (widget.subtitle != null) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            widget.subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(color: tone.muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ...widget.actions,
                ],
              ),
            ),
          ),
          Expanded(
            child: _center(
              ListView(
                padding: EdgeInsets.fromLTRB(Layout.gutter, 10, Layout.gutter, tail),
                children: _spaced(widget.children),
              ),
            ),
          ),
          if (bar)
            // 列表滚到底下会从按钮后面穿出来, 像没对齐。盖一层从透明到底色的渐变,
            // 内容到这里自然淡掉, 按钮才有「固定在这一层」的分量。
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[tone.field.withValues(alpha: 0), tone.field],
                  stops: const <double>[0, 0.34],
                ),
              ),
              padding: const EdgeInsets.only(top: 26),
              child: _center(
                Padding(
                  padding: EdgeInsets.fromLTRB(Layout.gutter, 0, Layout.gutter, barPad),
                  child: widget.bottomBar!,
                ),
              ),
            ),
        ],
      ),
    );
    // 外壳不是 Material Scaffold，不会替这里避让键盘。缩短 ListView 的视口后，
    // TextField 自己会把光标滚到可见区域，不必给每个输入框挂焦点监听。
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: content,
    );
  }

  Widget _center(Widget child) => Center(
        child: ConstrainedBox(
          // 宽屏且无底栏时用更宽的版心: 720 是给手机阅读的宽度, 桌面上会显得
          // 两边空一大片, 尤其表单和文件列表。
          constraints: BoxConstraints(
            maxWidth: Layout.isRail(context) && !widget.navReserve
                ? Layout.wideContent
                : Layout.maxContent,
          ),
          child: child,
        ),
      );
}

/// 给内容块之间补留白。[SectionLabel] 自带上下留白, 挨着它就不再叠。
List<Widget> _spaced(List<Widget> children) {
  final List<Widget> out = <Widget>[];
  for (final Widget child in children) {
    if (out.isNotEmpty && out.last is! SectionLabel && child is! SectionLabel) {
      out.add(const SizedBox(height: MakerScaffold.gap));
    }
    out.add(child);
  }
  return out;
}

/// 首页用的逐块入场: 包一层 [EnterLayer], 由外部的 controller 驱动。
class StaggerIn extends StatelessWidget {
  const StaggerIn({required this.controller, required this.index, required this.child, this.count = 6, super.key});

  final AnimationController controller;
  final int index;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animationsEnabled(context)) return child;
    final EnterStep step = EnterStep(controller, count: count);
    return EnterLayer(t: step.of(index), child: child);
  }
}