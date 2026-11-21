import 'dart:typed_data';

/// LVGL 图像文件与保留透明度的 I8/RLE 编码。
///
/// 文件头固定 12 字节(小端):
///
/// ```
/// [0]     cf    = 0x19  厂商自定义格式
/// [1]     pixel format: 16 = BGRA8888, 10 = I8(索引)
/// [2..3]  flags:  0 = 未压缩, 8 = RLE 压缩
/// [4..5]  w (u16LE)
/// [6..7]  h (u16LE)
/// [8..9]  stride (u16LE)
/// [10..11] 保留 0
/// ```
///
/// 9 Pro 的桌面图标另有一套 4 字节头: `u32LE = 5 | (w << 10) | (h << 21)`。
class LvglIconCodec {
  /// 图像头的魔数(cf 之前的那个 0x19)。
  static const int headerTag = 0x19;

  /// 索引图像的调色板字节数: 256 项 × BGRA。
  static const int paletteBytes = 1024;

  /// 解出来的图像: 宽、高与 ARGB 像素(行优先, 值域 0..0xFFFFFFFF)。
  // Kotlin 侧是 `LvglIconCodec.Image`; Dart 不能嵌套类, 提到顶层叫 LvglImage。
  static LvglImage decode(Uint8List bin) {
    // 9 Pro: 第一个字节不是 0x19 就是 4 字节被打包进 u32 的 BGRA 头。
    if (bin.length >= 4 && (bin[0] & 0xFF) != headerTag) {
      final word = _u32(bin, 0);
      final w = (word >> 10) & 2047;
      final h = (word >> 21) & 2047;
      if (!(word & 1023 == 5 &&
          w >= 1 && w <= 512 && h >= 1 && h <= 512 &&
          bin.length == 4 + w * h * 4)) {
        throw LvglIconError('不是完整的 9 Pro BGRA 图像');
      }
      return LvglImage(w, h, List<int>.generate(w * h, (i) => _u32(bin, 4 + i * 4)));
    }
    if (!(bin.length >= 12 && (bin[0] & 0xFF) == headerTag)) {
      throw LvglIconError('图像头不合法');
    }
    final cf = bin[1] & 0xFF;
    final flags = _u16(bin, 2);
    final w = _u16(bin, 4);
    final h = _u16(bin, 6);
    final stride = _u16(bin, 8);
    if (!(w >= 1 && w <= 512 && h >= 1 && h <= 512)) {
      throw LvglIconError('图像尺寸不合法');
    }
    if (cf == 16 && flags == 0) {
      if (!(stride >= w * 4 && bin.length == 12 + stride * h)) {
        throw LvglIconError('BGRA 图像数据长度不符');
      }
      return LvglImage(
          w, h, List<int>.generate(w * h, (i) => _u32(bin, 12 + (i ~/ w) * stride + (i % w) * 4)));
    }
    if (cf == 10 && flags == 0) {
      if (!(stride >= w && bin.length == 12 + paletteBytes + stride * h)) {
        throw LvglIconError('索引图像数据长度不符');
      }
      return LvglImage(
          w,
          h,
          List<int>.generate(w * h,
              (i) => _u32(bin, 12 + ((bin[12 + paletteBytes + (i ~/ w) * stride + (i % w)]) & 0xFF) * 4)));
    }
    if (!(cf == 10 && flags == 8 && stride >= w && stride <= 512 && bin.length >= 24)) {
      throw LvglIconError('图像编码不支持');
    }
    if (!(_u32(bin, 12) == 1 &&
        _u32(bin, 16) == bin.length - 24 &&
        _u32(bin, 20) == paletteBytes + stride * h)) {
      throw LvglIconError('RLE 图像头不自洽');
    }
    final raw = Uint8List(_u32(bin, 20));
    var at = 24;
    var dst = 0;
    while (at < bin.length) {
      final tag = bin[at++] & 0xFF;
      final count = tag & 127;
      if (!(count > 0 && dst + count <= raw.length)) {
        throw LvglIconError('RLE 段越界');
      }
      if (tag & 128 != 0) {
        if (!(at + count <= bin.length)) throw LvglIconError('RLE 字面段被截断');
        raw.setRange(dst, dst + count, bin, at);
        at += count;
      } else {
        if (!(at < bin.length)) throw LvglIconError('RLE 重复段被截断');
        raw.fillRange(dst, dst + count, bin[at++]);
      }
      dst += count;
    }
    if (dst != raw.length) throw LvglIconError('RLE 解压后长度不符');
    return LvglImage(
        w,
        h,
        List<int>.generate(w * h,
            (i) => _u32(raw, ((raw[paletteBytes + (i ~/ w) * stride + (i % w)]) & 0xFF) * 4)));
  }

  /// 12 字节图像头(小端)。w/h/stride 按 u16 截断, 与 Kotlin 的 `putShort` 一致。
  static Uint8List header(int w, int h, int cf, int flags, int stride) {
    final out = Uint8List(12);
    out[0] = headerTag;
    out[1] = cf;
    _w16(out, 2, flags);
    _w16(out, 4, w);
    _w16(out, 6, h);
    _w16(out, 8, stride);
    _w16(out, 10, 0);
    return out;
  }

  /// ARGB 像素 -> 固件要的 BGRA 字节流(前面加 12 字节头)。
  static Uint8List bgra(List<int> pixels, int w, int h) {
    if (pixels.length != w * h) throw LvglIconError('像素数组与尺寸不匹配');
    final out = Uint8List(12 + pixels.length * 4);
    out.setRange(0, 12, header(w, h, 16, 0, w * 4));
    var o = 12;
    for (final p in pixels) {
      out[o] = p & 0xFF; // B
      out[o + 1] = (p >> 8) & 0xFF; // G
      out[o + 2] = (p >> 16) & 0xFF; // R
      out[o + 3] = (p >> 24) & 0xFF; // A
      o += 4;
    }
    return out;
  }

  /// 9 Pro 的 4 字节头 + BGRA: 头里 (`5 | w<<10 | h<<21`) 一次性带走尺寸。
  static Uint8List bgra8(List<int> pixels, int w, int h) {
    if (!(w >= 1 && w <= 512 && h >= 1 && h <= 512 && pixels.length == w * h)) {
      throw LvglIconError('像素数组与尺寸不匹配');
    }
    final out = Uint8List(4 + pixels.length * 4);
    _w32(out, 0, 5 | (w << 10) | (h << 21));
    var o = 4;
    for (final p in pixels) {
      out[o] = p & 0xFF;
      out[o + 1] = (p >> 8) & 0xFF;
      out[o + 2] = (p >> 16) & 0xFF;
      out[o + 3] = (p >> 24) & 0xFF;
      o += 4;
    }
    return out;
  }

  /// 索引 + RLE: 1024 字节调色板 + 每像素 1 字节索引, 再做 15/7 位 RLE。
  ///
  /// 颜色不超过 255 种时直接按颜色值升序排调色板; 超过时用中位切分(median cut)量化到
  /// 255 色 —— 索引 0 永远留给透明, 所以真实颜色只能占 1..255。
  static Uint8List indexedRle(List<int> pixels, int w, int h) {
    if (!(w > 0 && h > 0 && pixels.length == w * h)) {
      throw LvglIconError('像素数组与尺寸不匹配');
    }
    final histogram = <int, int>{};
    for (final p in pixels) {
      if (_alpha(p) != 0) histogram[p] = (histogram[p] ?? 0) + 1;
    }
    final List<int> palette;
    if (histogram.length <= 255) {
      palette = histogram.keys.toList()..sort(_signedColorCompare);
    } else {
      final boxes = <_Box>[_Box([for (final e in histogram.entries) _ColorCount(e.key, e.value)])];
      while (boxes.length < 255) {
        // Kotlin 的 maxBy 在并列时取第一个, 这里用 > 保持同一取舍。
        var index = 0;
        var best = boxes[0].score;
        for (var i = 1; i < boxes.length; i++) {
          final score = boxes[i].score;
          if (score > best) {
            best = score;
            index = i;
          }
        }
        if (boxes[index].score < 0) break;
        final box = boxes.removeAt(index);
        final (a, b) = box.split();
        boxes.add(a);
        boxes.add(b);
      }
      palette = [for (final box in boxes) box.mean()];
    }
    final lookup = <int, int>{};
    for (final color in histogram.keys) {
      var bestIndex = 0;
      var bestError = -1;
      for (var i = 0; i < palette.length; i++) {
        final candidate = palette[i];
        final alpha = _channel(color, 3);
        final ca = _channel(candidate, 3);
        var error = (alpha - ca) * (alpha - ca) * 2;
        for (var ch = 0; ch < 3; ch++) {
          final delta = (_channel(color, ch) * alpha - _channel(candidate, ch) * ca) ~/ 255;
          error += delta * delta;
        }
        if (bestError < 0 || error < bestError) {
          bestError = error;
          bestIndex = i;
        }
      }
      lookup[color] = bestIndex + 1;
    }
    final raw = Uint8List(paletteBytes + pixels.length);
    _w32(raw, 0, 0);
    for (var i = 0; i < 255; i++) {
      _w32(raw, 4 + i * 4, i < palette.length ? palette[i] : 0);
    }
    for (var i = 0; i < pixels.length; i++) {
      final p = pixels[i];
      raw[paletteBytes + i] = _alpha(p) == 0 ? 0 : lookup[p]!;
    }
    final compressed = _rle(raw);
    final out = Uint8List(24 + compressed.length);
    out.setRange(0, 12, header(w, h, 10, 8, w));
    _w32(out, 12, 1);
    _w32(out, 16, compressed.length);
    _w32(out, 20, raw.length);
    out.setRange(24, 24 + compressed.length, compressed);
    return out;
  }

  /// 15/7 位 RLE: 控制字节 >= 0x80 -> 字面拷贝 (c & 0x7F) 字节; < 0x80 -> 重复 c 次。
  static Uint8List _rle(Uint8List raw) {
    final out = BytesBuilder(copy: true);
    var at = 0;
    int run(int start) {
      var n = 1;
      while (n < 127 && start + n < raw.length && raw[start + n] == raw[start]) {
        n++;
      }
      return n;
    }

    while (at < raw.length) {
      final count = run(at);
      if (count >= 3) {
        out.addByte(count);
        out.addByte(raw[at]);
        at += count;
      } else {
        final begin = at;
        at += count;
        while (at < raw.length && at - begin < 127 && run(at) < 3) {
          at += run(at) < 127 - (at - begin) ? run(at) : 127 - (at - begin);
        }
        out.addByte(0x80 | (at - begin));
        out.add(raw.sublist(begin, at));
      }
    }
    return out.takeBytes();
  }
}

/// 解出来的图像: 宽、高与 ARGB 像素。
class LvglImage {
  const LvglImage(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final List<int> pixels;
}

class LvglIconError implements Exception {
  LvglIconError(this.message);

  final String message;

  @override
  String toString() => 'LvglIconError: $message';
}

/// 一个颜色在直方图里的出现次数。
class _ColorCount {
  const _ColorCount(this.color, this.count);

  final int color;
  final int count;
}

/// 中位切分的候选盒子。
class _Box {
  _Box(this.colors);

  final List<_ColorCount> colors;

  /// 每个通道的跨度。
  late final List<int> ranges = List<int>.generate(
      4,
      (ch) =>
          colors.map((c) => _channel(c.color, ch)).reduce(_max) -
          colors.map((c) => _channel(c.color, ch)).reduce(_min));

  /// 切分用哪个通道: 取加权跨度最大的那个(alpha 权重 ×2)。
  int get splitChannel {
    var best = 0;
    var value = -1;
    for (var ch = 0; ch < 4; ch++) {
      final v = ranges[ch] * (ch == 3 ? 2 : 1);
      if (v > value) {
        value = v;
        best = ch;
      }
    }
    return best;
  }

  /// 盒子的切分价值; 只剩一种颜色时为 -1(不再可切)。
  int get score {
    if (colors.length <= 1) return -1;
    return ranges[splitChannel] * colors.fold<int>(0, (n, c) => n + c.count);
  }

  /// 按 [splitChannel] 排序后, 在像素数的一半处切开。
  (_Box, _Box) split() {
    final channel = splitChannel;
    final sorted = [...colors]..sort((a, b) {
        final c = _channel(a.color, channel).compareTo(_channel(b.color, channel));
        return c != 0 ? c : _signedColorCompare(a.color, b.color);
      });
    final half = sorted.fold<int>(0, (n, c) => n + c.count) ~/ 2;
    var sum = 0;
    var split = 1;
    for (var i = 0; i < sorted.length - 1; i++) {
      sum += sorted[i].count;
      split = i + 1;
      if (sum >= half) break;
    }
    return (_Box(sorted.sublist(0, split)), _Box(sorted.sublist(split)));
  }

  /// 盒子的加权平均色(每个通道分别取整)。
  int mean() {
    final total = colors.fold<int>(0, (n, c) => n + c.count);
    var result = 0;
    for (var ch = 0; ch < 4; ch++) {
      final sum = colors.fold<int>(0, (n, c) => n + _channel(c.color, ch) * c.count);
      result |= ((sum + total ~/ 2) ~/ total) << (ch * 8);
    }
    return result;
  }
}

int _max(int a, int b) => a > b ? a : b;

int _min(int a, int b) => a < b ? a : b;

/// Kotlin 的 Int 是有符号的: `colors.sorted()` 会把 alpha >= 0x80 的颜色排在前面。
/// 用异或 0x80000000 把无符号值映射成同一顺序, 保证调色板顺序逐字节一致。
int _signedColorCompare(int a, int b) => (a ^ 0x80000000).compareTo(b ^ 0x80000000);

int _alpha(int color) => (color >> 24) & 255;

int _channel(int color, int ch) => (color >> (ch * 8)) & 255;

int _u16(Uint8List b, int p) => (b[p] & 255) | ((b[p + 1] & 255) << 8);

int _u32(Uint8List b, int p) =>
    (b[p] & 255) | ((b[p + 1] & 255) << 8) | ((b[p + 2] & 255) << 16) | ((b[p + 3] & 255) << 24);

void _w16(Uint8List b, int p, int n) {
  b[p] = n & 255;
  b[p + 1] = (n >> 8) & 255;
}

void _w32(Uint8List b, int p, int n) {
  b[p] = n & 255;
  b[p + 1] = (n >> 8) & 255;
  b[p + 2] = (n >> 16) & 255;
  b[p + 3] = (n >> 24) & 255;
}
