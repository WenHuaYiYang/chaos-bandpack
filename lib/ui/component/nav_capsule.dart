import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../prefs.dart';
import '../theme/motion.dart';
import '../theme/tone.dart';

/// 一个目的地(给导航胶囊用)。用 record 而不是 import 上层枚举, 避免循环依赖。
typedef NavItem = ({String label, IconData icon, IconData activeIcon});

/// 浮动导航胶囊。
///
/// 两种外观共用同一套交互与布局: [UiPrefs.navGlass] 关着时是原来的纸片胶囊,
/// 打开后换成 liquid_glass_widgets 的液态玻璃条。默认关闭 —— 玻璃在低端安卓
/// 机上是有代价的, 不该替用户默认打开。
class NavCapsule extends StatelessWidget {
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final PageTone tone;
  final bool labels;

  /// 玻璃外观的参数。为 null 时用 [UiPrefs] 里的当前值。
  final NavGlassStyle glassStyle;
  final int glassTint;
  final int glassBlur;
  final bool glassGlow;

  const NavCapsule({
    required this.items,
    required this.index,
    required this.onSelect,
    required this.tone,
    this.labels = true,
    this.glassStyle = NavGlassStyle.ios27,
    this.glassTint = 50,
    this.glassBlur = 55,
    this.glassGlow = true,
    super.key,
  });

  static const double height = 62;
  static const double _pad = 5;

  @override
  Widget build(BuildContext context) {
    final bool motion = animationsEnabled(context);
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: height,
      child: GlassTabBar.bottom(
        tabs: <GlassTab>[
          for (final NavItem item in items)
            GlassTab(
              icon: Icon(item.icon, size: labels ? 21 : 24),
              activeIcon: Icon(item.activeIcon, size: labels ? 21 : 24),
              label: labels ? item.label : null,
              semanticLabel: item.label,
            ),
        ],
        selectedIndex: index,
        onTabSelected: onSelect,
        barHeight: height,
        barBorderRadius: height / 2,
        horizontalPadding: 6,
        verticalPadding: 6,
        spacing: 0,
        labelFontSize: 11,
        iconSize: labels ? 21 : 24,
        indicatorColor: tone.deep.withValues(alpha: dark ? 0.55 : 0.92),
        selectedIconColor: tone.onDeep,
        selectedLabelColor: tone.onDeep,
        unselectedIconColor: tone.muted,
        unselectedLabelColor: tone.muted,
        selectedLabelStyle: const TextStyle(fontSize: 11, height: 1.1, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 11, height: 1.1, fontWeight: FontWeight.w500),
        settings: _settings(dark),
        indicatorSettings: _indicator(dark),
        showIndicator: true,
        glowOpacity: glassGlow ? 0.6 : 0.0,
        pressScale: motion ? 1.04 : 1.0,
      ),
    );
  }

  LiquidGlassSettings _settings(bool dark) {
    final LiquidGlassSettings base = switch (glassStyle) {
      NavGlassStyle.ios26 => dark ? LiquidGlassSettings.ios26Dark : LiquidGlassSettings.ios26Light,
      NavGlassStyle.ios27 => dark ? LiquidGlassSettings.ios27Dark : LiquidGlassSettings.ios27Light,
    };
    // 用户只调两个量: 染色浓度和模糊强度。其余保持库里的光学参数,
    // 免得调出一块谁都不认识的塑料。
    return base.copyWith(
      glassColor: base.glassColor.withValues(alpha: glassTint / 100),
      blur: 4 + glassBlur * 0.28,
    );
  }

  LiquidGlassSettings _indicator(bool dark) {
    final LiquidGlassSettings base = switch (glassStyle) {
      NavGlassStyle.ios26 => LiquidGlassSettings.ios26Indicator,
      NavGlassStyle.ios27 => LiquidGlassSettings.ios27Indicator,
    };
    return base.copyWith(glassColor: tone.deep.withValues(alpha: dark ? 0.55 : 0.92));
  }
}

/// 原来的纸片胶囊: 一条卡片色的圆角长条, 选中格被一块深色圆角盖住, 图标反白。
///
/// 保留它不只是为了兼容 —— 玻璃版在无 GPU 加速的远程桌面、老安卓上会退化成
/// 一块灰, 那时这个版本反而是对的。
class PaperNavCapsule extends StatelessWidget {
  const PaperNavCapsule({
    required this.items,
    required this.index,
    required this.onSelect,
    required this.tone,
    this.labels = true,
    super.key,
  });

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final PageTone tone;
  final bool labels;

  static const double height = NavCapsule.height;
  static const double _pad = NavCapsule._pad;

  @override
  Widget build(BuildContext context) {
    final bool motion = animationsEnabled(context);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: tone.capsule,
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(_pad),
      child: LayoutBuilder(
        builder: (context, box) {
          final double cellW = box.maxWidth / items.length;
          return Stack(
            children: <Widget>[
              AnimatedAlign(
                alignment: Alignment(
                  items.length == 1 ? 0 : -1 + 2 * (index / (items.length - 1)),
                  0,
                ),
                duration: motion ? const Duration(milliseconds: 320) : Duration.zero,
                curve: Curves.easeOutCubic,
                child: Container(
                  width: cellW,
                  height: height - _pad * 2,
                  decoration: BoxDecoration(
                    color: tone.deep,
                    borderRadius: BorderRadius.circular((height - _pad * 2) / 2),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (int i = 0; i < items.length; i++)
                    Expanded(
                      child: _PaperNavCell(
                        item: items[i],
                        active: i == index,
                        onTap: () => onSelect(i),
                        tone: tone,
                        labels: labels,
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PaperNavCell extends StatelessWidget {
  const _PaperNavCell({
    required this.item,
    required this.active,
    required this.onTap,
    required this.tone,
    required this.labels,
  });

  final NavItem item;
  final bool active;
  final VoidCallback onTap;
  final PageTone tone;
  final bool labels;

  @override
  Widget build(BuildContext context) {
    final Color fg = active ? tone.onDeep : tone.muted;
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedScale(
              scale: active ? 1.06 : 1,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              child: Icon(active ? item.activeIcon : item.icon,
                  size: labels ? 21 : 24, color: fg),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: labels
                  ? Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 220),
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.1,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          color: fg,
                        ),
                        child: Text(item.label),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
