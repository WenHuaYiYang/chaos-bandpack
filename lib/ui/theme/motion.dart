import 'package:flutter/material.dart';

/// 动效开关: 系统关掉了动画就别硬放。
///
/// Android 的“移除动画”会把 animator duration scale 设成 0, Flutter 侧
/// MediaQuery.disableAnimationsOf 能读到。所有自造动效都要过这一关。
bool animationsEnabled(BuildContext context) =>
    !MediaQuery.disableAnimationsOf(context);

/// 逐段错峰入场: 第 i 块在 i*step 之后才开始, 用 [0,1] 的进度驱动淡入 + 上浮。
///
/// step 默认 70ms —— 比 Material 的默认 stagger 更陡一点, 因为制作台的卡片
/// 本来就少, 太绵会显得拖。
class EnterStep {
  EnterStep(this.controller, {this.count = 4, this.stepMs = 70, this.duration = const Duration(milliseconds: 520)});

  final AnimationController controller;
  final int count;
  final int stepMs;
  final Duration duration;

  /// 第 index 块的进度曲线(0..1)。用 easeOutCubic 收尾更干脆。
  Animation<double> of(int index) {
    final double start = (index * stepMs) / duration.inMilliseconds;
    final double end = start + (duration.inMilliseconds - (count - 1) * stepMs) / duration.inMilliseconds;
    final double begin = start.clamp(0.0, 1.0);
    final double finish = end.clamp(begin + 0.001, 1.0);
    return CurvedAnimation(
      parent: controller,
      curve: Interval(begin, finish, curve: Curves.easeOutCubic),
    );
  }
}

/// 入场修饰: 透明度 + 28dp 上浮。距离固定 28 是因为再大会撞到上一张卡。
class EnterLayer extends StatelessWidget {
  const EnterLayer({required this.t, required this.child, this.dy = 28, super.key});

  final Animation<double> t;
  final Widget child;
  final double dy;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, child) {
        final double v = t.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, (1 - v) * dy), child: child),
        );
      },
      child: child,
    );
  }
}

/// 「按下去会缩一下」的包装。做触感反馈用, 比 InkWell 的涟漪更像实体按键。
class PressScale extends StatefulWidget {
  const PressScale({required this.child, this.scale = 0.97, this.enabled = true, super.key});

  final Widget child;
  final double scale;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final bool live = widget.enabled && animationsEnabled(context);
    return GestureDetector(
      onTapDown: live ? (_) => setState(() => _down = true) : null,
      onTapCancel: live ? () => setState(() => _down = false) : null,
      onTapUp: live ? (_) => setState(() => _down = false) : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// 数值滚动: 数字变化时做一个短促的位移+淡出。
class TweenNumber extends StatelessWidget {
  const TweenNumber({required this.value, required this.style, this.align = TextAlign.start, super.key});

  final String value;
  final TextStyle style;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.35), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      child: Text(value, key: ValueKey<String>(value), style: style, textAlign: align),
    );
  }
}
