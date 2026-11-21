import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Animation;

import '../../icon/dgf1.dart';
import '../theme/paper_palette.dart';
import '../theme/tone.dart';
import 'app_icons.dart';
import 'paper_card.dart';

/// 动态图标预览。
///
/// 格子上的缩略图只能看到封面, 想确认这段动画到底怎么动、有多长, 得按真实
/// 每帧时长放一遍。播放节奏跟着设备的定时器走, 导出仍按帧表里的原始时长。
Future<void> showAnimatedIconDialog(BuildContext context, {required Uint8List bytes}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) => _AnimatedIconSheet(bytes: bytes),
  );
}

class _AnimatedIconSheet extends StatefulWidget {
  const _AnimatedIconSheet({required this.bytes});

  final Uint8List bytes;

  @override
  State<_AnimatedIconSheet> createState() => _AnimatedIconSheetState();
}

class _AnimatedIconSheetState extends State<_AnimatedIconSheet> {
  Animation? _animation;
  String? _failure;
  ui.Image? _image;
  Timer? _timer;

  int _frame = 0;
  int _rounds = 0;
  bool _playing = true;

  /// 解码是异步的。回填时用它判断这次结果是不是还属于当前这一帧。
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    try {
      _animation = Dgf1.parse(widget.bytes);
    } on Dgf1Error catch (e) {
      _failure = e.message;
      return;
    }
    _show(0);
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _image?.dispose();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    final Animation? a = _animation;
    if (a == null || !_playing) return;
    _timer = Timer(Duration(milliseconds: a.frames[_frame].delayMs), _advance);
  }

  void _advance() {
    final Animation? a = _animation;
    if (a == null || !mounted) return;
    if (_frame + 1 == a.frames.length) {
      _rounds++;
      // plays 为 0 表示无限循环; 否则播满即停在最后一帧。
      if (a.plays != 0 && _rounds >= a.plays) {
        setState(() => _playing = false);
        return;
      }
      setState(() => _frame = 0);
    } else {
      setState(() => _frame = _frame + 1);
    }
    _show(_frame);
    _schedule();
  }

  void _toggle() {
    if (_animation == null) return;
    setState(() => _playing = !_playing);
    if (_playing) {
      _show(_frame);
      _schedule();
    } else {
      _timer?.cancel();
    }
  }

  void _replay() {
    setState(() {
      _frame = 0;
      _rounds = 0;
      _playing = true;
    });
    _show(0);
    _schedule();
  }

  /// 把一帧解成 ui.Image。走 ImageDescriptor.raw 直传像素, 不编码 PNG。
  Future<void> _show(int index) async {
    final Animation? a = _animation;
    if (a == null) return;
    final int tag = ++_generation;
    final Uint8List rgba = _rgba(a.pixels(index));
    ui.Image? made;
    try {
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
      final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: Dgf1.side,
        height: Dgf1.side,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final ui.Codec codec = await descriptor.instantiateCodec();
      final ui.FrameInfo info = await codec.getNextFrame();
      made = info.image;
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    } on Object {
      made = null;
    }
    if (!mounted || tag != _generation) {
      made?.dispose();
      return;
    }
    final ui.Image? old = _image;
    setState(() => _image = made);
    old?.dispose();
  }

  /// ARGB int -> RGBA 字节。dart:ui 只要这个顺序。
  static Uint8List _rgba(List<int> pixels) {
    final Uint8List out = Uint8List(Dgf1.pixels * 4);
    for (var i = 0; i < Dgf1.pixels; i++) {
      final int c = pixels[i];
      final int o = i * 4;
      out[o] = (c >> 16) & 0xFF;
      out[o + 1] = (c >> 8) & 0xFF;
      out[o + 2] = c & 0xFF;
      out[o + 3] = (c >> 24) & 0xFF;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final PageTone tone = ToneScope.of(context);
    final ThemeData theme = Theme.of(context);
    final Animation? a = _animation;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: PaperCard(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('动态图标预览', style: theme.textTheme.titleLarge),
            const SizedBox(height: 14),
            if (a == null)
              Text(_failure ?? '这个动画读不出来', style: theme.textTheme.bodyMedium?.copyWith(color: tone.muted))
            else ...<Widget>[
              Center(
                child: Container(
                  width: 192,
                  height: 192,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(PaperPalette.shapeMd),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _image == null
                      ? const SizedBox.expand()
                      : RawImage(
                          image: _image,
                          width: 192,
                          height: 192,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.none,
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _summary(a),
                style: theme.textTheme.bodyMedium?.copyWith(color: tone.muted),
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  TextButton.icon(
                    onPressed: _toggle,
                    icon: Icon(_playing ? AppIcons.pause : AppIcons.play, size: 18),
                    label: Text(_playing ? '暂停' : '播放'),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: _replay,
                    icon: const Icon(AppIcons.refresh, size: 18),
                    label: const Text('重播'),
                  ),
                ],
              ),
              Text(
                '预览节奏受刷新率影响; 导出保留每帧时长。',
                style: theme.textTheme.bodySmall?.copyWith(color: tone.muted),
              ),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _summary(Animation a) {
    final String seconds = (a.durationMs / 1000).toStringAsFixed(2);
    final String loops = a.plays == 0 ? '无限循环' : '播放 ' + a.plays.toString() + ' 轮';
    return a.frames.length.toString() + ' 帧 · ' + seconds + ' 秒/轮 · ' + loops;
  }
}
