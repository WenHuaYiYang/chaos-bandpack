import 'package:chaos_bandpack/ui/chaos_app.dart';
import 'package:chaos_bandpack/ui/screen/font_screen.dart';
import 'package:chaos_bandpack/ui/theme/paper_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double _height = 930;
const double _dpr = 2;
const double _statusInset = 56;
const double _navigationInset = 24;

Future<void> _openFontMaker(WidgetTester tester) async {
  tester.view.devicePixelRatio = _dpr;
  tester.view.physicalSize = const Size(432 * _dpr, _height * _dpr);
  tester.view.viewPadding = tester.view.padding = const FakeViewPadding(
    top: _statusInset * _dpr,
    bottom: _navigationInset * _dpr,
  );
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: PaperPalette.theme(Brightness.light),
      home: const ChaosApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('字体制作'));
  await tester.pumpAndSettle();
  expect(find.byType(FontScreen), findsOneWidget);
}

void main() {
  testWidgets('从首页打开字体制作时，页头避开状态栏', (tester) async {
    await _openFontMaker(tester);

    for (final Finder header in [find.text('字体制作'), find.byTooltip('返回')]) {
      expect(tester.getTopLeft(header).dy, greaterThanOrEqualTo(_statusInset));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('键盘弹出时，字体制作自动滚动以露出已聚焦的输入框', (tester) async {
    await _openFontMaker(tester);
    final Finder field = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '兼容包标题',
    );
    final Finder editor = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    final Finder list = find.byType(ListView);
    final ScrollPosition position = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    ).position;
    final double normalViewportBottom = tester.getRect(list).bottom;

    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(editor).focusNode.hasFocus, isTrue);
    final double previousOffset = position.pixels;
    // 模拟键盘遮住刚点中的编辑区，不能只验证原本就在键盘上方的输入框。
    final double keyboardTop = tester.getCenter(editor).dy - 48;
    tester.view.padding = const FakeViewPadding(top: _statusInset * _dpr);
    tester.view.viewInsets = FakeViewPadding(bottom: (_height - keyboardTop) * _dpr);
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(previousOffset));
    expect(tester.getRect(list).bottom, lessThanOrEqualTo(keyboardTop));
    expect(tester.getRect(editor).bottom, lessThanOrEqualTo(keyboardTop));
    expect(editor.hitTestable(), findsOneWidget);
    expect(tester.widget<EditableText>(editor).focusNode.hasFocus, isTrue);

    tester.view.resetViewInsets();
    tester.view.padding = tester.view.viewPadding;
    await tester.pumpAndSettle();
    expect(tester.getRect(list).bottom, closeTo(normalViewportBottom, 0.01));
    expect(tester.takeException(), isNull);
  });
}
