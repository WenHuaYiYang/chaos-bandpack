import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// p67 的 DGF1 动画 ABI。解析时会逐帧校验, 连解压后的长度也要对上。
///
/// 文件布局(小端):
///
/// ```
/// 0x00  'DGF1'          0x04 u16 宽 96     0x06 u16 高 96
/// 0x08  u16 帧数(1..256) 0x0A u16 保留 0    0x0C u32 总时长 ms
/// 0x10  u32 循环次数     0x14 u32 帧表偏移   0x18 u32 负载偏移
/// 0x1C  32 字节源文件 SHA-256
/// 0x3C  256 项 BGRA 调色板(1024 字节)
/// 0x43C 帧表: 每帧 12 字节 (u32 时长, u32 偏移, u32 长度)
///       负载: 每帧一段 15/7 位 RLE, 解压后恰好 9216 字节索引
/// ```
class Dgf1 {
  /// 画布边长。
  static const int side = 96;

  /// 一帧的像素数。
  static const int pixels = side * side;

  /// 固定头长度(含 32 字节 SHA-256)。
  static const int headerBytes = 60;

  /// 帧表起点 = 固定头 + 1024 字节调色板。
  static const int tableOffset = headerBytes + 1024;

  /// 帧数上限。
  static const int maxFrames = 256;

  /// 整个文件的上限。
  static const int maxBytes = 1024 * 1024;

  /// 单帧压缩数据的长度上限。
  static const int maxEncodedFrame = 18432;

  /// 是不是 DGF1 文件(只看前 4 字节魔数)。
  static bool isAnimation(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x44 && // D
      bytes[1] == 0x47 && // G
      bytes[2] == 0x46 && // F
      bytes[3] == 0x31; // 1

  /// 解析动画。帧表、每帧解压长度、总时长与文件尾部全部要对上, 否则直接抛错。
  static Animation parse(Uint8List bytes) {
    if (!(bytes.length >= tableOffset + 12 + 1 &&
        bytes.length <= maxBytes &&
        isAnimation(bytes))) {
      throw Dgf1Error('不是有效的 DGF1 动画，或动画超过 1 MiB');
    }
    if (!(u16(bytes, 4) == side && u16(bytes, 6) == side)) {
      throw Dgf1Error('DGF1 动画必须为 96 × 96');
    }
    final count = u16(bytes, 8);
    if (!(count >= 1 && count <= maxFrames && u16(bytes, 10) == 0)) {
      throw Dgf1Error('DGF1 帧数或保留字段不合法');
    }
    final dataOffset = tableOffset + count * 12;
    if (!(u32(bytes, 20) == tableOffset &&
        u32(bytes, 24) == dataOffset &&
        dataOffset < bytes.length)) {
      throw Dgf1Error('DGF1 帧表或负载偏移不合法');
    }
    var next = dataOffset;
    var duration = 0;
    final records = <Record>[];
    for (var i = 0; i < count; i++) {
      final at = tableOffset + i * 12;
      final delay = u32(bytes, at);
      final offset = u32(bytes, at + 4);
      final length = u32(bytes, at + 8);
      if (!(delay >= 1 &&
          delay <= 60000 &&
          offset == next &&
          length >= 1 &&
          length <= maxEncodedFrame &&
          length <= bytes.length - next)) {
        throw Dgf1Error('DGF1 第 ${i + 1} 帧的时长、偏移或长度不合法');
      }
      unpack(bytes, next, length);
      records.add(Record(delay, next, length));
      next += length;
      duration += delay;
    }
    if (!(next == bytes.length && u32(bytes, 12) == duration)) {
      throw Dgf1Error('DGF1 总时长或文件尾部不合法');
    }
    final palette = List<int>.generate(256, (i) {
      final p = headerBytes + i * 4;
      return ((bytes[p + 3] & 255) << 24) |
          ((bytes[p + 2] & 255) << 16) |
          ((bytes[p + 1] & 255) << 8) |
          (bytes[p] & 255);
    });
    return Animation(bytes, records, duration, u32(bytes, 16),
        Uint8List.sublistView(bytes, 28, 60), palette);
  }

  /// 编码动画。会先解码校验一遍再返回, 出错不会产出半成品。
  static Uint8List encode(List<Frame> frames, int plays, Uint8List source) {
    if (frames.isEmpty || frames.length > maxFrames) {
      throw Dgf1Error('GIF 必须有 1–256 帧；不会自动抽帧');
    }
    if (!(plays >= 0 && plays <= 0xFFFFFFFF)) {
      throw Dgf1Error('循环次数必须为 0–4294967295');
    }
    for (var i = 0; i < frames.length; i++) {
      final f = frames[i];
      if (!(f.pixels.length == pixels && f.delayMs >= 1 && f.delayMs <= 60000)) {
        throw Dgf1Error('第 ${i + 1} 帧必须为 96 × 96，时长须为 1–60000 ms');
      }
    }
    final indexed = _quantize(frames);
    final compressed = <Uint8List>[];
    for (final frame in indexed.frames) {
      final data = pack(frame);
      if (data.length > maxEncodedFrame) {
        throw Dgf1Error('第 ${compressed.length + 1} 帧压缩后超过 18432 字节');
      }
      compressed.add(data);
    }
    final dataAt = tableOffset + frames.length * 12;
    var size = dataAt;
    for (final c in compressed) {
      size += c.length;
    }
    if (size > maxBytes) {
      throw Dgf1Error('GIF 转换后超过 1 MiB；请减少帧数或画面复杂度，不会自动抽帧或降低分辨率');
    }
    final out = Uint8List(size);
    out.setRange(0, 4, const [0x44, 0x47, 0x46, 0x31]); // 'DGF1'
    w16(out, 4, side);
    w16(out, 6, side);
    w16(out, 8, frames.length);
    w32(out, 12, frames.fold<int>(0, (n, f) => n + f.delayMs));
    w32(out, 16, plays);
    w32(out, 20, tableOffset);
    w32(out, 24, dataAt);
    out.setRange(28, 60, sha256.convert(source).bytes);
    for (var i = 0; i < indexed.palette.length; i++) {
      final c = indexed.palette[i];
      final p = headerBytes + i * 4;
      out[p] = c & 0xFF;
      out[p + 1] = (c >> 8) & 0xFF;
      out[p + 2] = (c >> 16) & 0xFF;
      out[p + 3] = (c >> 24) & 0xFF;
    }
    var next = dataAt;
    for (var i = 0; i < frames.length; i++) {
      final p = tableOffset + i * 12;
      w32(out, p, frames[i].delayMs);
      w32(out, p + 4, next);
      w32(out, p + 8, compressed[i].length);
      out.setRange(next, next + compressed[i].length, compressed[i]);
      next += compressed[i].length;
    }
    parse(out);
    return out;
  }

  /// 解一段 RLE: 控制字节 bit7 = 1 -> 重复 (c & 0x7F) + 1 次; 否则字面拷贝同样多字节。
  static Uint8List unpack(Uint8List bytes, int offset, int length) {
    if (!(offset >= 0 && length >= 1 && offset <= bytes.length - length)) {
      throw Dgf1Error('动画压缩数据越界');
    }
    final out = Uint8List(pixels);
    var p = offset;
    final end = offset + length;
    var n = 0;
    while (p < end) {
      final tag = bytes[p++] & 255;
      final count = (tag & 127) + 1;
      if (!(count <= pixels - n)) {
        throw Dgf1Error('动画帧解压后超过 9216 字节');
      }
      if (tag & 128 != 0) {
        if (!(p < end)) throw Dgf1Error('动画重复段被截断');
        out.fillRange(n, n + count, bytes[p++]);
      } else {
        if (!(count <= end - p)) throw Dgf1Error('动画字面段被截断');
        out.setRange(n, n + count, bytes, p);
        p += count;
      }
      n += count;
    }
    if (n != pixels) throw Dgf1Error('动画帧解压后必须恰好为 9216 字节');
    return out;
  }

  /// 压一段索引数据。连续 3 个以上相同字节才值得编码成重复段。
  static Uint8List pack(Uint8List bytes) {
    final out = BytesBuilder(copy: true);
    var p = 0;
    int run(int at) {
      var end = at + 1;
      while (end < bytes.length && end - at < 128 && bytes[end] == bytes[at]) {
        end++;
      }
      return end - at;
    }

    while (p < bytes.length) {
      final repeat = run(p);
      if (repeat >= 3) {
        out.addByte(128 | (repeat - 1));
        out.addByte(bytes[p]);
        p += repeat;
      } else {
        final start = p;
        p += repeat;
        while (p < bytes.length && p - start < 128 && run(p) < 3) {
          final r = run(p);
          final room = 128 - (p - start);
          p += r < room ? r : room;
        }
        out.addByte(p - start - 1);
        out.add(Uint8List.sublistView(bytes, start, p));
      }
    }
    return out.takeBytes();
  }

  /// 一帧: ARGB 像素 + 显示时长(ms)。
  static Frame frame(List<int> pixels, int delayMs) => Frame(pixels, delayMs);

  /// 整个动画只用一份调色板; 颜色不超过 256 种时直接用原色。
  static _Indexed _quantize(List<Frame> frames) {
    final unique = <int>{};
    var tooMany = false;
    for (final frame in frames) {
      for (final pixel in frame.pixels) {
        unique.add(_color(pixel));
        if (unique.length > 256) {
          tooMany = true;
          break;
        }
      }
      if (tooMany) break;
    }
    if (unique.length <= 256) {
      final colors = unique.toList();
      final lookup = <int, int>{};
      for (var i = 0; i < colors.length; i++) {
        lookup[colors[i]] = i;
      }
      return _Indexed(
          colors,
          [
            for (final f in frames)
              Uint8List(pixels)
                ..setAll(0, [for (var i = 0; i < pixels; i++) lookup[_color(f.pixels[i])]!])
          ]);
    }
    final counts = List<int>.filled(65536, 0);
    final sums = List<List<int>>.generate(4, (_) => List<int>.filled(65536, 0));
    var transparent = false;
    for (final f in frames) {
      for (final raw in f.pixels) {
        final c = _color(raw);
        if (c == 0) {
          transparent = true;
          continue;
        }
        final key = _bucket(c);
        counts[key]++;
        for (var k = 0; k < 4; k++) {
          sums[k][key] += _channel(c, k);
        }
      }
    }
    final histogram = <_ColorCount>[];
    for (var key = 0; key < counts.length; key++) {
      if (counts[key] <= 0) continue;
      var c = 0;
      for (var k = 0; k < 4; k++) {
        c |= (sums[k][key] ~/ counts[key]) << (k * 8);
      }
      histogram.add(_ColorCount(c, counts[key]));
    }
    final boxes = <List<_ColorCount>>[histogram];
    final target = transparent ? 255 : 256;
    int range(List<_ColorCount> box, int k) =>
        box.map((c) => _channel(c.color, k)).reduce(_max) -
        box.map((c) => _channel(c.color, k)).reduce(_min);
    while (boxes.length < target) {
      var at = -1;
      var best = -1;
      for (var i = 0; i < boxes.length; i++) {
        final box = boxes[i];
        if (box.length <= 1) continue;
        var widest = 0;
        for (var k = 0; k < 4; k++) {
          final v = range(box, k) * (k == 3 ? 2 : 1);
          if (v > widest) widest = v;
        }
        final score = widest * box.fold<int>(0, (n, c) => n + c.count);
        if (score > best) {
          best = score;
          at = i;
        }
      }
      if (at < 0) break;
      final box = boxes.removeAt(at);
      var axis = 0;
      var widestAxis = -1;
      for (var k = 0; k < 4; k++) {
        final v = range(box, k) * (k == 3 ? 2 : 1);
        if (v > widestAxis) {
          widestAxis = v;
          axis = k;
        }
      }
      final sorted = [...box]..sort((a, b) {
          final c = _channel(a.color, axis).compareTo(_channel(b.color, axis));
          return c != 0 ? c : _signedCompare(a.color, b.color);
        });
      final half = sorted.fold<int>(0, (n, c) => n + c.count) ~/ 2;
      var total = 0;
      var cut = 0;
      while (cut < sorted.length - 1 && (cut == 0 || total < half)) {
        total += sorted[cut++].count;
      }
      boxes.add(sorted.sublist(0, cut));
      boxes.add(sorted.sublist(cut));
    }
    final palette = <int>[];
    if (transparent) palette.add(0);
    for (final box in boxes) {
      final n = box.fold<int>(0, (a, c) => a + c.count);
      var c = 0;
      for (var k = 0; k < 4; k++) {
        final sum = box.fold<int>(0, (a, x) => a + _channel(x.color, k) * x.count);
        c |= (sum ~/ n) << (k * 8);
      }
      palette.add(c);
    }
    final lookup = List<int>.filled(65536, -1);
    if (transparent) lookup[0] = 0;
    int index(int c) {
      final key = _bucket(c);
      if (lookup[key] < 0) {
        var representative = 0;
        for (var k = 0; k < 4; k++) {
          representative |= (sums[k][key] ~/ counts[key]) << (k * 8);
        }
        var bestIndex = 0;
        var bestError = -1;
        for (var i = 0; i < palette.length; i++) {
          var error = 0;
          for (var k = 0; k < 4; k++) {
            final d = _channel(representative, k) - _channel(palette[i], k);
            error += d * d * (k == 3 ? 4 : 1);
          }
          if (bestError < 0 || error < bestError) {
            bestError = error;
            bestIndex = i;
          }
        }
        lookup[key] = bestIndex;
      }
      return lookup[key];
    }

    return _Indexed(
        palette,
        [
          for (final f in frames)
            Uint8List(pixels)
              ..setAll(0, [for (var i = 0; i < pixels; i++) index(_color(f.pixels[i]))])
        ]);
  }

  /// 小端 u16。
  static int u16(Uint8List b, int p) => (b[p] & 255) | ((b[p + 1] & 255) << 8);

  /// 小端 u32(按无符号解释)。
  static int u32(Uint8List b, int p) =>
      (b[p] & 255) |
      ((b[p + 1] & 255) << 8) |
      ((b[p + 2] & 255) << 16) |
      ((b[p + 3] & 255) << 24);

  /// 小端写 u16(超出 16 位按 Kotlin 的 toShort 截断)。
  static void w16(Uint8List b, int p, int n) {
    b[p] = n & 255;
    b[p + 1] = (n >> 8) & 255;
  }

  /// 小端写 u32(超出 32 位截断)。
  static void w32(Uint8List b, int p, int n) {
    for (var i = 0; i < 4; i++) {
      b[p + i] = (n >> (i * 8)) & 255;
    }
  }
}

/// 一帧动画: ARGB 像素 + 显示时长(ms)。
class Frame {
  const Frame(this.pixels, this.delayMs);

  final List<int> pixels;
  final int delayMs;
}

/// 帧表里的一项: 时长、负载偏移与压缩长度。
class Record {
  const Record(this.delayMs, this.offset, this.length);

  final int delayMs;
  final int offset;
  final int length;
}

/// 解析好的动画。帧数据只有索引, 取像素时再查调色板。
class Animation {
  Animation(this.bytes, this.frames, this.durationMs, this.plays, this.sourceHash,
      this._palette);

  /// 原始文件字节(导出时原样带走)。
  final Uint8List bytes;

  /// 帧表。
  final List<Record> frames;

  /// 总时长(ms)。
  final int durationMs;

  /// 循环次数, 0 = 无限循环。
  final int plays;

  /// 生成这份动画的源文件 SHA-256。
  final Uint8List sourceHash;

  final List<int> _palette;

  /// 取第 [frame] 帧的 ARGB 像素(9216 个)。
  List<int> pixels(int frame) {
    final indices = Dgf1.unpack(bytes, frames[frame].offset, frames[frame].length);
    return List<int>.generate(Dgf1.pixels, (i) => _palette[indices[i] & 255]);
  }
}

/// 量化结果: 整段动画共用一份调色板, 每帧只剩索引。
class _Indexed {
  const _Indexed(this.palette, this.frames);

  final List<int> palette;
  final List<Uint8List> frames;
}

/// 一个颜色在直方图里的出现次数。
class _ColorCount {
  const _ColorCount(this.color, this.count);

  final int color;
  final int count;
}

/// Kotlin Int 有符号, 排序时按同一规则比较, 保证调色板顺序逐字节一致。
int _signedCompare(int a, int b) => (a ^ 0x80000000).compareTo(b ^ 0x80000000);

/// 全透明的像素统一折成 0, 其它原样返回。
int _color(int c) => (c >> 24) & 255 == 0 ? 0 : c;

/// 每个通道取高 4 位, 合成 16 位直方图桶号。
int _bucket(int c) =>
    (((c >> 28) & 15) << 12) |
    (((c >> 20) & 15) << 8) |
    (((c >> 12) & 15) << 4) |
    ((c >> 4) & 15);

int _channel(int c, int k) => (c >> (k * 8)) & 255;

int _max(int a, int b) => a > b ? a : b;

int _min(int a, int b) => a < b ? a : b;

class Dgf1Error implements Exception {
  Dgf1Error(this.message);

  final String message;

  @override
  String toString() => 'Dgf1Error: $message';
}
