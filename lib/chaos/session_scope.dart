import 'package:flutter/widgets.dart';

import 'session.dart';

/// 把连接会话提到应用根部: 字体页/图标页也要能投递, 不能各开一条 SPP。
///
/// 用 [InheritedNotifier] 是因为 [ChaosSession] 本身就是 ChangeNotifier ——
/// 连接状态一变, 所有关心它的页面一起重建, 不需要各自转发。
class SessionScope extends InheritedNotifier<ChaosSession> {
  const SessionScope({required ChaosSession session, required super.child, super.key})
      : super(notifier: session);

  /// 会建立依赖(会话变化时重建调用方)。页面 build 里用这个。
  static ChaosSession of(BuildContext context) {
    final SessionScope? s = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(s != null, '没有 SessionScope —— 检查 widget 树是否在 ChaosApp 之下');
    return s!.notifier!;
  }

  /// 不建立依赖。initState 里用这个, 避免在 initState 里注册依赖。
  static ChaosSession read(BuildContext context) {
    final SessionScope? s =
        context.getElementForInheritedWidgetOfExactType<SessionScope>()?.widget as SessionScope?;
    assert(s != null, '没有 SessionScope —— 检查 widget 树是否在 ChaosApp 之下');
    return s!.notifier!;
  }
}
