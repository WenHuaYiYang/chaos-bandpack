import 'package:flutter/material.dart';

import '../chaos/session.dart';
import '../chaos/session_scope.dart';
import '../project/project_store.dart';
import 'component/app_icons.dart';
import 'component/layout.dart';
import 'component/nav_capsule.dart';
import 'component/nav_rail.dart';
import 'prefs.dart';
import 'screen/device_screen.dart';
import 'screen/home_screen.dart';
import 'screen/settings_screen.dart';
import 'screen/store_screen.dart';
import 'theme/motion.dart';
import 'theme/tone.dart';

/// 底栏的四个目的地: 首页、资源商店、设置、设备。
///
/// 字体页与图标页从首页的卡片进去 —— 它们是一次性的活, 不是每天要巡视的地方,
/// 占底栏会把真正常用的四格挤掉。
enum Dest { home, store, settings, device }

extension DestInfo on Dest {
  String get label => switch (this) {
        Dest.home => '首页',
        Dest.store => '商店',
        Dest.settings => '设置',
        Dest.device => '设备',
      };

  IconData get icon => switch (this) {
        Dest.home => AppIcons.home,
        Dest.store => AppIcons.store,
        Dest.settings => AppIcons.settings,
        Dest.device => AppIcons.device,
      };

  IconData get activeIcon => switch (this) {
        Dest.home => AppIcons.homeActive,
        Dest.store => AppIcons.storeActive,
        Dest.settings => AppIcons.settingsActive,
        Dest.device => AppIcons.linked,
      };

  PageTone tone(BuildContext c) => switch (this) {
        Dest.home => TonePalette.home(c),
        Dest.store => TonePalette.store(c),
        Dest.settings => TonePalette.settings(c),
        Dest.device => TonePalette.device(c),
      };
}

/// 应用外壳: 底色随目的地渐变, 页面错峰滑入, 底部浮动导航胶囊。
class ChaosApp extends StatefulWidget {
  const ChaosApp({super.key});

  @override
  State<ChaosApp> createState() => _ChaosAppState();
}

class _ChaosAppState extends State<ChaosApp> with SingleTickerProviderStateMixin {
  Dest _dest = Dest.home;
  int _dir = 1;
  late final AnimationController _switch = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );

  /// 一条会话活到应用末尾: 页面来回切换不该断链路(重连要重新配对握手,
  /// 手环那边还会弹确认)。设备页只负责展示与控制。
  late final ChaosSession _session = ChaosSession();

  /// 一份工程活到应用末尾: 在字体页做的包、在图标页选的图, 切页回来还在。
  late final ProjectStore _project = ProjectStore();

  @override
  void dispose() {
    _project.dispose();
    _session.dispose();
    _switch.dispose();
    super.dispose();
  }

  void _go(Dest next) {
    if (next == _dest) return;
    setState(() {
      _dir = next.index < _dest.index ? -1 : 1;
      _dest = next;
    });
    _switch.forward(from: 0);
  }

  /// 页面本体 + 切页动效。窄屏铺满窗口, 宽屏铺满右侧内容区。
  Widget _stage(Widget page, bool motion) {
    return SafeArea(
      bottom: false,
      child: AnimatedBuilder(
        animation: _switch,
        builder: (context, _) {
          final double t = _switch.value;
          // 进场: 从切换方向的一侧滑入 + 淡入。位移只有 36dp, 再大
          // 会和胶囊一起晃, 反而显脏。
          final double dx = (1 - Curves.easeOutCubic.transform(t)) * _dir * 36;
          final double opacity = Curves.easeOut.transform(t.clamp(0.0, 1.0));
          return Opacity(
            opacity: opacity,
            child: Transform.translate(offset: Offset(dx, 0), child: page),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PageTone tone = _dest.tone(context);
    final bool motion = animationsEnabled(context);
    final UiPrefs prefs = UiPrefsScope.of(context);
    final bool navLabels = prefs.navLabels;
    final bool rail = Layout.isRail(context);

    final Widget page = switch (_dest) {
      Dest.home => HomeScreen(onOpen: _go),
      Dest.store => const StoreScreen(),
      Dest.settings => const SettingsScreen(),
      Dest.device => const DeviceScreen(),
    };

    final List<NavItem> navItems = <NavItem>[
      for (final Dest d in Dest.values) (label: d.label, icon: d.icon, activeIcon: d.activeIcon),
    ];

    return SessionScope(
      session: _session,
      child: ProjectScope(
        store: _project,
        child: ToneScope(
          tone: tone,
          child: PopScope(
            canPop: _dest == Dest.home,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              _go(Dest.home);
            },
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: tone.field),
              duration: motion ? const Duration(milliseconds: 360) : Duration.zero,
              curve: Curves.easeOut,
              builder: (context, color, child) => ColoredBox(
                color: color ?? tone.field,
                child: child,
              ),
              // 整壳垫一层透明 Material: 页面里的 InkWell(导航胶囊的格子、卡片的
              // 点击态)都要求有 Material 祖先, 少了它整棵树会在 build 时断言失败。
              child: Material(
                type: MaterialType.transparency,
                // 宽屏: 左侧竖排导航 + 右侧内容。窄屏仍是底栏胶囊浮在内容上。
                child: rail
                    ? Row(
                        children: <Widget>[
                          NavRail(
                            items: navItems,
                            index: _dest.index,
                            onSelect: (i) => _go(Dest.values[i]),
                            tone: tone,
                            labels: navLabels,
                            collapsed: prefs.railCollapsed,
                            onToggle: () => prefs.setRailCollapsed(!prefs.railCollapsed),
                          ),
                          Expanded(child: _stage(page, motion)),
                        ],
                      )
                    : Stack(
                  children: <Widget>[
                    Positioned.fill(child: _stage(page, motion)),
                    Positioned(
                      left: Layout.gutter,
                      right: Layout.gutter,
                      bottom: 12 + MediaQuery.viewPaddingOf(context).bottom,
                      // 宽屏上限宽: 五格胶囊拉满 1200dp 会变成一条扁带,
                      // 拇指也够不到中间那两格。
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: Layout.maxNav),
                          child: prefs.navGlass
                              ? NavCapsule(
                                  items: navItems,
                                  index: _dest.index,
                                  onSelect: (i) => _go(Dest.values[i]),
                                  tone: tone,
                                  labels: navLabels,
                                  glassStyle: prefs.glassStyle,
                                  glassTint: prefs.glassTint,
                                  glassBlur: prefs.glassBlur,
                                  glassGlow: prefs.glassGlow,
                                )
                              : PaperNavCapsule(
                                  items: navItems,
                                  index: _dest.index,
                                  onSelect: (i) => _go(Dest.values[i]),
                                  tone: tone,
                                  labels: navLabels,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}