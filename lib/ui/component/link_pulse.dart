import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/tone.dart';

/// 连接状态徽记：一条蓝牙链路正在"接通"的视觉隐喻。
///
/// 三圈扩散的波纹从中心发出，中心的蓝牙符号随阶段旋转、呼吸；连上之后波纹
/// 收拢成一圈稳定的光晕，断开则熄灭。所有动画都走 [animationsEnabled]，
/// 系统关掉动画时只画一帧静态图，不会偷偷继续耗电。
class LinkPulse extends StatefulWidget {
  const LinkPulse({
    required this.active,
    this.busy = false,
    this.size = 64,
    super.key,
  });

  /// 已经握手完成：波纹收拢、颜色转绿。
  final bool active;

  /// 正在连接或搜索：中心符号旋转，波纹加速。
  final bool busy;

  final double size;

  @override
  State<LinkPulse> createState() => _LinkPulseState();
}

class _LinkPulseState extends State<LinkPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(LinkPulse old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final bool live = animationsEnabled(context);
    if (!live) {
      _c.stop();
      _c.value = widget.active ? 1 : 0;
      return;
    }
    // 只有"正在接通"才无限循环。连上之后播一遍收拢动画就停 —— 永久动画会让
    // 整页永远处于"还在动"的状态, 界面测试的 pumpAndSettle 也永远等不到静止,
    // 顺带省掉一个常驻的重绘。
    if (widget.busy) {
      if (!_c.isAnimating) _c.repeat();
    } else if (widget.active) {
      if (_c.isAnimating) _c.stop();
      if (_c.value != 1) _c.forward();
    } else if (_c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PageTone tone = ToneScope.of(context);
    final Color glow = widget.active ? const Color(0xFF30A46C) : tone.deep;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final double t = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              for (int i = 0; i < 3; i++)
                _Ring(
                  progress: (t + i / 3) % 1,
                  color: glow,
                  size: widget.size,
                  still: !widget.busy && !widget.active,
                ),
              Container(
                width: widget.size * 0.46,
                height: widget.size * 0.46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glow.withValues(alpha: widget.active ? 0.20 : 0.12),
                ),
                child: Transform.rotate(
                  angle: widget.busy ? math.sin(t * math.pi * 2) * 0.14 : 0,
                  child: Icon(
                    Icons.bluetooth,
                    size: widget.size * 0.26,
                    color: glow,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.progress,
    required this.color,
    required this.size,
    required this.still,
  });

  final double progress;
  final Color color;
  final double size;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final double eased = Curves.easeOutCubic.transform(progress);
    final double d = size * (still ? 0.62 : (0.44 + 0.56 * eased));
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: still ? 0.18 : 0.30 * (1 - eased)),
          width: 1.6,
        ),
      ),
    );
  }
}
