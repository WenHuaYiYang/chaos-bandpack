import 'dart:typed_data';

import 'dgf1.dart';
import 'icon_convert.dart';
import 'lvgl_icon_codec.dart';

/// GIF87a/89a 解码: 局部调色板、隔行扫描、disposal 0–3 全部支持。
///
/// 解出来的每一帧都先合成到逻辑画布上(与 Pillow 的行为一致), 再交给 DGF1。
class GifIcons {
  /// 源文件上限。
  static const int maxSourceBytes = 32000000;

  /// 逻辑画布的像素上限(2048 × 2048)。
  static const int _maxCanvasPixels = 4194304;

  /// 是不是 GIF(只看 6 字节魔数)。
  static bool isGif(Uint8List bytes) =>
      bytes.length >= 6 &&
      (_ascii(bytes, 0, 6) == 'GIF87a' || _ascii(bytes, 0, 6) == 'GIF89a');

  /// 转成 DGF1: 第一帧同时出成静态封面(p67 的 96 × 96 BGRA)。
  static Made convert(Uint8List bytes) {
    if (!(bytes.length >= 13 && bytes.length <= maxSourceBytes && isGif(bytes))) {
      throw GifIconError('不是 GIF 图片，或源文件超过 32 MB');
    }
    final r = _Reader(bytes);
    r.skip(6);
    final width = r.word();
    final height = r.word();
    if (!(width >= 1 &&
        width <= 4096 &&
        height >= 1 &&
        height <= 4096 &&
        width * height <= _maxCanvasPixels)) {
      throw GifIconError('GIF 画布过大（最多 4096 边长、4194304 像素）');
    }
    final flags = r.byte();
    final background = r.byte();
    r.byte();
    final global = flags & 128 != 0 ? r.palette(1 << ((flags & 7) + 1)) : null;
    final canvas = List<int>.filled(width * height, 0);
    var initialized = false;
    var initialTransparency = false;
    var disposal = 0;
    var transparent = -1;
    var delay = 100;
    var previousDisposal = 0;
    var previousLeft = 0;
    var previousTop = 0;
    var previousWidth = 0;
    var previousHeight = 0;
    var previousClear = 0;
    List<int>? restore;
    var plays = 1;
    var ended = false;
    final frames = <Frame>[];
    while (r.remaining > 0 && !ended) {
      final tag = r.byte();
      if (tag == 0x3b) {
        ended = true;
      } else if (tag == 0x21) {
        final label = r.byte();
        if (label == 0xf9) {
          if (r.byte() != 4) throw GifIconError('GIF 控制块长度不合法');
          final control = r.byte();
          final specifiedDisposal = (control >> 2) & 7;
          if (!(specifiedDisposal >= 0 && specifiedDisposal <= 3)) {
            throw GifIconError('GIF disposal 模式不支持：$specifiedDisposal');
          }
          // 未指定的 disposal 沿用上一次显式指定的值, 与 Pillow 一致。
          if (specifiedDisposal != 0) disposal = specifiedDisposal;
          delay = r.word() * 10;
          final index = r.byte();
          transparent = control & 1 != 0 ? index : -1;
          if (r.byte() != 0) throw GifIconError('GIF 控制块未结束');
        } else if (label == 0xff) {
          final application = _asciiFromBytes(r.take(r.byte()));
          final data = r.blocks();
          if (application == 'NETSCAPE2.0' || application == 'ANIMEXTS1.0') {
            if (!(data.length >= 3 && data[0] == 1)) {
              throw GifIconError('GIF 循环扩展不合法');
            }
            final repeats = Dgf1.u16(data, 1);
            plays = repeats == 0 ? 0 : repeats + 1;
          }
        } else if (label == 0x01) {
          throw GifIconError('GIF 包含文本绘制扩展，请先转换为普通图片帧');
        } else {
          r.blocks();
        }
      } else if (tag == 0x2c) {
        if (!(frames.length < Dgf1.maxFrames)) {
          throw GifIconError('GIF 超过 256 帧；不会自动抽帧');
        }
        if (!(delay >= 1 && delay <= 60000)) {
          throw GifIconError('GIF 第 ${frames.length + 1} 帧的时长须为 1–60000 ms（当前 $delay ms）');
        }
        final left = r.word();
        final top = r.word();
        final w = r.word();
        final h = r.word();
        final packed = r.byte();
        if (!(w > 0 && h > 0 && left <= width - w && top <= height - h)) {
          throw GifIconError('GIF 帧越出逻辑画布');
        }
        final List<int> palette;
        if (packed & 128 != 0) {
          palette = r.palette(1 << ((packed & 7) + 1));
        } else {
          if (global == null) throw GifIconError('GIF 缺少调色板');
          palette = global;
        }
        if (!(transparent < palette.length)) throw GifIconError('GIF 透明色索引越界');
        final firstFrame = !initialized;
        if (!initialized) {
          initialTransparency = transparent >= 0;
          // 局部首帧: 画布在它的范围之外是调色板 0 号(而不是背景色)。
          canvas.fillRange(0, canvas.length, initialTransparency ? 0 : palette[0]);
          initialized = true;
        } else if (previousDisposal == 2) {
          for (var y = previousTop; y < previousTop + previousHeight; y++) {
            canvas.fillRange(
                y * width + previousLeft, y * width + previousLeft + previousWidth, previousClear);
          }
        } else if (previousDisposal == 3) {
          if (restore == null) throw GifIconError('GIF disposal 3 缺少还原帧');
          canvas.setAll(0, restore);
        }
        restore = disposal == 3 ? [...canvas] : null;
        final indices = _lzw(r.blocksAfterCodeSize(), w * h);
        final List<int> rows;
        if (packed & 64 == 0) {
          rows = List<int>.generate(h, (y) => y);
        } else {
          rows = [];
          for (final (start, step) in const [(0, 8), (4, 8), (2, 4), (1, 2)]) {
            for (var y = start; y < h; y += step) {
              rows.add(y);
            }
          }
        }
        var p = 0;
        for (final row in rows) {
          for (var x = 0; x < w; x++) {
            final index = indices[p++] & 255;
            if (!(index < palette.length)) throw GifIconError('GIF 像素调色板索引越界');
            if (index != transparent) {
              canvas[(top + row) * width + left + x] = palette[index];
            } else if (firstFrame) {
              canvas[(top + row) * width + left + x] = 0;
            }
          }
        }
        frames.add(Frame(IconConvert.fitCanvas(canvas, width, height, Dgf1.side), delay));
        previousDisposal = disposal;
        previousLeft = left;
        previousTop = top;
        previousWidth = w;
        previousHeight = h;
        previousClear = initialTransparency || transparent >= 0
            ? 0
            : (global != null && background < global.length ? global[background] : 0);
        transparent = -1;
        delay = 100;
      } else {
        throw GifIconError('GIF 数据块不合法：0x${_hex(tag)}');
      }
    }
    if (!(ended && frames.isNotEmpty)) throw GifIconError('GIF 被截断或没有图片帧');
    final animation = Dgf1.encode(frames, plays, bytes);
    return Made(
        LvglIconCodec.bgra(frames.first.pixels, Dgf1.side, Dgf1.side),
        animation,
        frames.length,
        frames.fold<int>(0, (n, f) => n + f.delayMs),
        plays);
  }

  /// LZW 解压。码宽从 minBits+1 起, 字典满 4096 就停止增长(不再有 clear)。
  static Uint8List _lzw(_Compressed data, int expected) {
    if (!(data.minBits >= 2 && data.minBits <= 8)) {
      throw GifIconError('GIF LZW 初始码宽不合法');
    }
    final clear = 1 << data.minBits;
    final stop = clear + 1;
    final prefix = List<int>.filled(4096, 0);
    final suffix = Uint8List(4096);
    final stack = Uint8List(4097);
    for (var i = 0; i < clear; i++) {
      suffix[i] = i;
    }
    final out = Uint8List(expected);
    var bit = 0;
    var bits = data.minBits + 1;
    var available = stop + 1;
    var old = -1;
    var first = 0;
    var written = 0;
    var ended = false;
    int code() {
      if (!(bit + bits <= data.bytes.length * 8)) throw GifIconError('GIF LZW 数据被截断');
      var value = 0;
      for (var i = 0; i < bits; i++) {
        value |= ((data.bytes[(bit + i) >> 3] >> ((bit + i) & 7)) & 1) << i;
      }
      bit += bits;
      return value;
    }

    while (!ended) {
      var current = code();
      if (current == clear) {
        bits = data.minBits + 1;
        available = stop + 1;
        old = -1;
        continue;
      }
      if (current == stop) {
        ended = true;
        continue;
      }
      if (!(current <= available && current < 4096)) throw GifIconError('GIF LZW 码字不合法');
      if (old < 0) {
        if (!(current < clear && written < expected)) {
          throw GifIconError('GIF LZW 首码或像素数不合法');
        }
        out[written++] = current;
        first = current;
        old = current;
        continue;
      }
      final input = current;
      var top = 0;
      if (current == available) {
        stack[top++] = first;
        current = old;
      }
      while (current >= clear) {
        if (!(current > stop && current < available && top < 4096)) {
          throw GifIconError('GIF LZW 字典损坏');
        }
        stack[top++] = suffix[current];
        current = prefix[current];
      }
      first = current;
      stack[top++] = first;
      if (!(top <= expected - written)) throw GifIconError('GIF LZW 像素数超过帧尺寸');
      while (top > 0) {
        out[written++] = stack[--top];
      }
      if (available < 4096) {
        prefix[available] = old;
        suffix[available] = first;
        available++;
        if (available == 1 << bits && bits < 12) bits++;
      }
      old = input;
    }
    if (written != expected) throw GifIconError('GIF LZW 解码后的像素数不符');
    return out;
  }
}

/// 转换结果: 静态封面、DGF1 动画、帧数、总时长与循环次数。
class Made {
  const Made(this.cover, this.animation, this.frameCount, this.durationMs, this.plays);

  final Uint8List cover;
  final Uint8List animation;
  final int frameCount;
  final int durationMs;
  final int plays;
}

/// 一帧的压缩数据: 初始码宽 + 码流(子块拼起来的)。
class _Compressed {
  const _Compressed(this.minBits, this.bytes);

  final int minBits;
  final Uint8List bytes;
}

/// 按子块推进的读取器, 任何越界都当作截断。
class _Reader {
  _Reader(this.bytes);

  final Uint8List bytes;
  var p = 0;

  int get remaining => bytes.length - p;

  int byte() {
    if (!(p < bytes.length)) throw GifIconError('GIF 数据被截断');
    return bytes[p++] & 255;
  }

  int word() => byte() | (byte() << 8);

  void skip(int n) {
    if (!(n >= 0 && n <= remaining)) throw GifIconError('GIF 数据被截断');
    p += n;
  }

  Uint8List take(int n) {
    if (!(n >= 0 && n <= remaining)) throw GifIconError('GIF 数据被截断');
    final out = Uint8List.sublistView(bytes, p, p + n);
    p += n;
    return out;
  }

  List<int> palette(int n) => List<int>.generate(n, (_) {
        final red = byte();
        final green = byte();
        final blue = byte();
        return 0xff000000 | (red << 16) | (green << 8) | blue;
      });

  Uint8List blocks() {
    final out = BytesBuilder(copy: true);
    while (true) {
      final n = byte();
      if (n == 0) break;
      out.add(take(n));
    }
    return out.takeBytes();
  }

  _Compressed blocksAfterCodeSize() {
    final size = byte();
    return _Compressed(size, blocks());
  }
}

String _ascii(Uint8List b, int start, int end) =>
    String.fromCharCodes(Uint8List.sublistView(b, start, end));

String _asciiFromBytes(Uint8List b) => String.fromCharCodes(b);

String _hex(int v) => v.toRadixString(16);

class GifIconError implements Exception {
  GifIconError(this.message);

  final String message;

  @override
  String toString() => 'GifIconError: $message';
}
