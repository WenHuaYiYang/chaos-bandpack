import 'dart:math' as math;
import 'dart:typed_data';

import 'dgf1.dart';
import 'device_target.dart';
import 'icon_spec.dart';
import 'lvgl_icon_codec.dart';

/// 原生图标的转换。p67 的新桌面图会保留完整源画布与 alpha, 居中放进 96 × 96 的
/// BGRA 图; 系统图标保持自己的槽位几何; 老的 9 Pro 100 × 100 转换仍保留内容/底板检查。
/// 缩放一律按预乘 alpha 做。
///
/// Kotlin 侧用 `android.graphics.Bitmap` 做解码与缩放; 这里只吃像素数组,
/// 解码交给 `package:image`(见 [packArgb]), 所以本文件不 import flutter/dart:ui。
class IconConvert {
  /// 认定"这里有内容"的 alpha 门（与 PC 侧取同一个值）
  static const int alphaHit = 24;

  /// 认定"这里是实心底板"的 alpha 门
  static const int alphaPlate = 200;

  /// 低于此覆盖率判为透明底裸图形
  static const double plateMinCoverage = 0.55;

  static const double _lanczosA = 3.0;

  /// 转换统计: 底板覆盖率、源方框边长、缩放后的内容边长。
  static (Uint8List, Report) convert(List<int> src, int w, int h, [IconSpecSlot? slot]) {
    final s = slot ?? IconSpec.desktop.first;
    if (s.group == IconSpecGroup.native) {
      throw IconConvertError('此系统资源请导入已转换的 BIN，原尺寸会被保留');
    }
    if (s.group == IconSpecGroup.desktop && s.device == DeviceTarget.tenPro) {
      final pixels = fitCanvas(src, w, h, Dgf1.side);
      final coverage = pixels.where((p) => _alpha(p) > alphaPlate).length / pixels.length;
      return (
        LvglIconCodec.bgra(pixels, Dgf1.side, Dgf1.side),
        Report(coverage, math.max(w, h), Dgf1.side)
      );
    }
    if (s.group != IconSpecGroup.desktop) return _convertSystem(src, w, h, s);
    if (!(w > 0 && h > 0 && src.length >= w * h)) {
      throw IconConvertError('像素数组与尺寸不匹配');
    }

    // 1. 外接方框（alpha > ALPHA_HIT）
    var x0 = w;
    var x1 = -1;
    var y0 = h;
    var y1 = -1;
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        if (_alpha(src[row + x]) > alphaHit) {
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
      }
    }
    if (x1 < 0) throw Blank();

    // 取正方形外接框，长边贴齐画幅时向内收，避免裁到图外
    var side = math.max(x1 - x0, y1 - y0) + 1;
    side = math.min(side, math.min(w, h));
    final cx = (x0 + x1 + 1) ~/ 2;
    final cy = (y0 + y1 + 1) ~/ 2;
    final bx = math.max(0, math.min(cx - side ~/ 2, w - side));
    final by = math.max(0, math.min(cy - side ~/ 2, h - side));

    // 2. 底板覆盖率：方框内 alpha > ALPHA_PLATE 的比例
    var opaque = 0;
    for (var y = by; y < by + side; y++) {
      final row = y * w;
      for (var x = bx; x < bx + side; x++) {
        if (_alpha(src[row + x]) > alphaPlate) opaque++;
      }
    }
    final coverage = opaque / (side * side);
    if (coverage <= plateMinCoverage) throw NoPlate(coverage);

    // 3. 只缩放，不重画：方框 -> 内容框
    final fitted = _scaleBox(src, w, bx, by, side, s.content);

    // 4. 居中贴到画布，透明边自然成为桌面间距
    final canvas = List<int>.filled(s.width * s.height, 0);
    final off = (s.width - s.content) ~/ 2;
    for (var y = 0; y < s.content; y++) {
      final srcRow = y * s.content;
      final dstRow = (y + off) * s.width + off;
      canvas.setRange(dstRow, dstRow + s.content, fitted, srcRow);
    }

    return (_encode(canvas, s), Report(coverage, side, s.content));
  }

  /// 系统图标(控制中心/设置/系统应用): 裁掉四周透明边, 补成正方形, 再缩到槽位内容框。
  static (Uint8List, Report) _convertSystem(List<int> src, int w, int h, IconSpecSlot slot) {
    if (!(w > 0 && h > 0 && src.length >= w * h)) {
      throw IconConvertError('像素数组与尺寸不匹配');
    }
    var x0 = w;
    var y0 = h;
    var x1 = -1;
    var y1 = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (_alpha(src[y * w + x]) != 0) {
          x0 = math.min(x0, x);
          x1 = math.max(x1, x);
          y0 = math.min(y0, y);
          y1 = math.max(y1, y);
        }
      }
    }
    if (x1 < 0) throw Blank();
    final side = math.max(x1 - x0 + 1, y1 - y0 + 1);
    final square = List<int>.filled(side * side, 0);
    final dx = (side - (x1 - x0 + 1)) ~/ 2;
    final dy = (side - (y1 - y0 + 1)) ~/ 2;
    for (var y = y0; y <= y1; y++) {
      square.setRange((y - y0 + dy) * side + dx, (y - y0 + dy) * side + dx + (x1 - x0 + 1), src,
          y * w + x0);
    }
    final scaled = _scaleBox(square, side, 0, 0, side, slot.content);
    final coverage = square.where((p) => _alpha(p) > alphaPlate).length / square.length;
    final canvas = List<int>.filled(slot.width * slot.height, 0);
    final ox = (slot.width - slot.content) ~/ 2;
    final oy = (slot.height - slot.content) ~/ 2;
    for (var y = 0; y < slot.content; y++) {
      canvas.setRange((y + oy) * slot.width + ox, (y + oy) * slot.width + ox + slot.content,
          scaled, y * slot.content);
    }
    return (_encode(canvas, slot), Report(coverage, side, slot.content));
  }

  /// 9 Pro 走 4 字节头的 BGRA, p67 走 12 字节头的 BGRA。
  static Uint8List _encode(List<int> pixels, IconSpecSlot slot) =>
      slot.device == DeviceTarget.ninePro
          ? LvglIconCodec.bgra8(pixels, slot.width, slot.height)
          : LvglIconCodec.bgra(pixels, slot.width, slot.height);

  /// Kotlin 侧的 `internal fun resizeSquare`: 把边长 [side] 的方图缩到 [to]。
  static List<int> resizeSquare(List<int> pixels, int side, int to) =>
      _scaleBox(pixels, side, 0, 0, side, to);

  /// 保留完整的逻辑画布与透明信息, 非正方形输入居中。
  static List<int> fitCanvas(List<int> pixels, int width, int height, int to) {
    if (!(width > 0 && height > 0 && width * height <= pixels.length && to > 0)) {
      throw IconConvertError('像素数组与尺寸不匹配');
    }
    final side = math.max(width, height);
    return _scaleBox(
        pixels, width, -(side - width) ~/ 2, -(side - height) ~/ 2, side, to);
  }

  // ===== 缩放 =====

  /// 从 [src] 里取出 [side]x[side] 的方框（左上角 [bx],[by]），等比缩放到 [dst]x[dst]。
  /// Lanczos-3，可分离（先横后竖），预乘 alpha。
  static List<int> _scaleBox(
      List<int> src, int srcW, int bx, int by, int side, int dst) {
    final srcH = src.length ~/ srcW;
    if (side == dst) {
      final out = List<int>.filled(dst * dst, 0);
      for (var y = 0; y < dst; y++) {
        for (var x = 0; x < dst; x++) {
          final sx = bx + x;
          final sy = by + y;
          if (sx >= 0 && sx < srcW && sy >= 0 && sy < srcH) {
            out[y * dst + x] = src[sy * srcW + sx];
          }
        }
      }
      return out;
    }

    final k = _weights(side, dst);

    // 横pass：预乘成 4 个浮点通道(r,g,b 已乘 alpha, a 原样)。
    // 用 Float32List 而不是 List<double>: Kotlin 侧是 FloatArray, 每个权重存进去都要
    // 过一遍 float 舍入, 少了这一步两侧会差最后一两位。
    final horiz = Float32List(dst * side * 4);
    for (var y = 0; y < side; y++) {
      final row = (by + y) * srcW + bx;
      for (var x = 0; x < dst; x++) {
        var r = 0.0;
        var g = 0.0;
        var b = 0.0;
        var a = 0.0;
        final base = x * k.n;
        for (var j = 0; j < k.n; j++) {
          final w = k.wgt[base + j];
          if (w == 0.0) continue;
          final sx = bx + k.idx[base + j];
          final p = (sx >= 0 && sx < srcW && by + y >= 0 && by + y < srcH)
              ? src[row + k.idx[base + j]]
              : 0;
          final pa = _alpha(p);
          final f = w * pa;
          r += ((p >> 16) & 0xFF) * f;
          g += ((p >> 8) & 0xFF) * f;
          b += (p & 0xFF) * f;
          a += f;
        }
        final o = (y * dst + x) * 4;
        horiz[o] = r;
        horiz[o + 1] = g;
        horiz[o + 2] = b;
        horiz[o + 3] = a;
      }
    }

    // 竖pass
    final out = List<int>.filled(dst * dst, 0);
    for (var x = 0; x < dst; x++) {
      for (var y = 0; y < dst; y++) {
        var r = 0.0;
        var g = 0.0;
        var b = 0.0;
        var a = 0.0;
        final base = y * k.n;
        for (var j = 0; j < k.n; j++) {
          final w = k.wgt[base + j];
          if (w == 0.0) continue;
          final o = (k.idx[base + j] * dst + x) * 4;
          r += horiz[o] * w;
          g += horiz[o + 1] * w;
          b += horiz[o + 2] * w;
          a += horiz[o + 3] * w;
        }
        // 除回来：r/g/b 累加时已经乘过 alpha(0..255)，直接除以 alpha 累加值
        // 就得到 alpha 加权平均色，再取整成 0..255
        final inv = a > 1e-6 ? 1.0 / a : 0.0;
        out[y * dst + x] = (_clamp255(a) << 24) |
            (_clamp255(r * inv) << 16) |
            (_clamp255(g * inv) << 8) |
            _clamp255(b * inv);
      }
    }
    return out;
  }

  static int _clamp255(double v) {
    if (v <= 0.0) return 0;
    if (v >= 255.0) return 255;
    return (v + 0.5).floor();
  }

  /// 一维重采样权重表：dst 个输出点，每个固定取 [n] 个源点（不足的补 0 权重）
  static _Weights _weights(int size, int dst) {
    final scale = size / dst;
    final filterScale = math.max(1.0, scale);
    final support = _lanczosA * filterScale;
    final n = (2 * support).floor() + 3;
    final idx = Int32List(dst * n);
    final wgt = Float32List(dst * n);
    for (var ox = 0; ox < dst; ox++) {
      final c = (ox + 0.5) * scale - 0.5;
      final lo = (c - support).ceil();
      final hi = (c + support).floor();
      var sum = 0.0;
      var j = 0;
      for (var i = lo; i <= hi; i++) {
        if (j >= n) break;
        final w = _lanczos((i - c) / filterScale);
        idx[ox * n + j] = i.clamp(0, size - 1);
        wgt[ox * n + j] = w;
        sum += w;
        j++;
      }
      if (sum != 0.0 && sum != 1.0) {
        final inv = 1.0 / sum;
        for (var q = 0; q < j; q++) {
          wgt[ox * n + q] = wgt[ox * n + q] * inv;
        }
      }
    }
    return _Weights(idx, wgt, n);
  }

  /// Lanczos-3 核
  static double _lanczos(double x) {
    if (x == 0.0) return 1.0;
    final ax = x.abs();
    if (ax >= _lanczosA) return 0.0;
    final px = math.pi * x;
    return _lanczosA * math.sin(px) * math.sin(px / _lanczosA) / (px * px);
  }

  // ===== 打包 =====

  /// ARGB -> 固件要的 BGRA 字节流（前面加 12 字节头, 尺寸固定为 IconSpec.CANVAS）
  static Uint8List packArgb(List<int> argb) {
    final out = Uint8List(IconSpec.outBytes);
    out.setRange(0, 12, IconSpec.header);
    var o = 12;
    for (final p in argb) {
      out[o] = p & 0xFF; // B
      out[o + 1] = (p >> 8) & 0xFF; // G
      out[o + 2] = (p >> 16) & 0xFF; // R
      out[o + 3] = (p >> 24) & 0xFF; // A
      o += 4;
    }
    return out;
  }
}

/// 转换统计: 底板覆盖率、源方框边长、缩放后的内容边长。
class Report {
  const Report(this.coverage, this.srcBoxSide, this.scaled);

  final double coverage;
  final int srcBoxSide;
  final int scaled;
}

/// 一维重采样权重表。
class _Weights {
  const _Weights(this.idx, this.wgt, this.n);

  final Int32List idx;
  final Float32List wgt;
  final int n;
}

/// 源图全透明（Kotlin 侧的 `IconConvert.Blank`）。
class Blank extends IconConvertError {
  Blank() : super('这张图整幅都是透明的，没有可用的内容');
}

/// 透明底裸图形（Kotlin 侧的 `IconConvert.NoPlate`）：贴到桌面会比系统图标小一圈。
class NoPlate extends IconConvertError {
  NoPlate(this.coverage)
      : super('这张图没有底板（内容只占方框的 ${(coverage * 100).toStringAsFixed(0)}%），'
            '贴到桌面会比系统图标小一圈。请换一张自带底色的图。');

  /// 方框内实心像素的占比。
  final double coverage;
}

class IconConvertError implements Exception {
  IconConvertError(this.message);

  final String message;

  @override
  String toString() => 'IconConvertError: $message';
}

int _alpha(int color) => (color >> 24) & 0xFF;
