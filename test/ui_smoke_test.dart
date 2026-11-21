import 'package:chaos_bandpack/ui/chaos_app.dart';
import 'package:chaos_bandpack/ui/component/nav_capsule.dart';
import 'package:chaos_bandpack/ui/component/nav_rail.dart';
import 'package:chaos_bandpack/ui/prefs.dart';
import 'package:chaos_bandpack/ui/theme/paper_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 冒烟: 四页都能建起来, 切页不抛异常。
///
/// 这几页都含大量布局代码(网格、卡片、错峰动画), 光靠 analyze 看不出运行时问题
/// —— 空槽位的网格、没有链路时的设备页, 都是容易在 build 里崩的地方。
void main() {
  Future<void> boot(WidgetTester tester, {double width = 480, double height = 960}) async {
    tester.view.physicalSize = Size(width * 2, height * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      // 生产里 UiPrefsScope 在 MaterialApp 外面; 测试也得包上, 否则改偏好
      // 不会触发重建, 侧栏收起这类交互就测不出来。
      UiPrefsScope(
        prefs: UiPrefs.instance,
        child: MaterialApp(
          theme: PaperPalette.theme(Brightness.light),
          home: const ChaosApp(),
        ),
      ),
    );
    // 首页卡片是错峰入场的(900ms), 不跑完就点, 命中区域还在往下走。
    await tester.pump(const Duration(milliseconds: 1000));
  }

  testWidgets('应用外壳能建起来并切完全部页签', (WidgetTester tester) async {
    await boot(tester);

    expect(find.text('Chaos 同步器'), findsWidgets);
    expect(find.text('字体制作'), findsWidgets);

    // 底栏四格: 首页 / 商店 / 设置 / 设备。制作页不在底栏。
    for (final String label in <String>['商店', '设置', '设备', '首页']) {
      await tester.tap(find.text(label).last);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: '切到' + label + '时抛异常');
    }
    // 底栏不该再有制作页的两格。
    expect(find.text('字体'), findsNothing);
    expect(find.text('图标'), findsNothing);
  });

  testWidgets('字体页从首页卡片推入, 没字库时生成按钮不可点', (WidgetTester tester) async {
    await boot(tester);
    await tester.tap(find.text('字体制作'));
    // 路由推入要一帧真正 build 出页面, 再补一帧把 340ms 的转场走完。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('选择 TTF / OTF'), findsOneWidget);
    final Finder button = find.text('生成字体');
    expect(button, findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.ancestor(of: button, matching: find.byType(FilledButton))).onPressed,
      isNull,
    );
    // 推上来的页面没有底栏, 退回靠页头箭头。
    expect(find.text('首页'), findsNothing);
    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('选择 TTF / OTF'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('图标页从首页卡片推入并列出槽位', (WidgetTester tester) async {
    await boot(tester);
    await tester.tap(find.text('图标制作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('10 Pro'), findsWidgets);
    expect(find.text('9 Pro'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('商店是空白页, 摆明还没开始卖', (WidgetTester tester) async {
    await boot(tester);
    await tester.tap(find.text('商店').last);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('资源商店'), findsOneWidget);
    expect(find.text('这里还是空的。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏改用左侧导航栏，首页仍排两列', (WidgetTester tester) async {
    await boot(tester, width: 1280, height: 900);

    // 侧栏出现, 底栏胶囊消失。
    expect(find.byType(NavRail), findsOneWidget);
    expect(find.byType(PaperNavCapsule), findsNothing);
    expect(find.byType(NavCapsule), findsNothing);

    // 两张制作卡同排: 标题的纵向位置一致。
    final Offset font = tester.getTopLeft(find.text('字体制作'));
    final Offset icon = tester.getTopLeft(find.text('图标制作'));
    expect(font.dy, icon.dy);
    expect(icon.dx, greaterThan(font.dx));

    // 内容从侧栏右边开始, 不再被 720 的死版心卡住。
    final Rect list = tester.getRect(find.byType(ListView).first);
    expect(list.left, greaterThanOrEqualTo(200));
    expect(list.width, greaterThan(720));
    expect(list.width, lessThanOrEqualTo(1000));
    expect(tester.takeException(), isNull);
  });

  testWidgets('侧栏可以收起成图标条并再展开', (WidgetTester tester) async {
    // 偏好是全局单例, 用例之间会串味, 结束必须还原。
    addTearDown(() => UiPrefs.instance.setRailCollapsed(false));
    await boot(tester, width: 1200, height: 900);
    final double expanded = tester.getSize(find.byType(NavRail)).width;
    expect(expanded, greaterThan(200));

    await tester.tap(find.byTooltip('收起侧栏'));
    // 隐式动画要两帧: 第一帧把起点定下来, 再推进时间才会真的变化。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(UiPrefs.instance.railCollapsed, isTrue, reason: '点击应写进偏好');
    expect(tester.widget<NavRail>(find.byType(NavRail)).collapsed, isTrue, reason: '侧栏应收到收起状态');
    final double collapsed = tester.getSize(find.byType(NavRail)).width;
    expect(collapsed, lessThan(expanded));
    // 收起后文字隐藏, 但入口仍在(靠 Tooltip 说明)。
    expect(find.text('商店'), findsNothing);
    expect(find.byTooltip('商店'), findsOneWidget);
    expect(find.byTooltip('展开侧栏'), findsOneWidget);

    await tester.tap(find.byTooltip('展开侧栏'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(find.byType(NavRail)).width, expanded);
    expect(find.text('商店'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('侧栏四个入口都能切页', (WidgetTester tester) async {
    await boot(tester, width: 1200, height: 900);
    for (final String label in <String>['商店', '设置', '设备', '首页']) {
      await tester.tap(find.text(label).last);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: '切到' + label + '时抛异常');
    }
    expect(find.byType(NavRail), findsOneWidget);
  });

  testWidgets('窄屏仍是一列', (WidgetTester tester) async {
    await boot(tester, width: 420, height: 900);
    final Offset font = tester.getTopLeft(find.text('字体制作'));
    final Offset icon = tester.getTopLeft(find.text('图标制作'));
    expect(icon.dy, greaterThan(font.dy));
    expect(tester.takeException(), isNull);
  });
}