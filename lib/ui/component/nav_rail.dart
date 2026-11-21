import 'package:flutter/material.dart';

import '../prefs.dart';
import '../theme/motion.dart';
import '../theme/tone.dart';
import 'app_icons.dart';
import 'layout.dart';
import 'nav_capsule.dart';

/// 宽屏用的左侧导航栏, 可以收起成一条图标栏。
///
/// 展开时占满整列高度, 所以底部要有东西收口 —— 否则四个入口挤在顶部, 下面
/// 留一大片空白, 看着像没画完。收起后只留图标, 把横向空间让给内容, 每格用
/// Tooltip 补回文字。
class NavRail extends StatelessWidget {
  const NavRail({
    required this.items,
    required this.index,
    required this.onSelect,
    required this.tone,
    this.labels = true,
    this.collapsed = false,
    this.onToggle,
    this.version = '2.0.0',
    super.key,
  });

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final PageTone tone;
  final bool labels;
  final bool collapsed;
  final VoidCallback? onToggle;
  final String version;

  static const int _animMs = 220;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool motion = animationsEnabled(context);
    final Duration duration = motion ? const Duration(milliseconds: _animMs) : Duration.zero;
    // 用 AnimatedSize 而不是 AnimatedContainer 动画宽度: 后者会把"动画中的
    // 中间宽度"当成子树的约束, 收起时可用宽度比图标还窄, 直接报 overflow。
    // AnimatedSize 让子树永远按最终宽度排版, 只裁剪外层。
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      clipBehavior: Clip.hardEdge,
      child: Container(
      width: collapsed ? Layout.railCollapsedWidth : Layout.railWidth,
      decoration: BoxDecoration(
        color: tone.card,
        border: Border(right: BorderSide(color: tone.muted.withValues(alpha: 0.12))),
      ),
      child: SafeArea(
        right: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(collapsed ? 19 : 22, 22, collapsed ? 14 : 18, 16),
              child: Row(
                children: <Widget>[
                  // 用应用自己的图标, 而不是再画一枚 home: 侧栏第一行是品牌。
                  Tooltip(
                    message: 'Chaos 同步器',
                    child: Image.asset(
                      'assets/brand/app_icon.png',
                      width: collapsed ? 38 : 48,
                      height: collapsed ? 38 : 48,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  if (!collapsed) ...<Widget>[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Chaos 同步器',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: tone.onField,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!collapsed)
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 2, 22, 8),
                child: Text(
                  '导航',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                    color: tone.muted.withValues(alpha: 0.8),
                  ),
                ),
              ),
            for (int i = 0; i < items.length; i++)
              _RailItem(
                item: items[i],
                active: i == index,
                labels: labels && !collapsed,
                collapsed: collapsed,
                tone: tone,
                motion: motion,
                onTap: () => onSelect(i),
              ),
            const Spacer(),
            if (!collapsed) _RailFooter(tone: tone, version: version),
            _RailToggle(
              collapsed: collapsed,
              tone: tone,
              onTap: onToggle,
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.item,
    required this.active,
    required this.labels,
    required this.collapsed,
    required this.tone,
    required this.motion,
    required this.onTap,
  });

  final NavItem item;
  final bool active;
  final bool labels;
  final bool collapsed;
  final PageTone tone;
  final bool motion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color fg = active ? tone.deep : tone.onField.withValues(alpha: 0.72);
    final Widget row = Row(
      mainAxisAlignment: labels ? MainAxisAlignment.start : MainAxisAlignment.center,
      children: <Widget>[
        AnimatedScale(
          scale: active && motion ? 1.08 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: Icon(active ? item.activeIcon : item.icon, size: 21, color: fg),
        ),
        if (labels) ...<Widget>[
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              item.label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: fg,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
    final Widget body = Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: motion ? const Duration(milliseconds: 220) : Duration.zero,
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(horizontal: labels ? 14 : 0, vertical: 13),
          decoration: BoxDecoration(
            color: active ? tone.deep.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: row,
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 10 : 14, vertical: 3),
      child: collapsed ? Tooltip(message: item.label, child: body) : body,
    );
  }
}

/// 侧栏底部: 一张小卡片说明当前连接与版本。
class _RailFooter extends StatelessWidget {
  const _RailFooter({required this.tone, required this.version});

  final PageTone tone;
  final String version;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: tone.field,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: tone.muted.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(AppIcons.device, size: 15, color: tone.muted),
                const SizedBox(width: 7),
                Text(
                  'ChaosConnect v1',
                  style: theme.textTheme.bodySmall?.copyWith(color: tone.muted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '版本 ' + version,
              style: TextStyle(fontSize: 11.5, color: tone.muted.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 展开/收起按钮。收起后只剩一枚箭头, 仍然点得到。
class _RailToggle extends StatelessWidget {
  const _RailToggle({required this.collapsed, required this.tone, required this.onTap});

  final bool collapsed;
  final PageTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Tooltip(
        message: collapsed ? '展开侧栏' : '收起侧栏',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: <Widget>[
                AnimatedRotation(
                  turns: collapsed ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(AppIcons.back, size: 18, color: tone.muted),
                ),
                if (!collapsed) ...<Widget>[
                  const SizedBox(width: 10),
                  Text(
                    '收起侧栏',
                    style: TextStyle(fontSize: 12.5, color: tone.muted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
