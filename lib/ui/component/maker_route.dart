import 'package:flutter/material.dart';

import '../../chaos/session.dart';
import '../../chaos/session_scope.dart';
import '../../project/project_store.dart';
import '../theme/tone.dart';

/// 把制作页推成全屏路由, 并替它挂上外壳提供的那几个作用域。
///
/// 字体页和图标页不进底栏(四格留给每天都要看的入口), 从首页卡片推上来。
///
/// 关键点: 路由是挂在 MaterialApp 的 Navigator 上的, 而 SessionScope /
/// ProjectScope / ToneScope 都在外壳里面 —— 推上去的页面默认什么也看不见,
/// 一进 didChangeDependencies 就会断言「不在树里」。所以三个作用域要在这里
/// 重新包一层, 传进来的都是外壳里那份同一个实例, 不是新建的。
Route<void> makerRoute({
  required String label,
  required Widget page,
  required PageTone Function(BuildContext) tone,
  required ChaosSession session,
  required ProjectStore project,
}) {
  return PageRouteBuilder<void>(
    settings: RouteSettings(name: label),
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondary) {
      final PageTone t = tone(context);
      return SessionScope(
        session: session,
        child: ProjectScope(
          store: project,
          child: ToneScope(
            tone: t,
            // 垫一层透明 Material: 卡片之外的 InkWell(顶栏按钮、分段器)也要有
            // Material 祖先, 少了它会在 build 时断言失败。
            child: Material(
              type: MaterialType.transparency,
              child: ColoredBox(
                color: t.field,
                // 新路由不在首页外壳的 SafeArea 内；只内缩内容，底色仍铺满窗口。
                child: SafeArea(bottom: false, child: page),
              ),
            ),
          ),
        ),
      );
    },
    transitionsBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondary, Widget child) {
      final double t = Curves.easeOutCubic.transform(animation.value);
      return Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
      );
    },
  );
}