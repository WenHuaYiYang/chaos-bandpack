import 'package:flutter/material.dart';

import '../../chaos/beauty_sync.dart';
import '../../chaos/session_scope.dart';
import '../../project/chaos_project.dart';
import '../../project/project_actions.dart';
import '../../project/project_store.dart';
import '../chaos_app.dart';
import '../component/app_icons.dart';
import '../component/layout.dart';
import '../component/maker_route.dart';
import '../component/maker_scaffold.dart';
import '../component/paper_card.dart';
import '../theme/motion.dart';
import '../theme/paper_palette.dart';
import '../theme/tone.dart';
import 'beauty_pack_screen.dart';
import 'font_screen.dart';
import 'icon_screen.dart';

/// 首页: 错峰入场的一列卡片。
///
/// 卡片数是 6 (两张制作卡 + 工程动作 + 美化包 + 连接手环 + 关于), 改数量要同步
/// [_cardCount], 否则最后一块会提前入场。
///
/// 平板或横屏时改成两列: 一列铺满 1000 多逻辑像素的话, 一张卡横着长成一条,
/// 读的时候眼睛要从左头扫到右头。两列之后版心仍然限宽居中。
class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.onOpen, super.key});

  final ValueChanged<Dest> onOpen;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  static const int _cardCount = 6;
  bool _openingPack = false;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
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

  /// 字体页与图标页不进底栏 —— 四格留给每天都要看的入口, 这两件是一次性的活。
  /// 从卡片推进来, 页头给返回箭头。
  void _push(BuildContext context, String label, Widget page, PageTone Function(BuildContext) tone) {
    final NavigatorState nav = Navigator.of(context);
    nav.push(
      makerRoute(
        label: label,
        page: page,
        tone: tone,
        session: SessionScope.read(context),
        project: ProjectScope.read(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PageTone tone = ToneScope.of(context);
    final ColorScheme s = theme.colorScheme;
    final bool wide = Layout.isTwoColumn(context);

    final Widget fontCard = _BigCard(
      index: 0,
      controller: _c,
      count: _cardCount,
      title: '字体制作',
      desc: '选字库、字集档与打包',
      icon: AppIcons.font,
      tint: s.secondary,
      onTap: () => _push(context, '字体制作', FontScreen(onClose: () => Navigator.of(context).pop()), TonePalette.font),
    );

    final Widget iconCard = _BigCard(
      index: 1,
      controller: _c,
      count: _cardCount,
      title: '图标制作',
      desc: '机型、槽位与打包',
      icon: AppIcons.iconPackActive,
      tint: s.tertiary,
      onTap: () => _push(context, '图标制作', IconScreen(onClose: () => Navigator.of(context).pop()), TonePalette.icon),
    );

    final Widget deviceCard = _BigCard(
      index: 4,
      controller: _c,
      count: _cardCount,
      title: '连接手环',
      desc: '配对、权限、文件与 NSH',
      icon: AppIcons.device,
      tint: s.primary,
      onTap: () => widget.onOpen(Dest.device),
    );

    final Widget aboutCard = _BigCard(
      index: 5,
      controller: _c,
      count: _cardCount,
      title: '关于同步器',
      desc: '版本、固件与协议',
      icon: AppIcons.info,
      tint: tone.muted,
      onTap: () => _about(context),
    );

    final Widget smallRow = _SmallRow(
      index: 2,
      controller: _c,
      count: _cardCount + 1,
      children: <Widget>[
        _SmallAction(
          icon: AppIcons.openProject,
          label: '打开工程',
          onTap: () => _open(context),
        ),
        _SmallAction(
          icon: AppIcons.saveProject,
          label: '保存工程',
          onTap: () => _save(context),
        ),
      ],
    );

    final Widget packCard = _BigCard(
      index: 3,
      controller: _c,
      count: _cardCount,
      title: '打开美化包',
      desc: '打开 .chp，查看内容并同步到手环',
      icon: AppIcons.build,
      tint: s.secondary,
      onTap: _openingPack ? () {} : () => _openBeautyPack(context),
    );

    final List<Widget> body = <Widget>[
      if (wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: fontCard),
            const SizedBox(width: 14),
            Expanded(child: iconCard),
          ],
        )
      else ...<Widget>[fontCard, const SizedBox(height: 12), iconCard],
      const SizedBox(height: 12),
      smallRow,
      const SizedBox(height: 12),
      packCard,
      const SizedBox(height: 12),
      if (wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: deviceCard),
            const SizedBox(width: 14),
            Expanded(child: aboutCard),
          ],
        )
      else ...<Widget>[deviceCard, const SizedBox(height: 12), aboutCard],
    ];

    final bool rail = Layout.isRail(context);
    final double gutter = rail ? Layout.railGutter : Layout.gutter;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: rail ? Layout.wideContent : Layout.maxContent),
        child: ListView(
          // 侧栏模式没有底部胶囊, 不需要那 120dp 的避让。
          padding: EdgeInsets.fromLTRB(gutter, 8, gutter, rail ? 32 : 120),
          children: <Widget>[
            StaggerIn(
              controller: _c,
              index: 0,
              count: _cardCount,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Chaos 同步器',
                      style: theme.textTheme.headlineMedium?.copyWith(color: tone.onField),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '制作字体和图标，直接同步到手环',
                      style: theme.textTheme.bodySmall?.copyWith(color: tone.muted),
                    ),
                  ],
                ),
              ),
            ),
            ...body,
          ],
        ),
      ),
    );
  }

  Future<void> _openBeautyPack(BuildContext context) async {
    if (_openingPack) return;
    _openingPack = true;
    try {
      final selected = await BeautySync.pick();
      if (!context.mounted || selected == null) return;
      _push(context, '美化包', BeautyPackScreen(pack: selected.pack, fileName: selected.name), TonePalette.home);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(BeautySync.readableError(error))));
      }
    } finally {
      _openingPack = false;
    }
  }

  /// 打开工程: 认 .chaosproj 和旧版 .bin 投递表盘。
  Future<void> _open(BuildContext context) async {
    final ProjectStore store = ProjectScope.read(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final (ChaosProject, bool, String)? picked = await ProjectActions.pick();
      if (picked == null) return;
      final (ChaosProject project, bool isProject, String name) = picked;
      store.apply(project, file: name);
      messenger.showSnackBar(
        SnackBar(content: Text((isProject ? '已打开工程 ' : '已从投递包反推工程 ') + name)),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败: ' + e.toString())));
    }
  }

  /// 保存工程: 至少要有一个包才有意义。
  Future<void> _save(BuildContext context) async {
    final ProjectStore store = ProjectScope.read(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ChaosProject? project = store.snapshot();
    if (project == null) {
      messenger.showSnackBar(const SnackBar(content: Text('请先选择图标或字体')));
      return;
    }
    try {
      final String? path = await ProjectActions.save(project);
      if (path == null) return;
      messenger.showSnackBar(SnackBar(content: Text('已保存到 ' + path)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('保存失败: ' + e.toString())));
    }
  }

  void _about(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final PageTone tone = ToneScope.of(context);
        final ThemeData theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: PaperCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Chaos 同步器', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  '版本 2.0.0',
                  style: theme.textTheme.bodyMedium?.copyWith(color: tone.muted),
                ),
                const SizedBox(height: 14),
                Text('小米手环 10 Pro / 9 Pro', style: theme.textTheme.bodySmall),
                Text('固件 3.101.043 · 3.1.187', style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('知道了'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 并排两个小动作(打开/保存工程), 与上下的大卡共用错峰入场。
class _SmallRow extends StatelessWidget {
  const _SmallRow({
    required this.index,
    required this.controller,
    required this.count,
    required this.children,
  });

  final int index;
  final int count;
  final AnimationController controller;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final Widget row = Row(
      children: <Widget>[
        for (int i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: children[i]),
        ],
      ],
    );
    if (!animationsEnabled(context)) return row;
    return EnterLayer(
      t: EnterStep(controller, count: count).of(index + 1),
      dy: 26,
      child: row,
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PageTone tone = ToneScope.of(context);
    return PressScale(
      child: PaperCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: onTap,
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: tone.muted),
            const SizedBox(width: 10),
            Text(label, style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}

class _BigCard extends StatefulWidget {
  const _BigCard({
    required this.index,
    required this.count,
    required this.controller,
    required this.title,
    required this.desc,
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  final int index;
  final int count;
  final AnimationController controller;
  final String title;
  final String desc;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  State<_BigCard> createState() => _BigCardState();
}

class _BigCardState extends State<_BigCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PageTone tone = ToneScope.of(context);
    final bool motion = animationsEnabled(context);
    final Animation<double> t = EnterStep(widget.controller, count: widget.count).of(widget.index + 1);

    final Widget card = AnimatedScale(
      scale: _down && motion ? 0.98 : 1,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: PaperCard(
        padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
        tint: widget.tint,
        onTap: widget.onTap,
        child: Row(
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: widget.tint.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(PaperPalette.shapeMd),
              ),
              child: Icon(widget.icon, color: widget.tint, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(widget.title, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(widget.desc, style: theme.textTheme.bodySmall?.copyWith(color: tone.muted)),
                ],
              ),
            ),
            Icon(AppIcons.chevronRight, color: tone.muted, size: 22),
          ],
        ),
      ),
    );

    final Widget wrapped = GestureDetector(
      onTapDown: motion ? (_) => setState(() => _down = true) : null,
      onTapUp: motion ? (_) => setState(() => _down = false) : null,
      onTapCancel: motion ? () => setState(() => _down = false) : null,
      child: card,
    );

    if (!motion) return wrapped;
    return EnterLayer(t: t, dy: 30, child: wrapped);
  }
}