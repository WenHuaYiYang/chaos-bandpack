import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../icon/animated_icons.dart';
import '../icon/dgf1.dart';
import '../icon/gif_icons.dart' as gif;
import '../icon/icon_convert.dart' as conv;
import '../icon/icon_spec.dart';
import '../icon/lvgl_icon_codec.dart';
import '../icon/portable_icons.dart';
import '../pack/cipk.dart';

/// 图标处理编排: 源文件 -> 槽位规格的 BIN(可带动画)。
///
/// 与 Kotlin 版 IconMake 同口径: GIF 出封面 + DGF1, _anim.bin 只带动画需要外部
/// 提供封面, 原生 BIN 原样带走, 普通图片走 IconConvert 的透明边裁剪与底板覆盖率
/// 检查。
///
/// 解码交给 package:image(纯 Dart), 所以这一层能跑在 isolate 里。
abstract final class IconMake {
  /// 单张图片的边长上限: 超过就先缩小再进算法, 免得几十兆的相机图撑爆内存。
  static const int maxDecodeSide = 1024;

  /// 转换一张输入。[name] 只用来判断类型(GIF / BIN / 图片), 大小写不敏感。
  ///
  /// [existingCover] 只在导入 _anim.bin 时需要: 动画本身没有封面像素, 必须有一张
  /// 96 x 96 的静态图配套。
  static IconMade convert({
    required Uint8List bytes,
    required String name,
    required IconSpecSlot slot,
    Uint8List? existingCover,
  }) {
    final String lower = name.toLowerCase();
    final bool isGif = gif.GifIcons.isGif(bytes) || lower.endsWith('.gif');
    if (isGif || Dgf1.isAnimation(bytes)) {
      if (!(slot.device.id == 'p67' &&
          slot.group == IconSpecGroup.desktop &&
          AnimatedIcons.stems.contains(slot.stem))) {
        throw IconMakeError(
            'GIF / DGF1 动画仅支持 10 Pro 桌面图标；9 Pro 和系统 UI 请使用静态图片或 BIN');
      }
      if (isGif) {
        final gif.Made made = gif.GifIcons.convert(bytes);
        return IconMade(
          bytes: made.cover,
          report: coverage(made.cover, slot),
          animation: made.animation,
          frames: made.frameCount,
        );
      }
      final Animation animation = Dgf1.parse(bytes);
      final Uint8List? cover = existingCover;
      if (cover == null) {
        throw IconMakeError('导入 _anim.bin 时必须同时提供 96 x 96 静态封面');
      }
      AnimatedIcons.validateProject(<String, Uint8List>{
        slot.stem: cover,
        AnimatedIcons.key(slot.stem): bytes,
      });
      return IconMade(
        bytes: cover,
        report: coverage(cover, slot),
        animation: bytes,
        frames: animation.frames.length,
      );
    }
    if (lower.endsWith('.bin')) {
      if (!(bytes.length <= Cipk.iconLenMax)) {
        throw IconMakeError('BIN 超过 ${Cipk.iconLenMax} 字节上限');
      }
      return IconMade(bytes: PortableIcons.convert(bytes, slot), report: null);
    }
    if (slot.group == IconSpecGroup.native) {
      throw IconMakeError('此系统资源只接受原尺寸的原生 BIN');
    }
    final (List<int> argb, int w, int h) = decodeArgb(bytes);
    final (Uint8List out, conv.Report report) =
        conv.IconConvert.convert(argb, w, h, slot);
    return IconMade(bytes: out, report: report);
  }

  /// 统计一张已转换封面的覆盖率(给界面显示, 不参与转换)。
  static conv.Report coverage(Uint8List cover, IconSpecSlot slot) {
    // 封面是固件用的 LVGL BIN, 不是 PNG; 跟 Kotlin 版一样先解成像素再算覆盖率。
    final LvglImage image = LvglIconCodec.decode(cover);
    final int opaque =
        image.pixels.where((int p) => (p >> 24) & 0xFF > 200).length;
    final int side = math.max(image.width, image.height);
    return conv.Report(opaque / image.pixels.length, side, side);
  }

  /// 把任意图片解码成 ARGB int 列表(每像素 0xAARRGGBB)。
  ///
  /// 长边超过 [maxDecodeSide] 时先等比缩小; 真正的缩放置换交给 IconConvert, 这里
  /// 只为省内存。
  static (List<int>, int, int) decodeArgb(Uint8List bytes) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } on Object {
      decoded = null;
    }
    if (decoded == null) throw IconMakeError('这个文件不是图片');
    var source = decoded;
    final int longest = math.max(source.width, source.height);
    if (longest > maxDecodeSide) {
      final double k = maxDecodeSide / longest;
      source = img.copyResize(
        decoded,
        width: math.max(1, (decoded.width * k).round()),
        height: math.max(1, (decoded.height * k).round()),
        interpolation: img.Interpolation.average,
      );
    }
    final int w = source.width;
    final int h = source.height;
    final List<int> argb = List<int>.filled(w * h, 0);
    for (var y = 0; y < h; y++) {
      final int row = y * w;
      for (var x = 0; x < w; x++) {
        final img.Pixel p = source.getPixel(x, y);
        argb[row + x] = ((p.a.toInt() & 0xFF) << 24) |
            ((p.r.toInt() & 0xFF) << 16) |
            ((p.g.toInt() & 0xFF) << 8) |
            (p.b.toInt() & 0xFF);
      }
    }
    return (argb, w, h);
  }
}

/// 一次转换的结果。动画为 null 表示这是静态封面。
class IconMade {
  const IconMade({
    required this.bytes,
    required this.report,
    this.animation,
    this.frames = 0,
  });

  final Uint8List bytes;
  final conv.Report? report;
  final Uint8List? animation;
  final int frames;

  bool get animated => animation != null;
}

class IconMakeError implements Exception {
  IconMakeError(this.message);

  final String message;

  @override
  String toString() => 'IconMakeError: $message';
}
