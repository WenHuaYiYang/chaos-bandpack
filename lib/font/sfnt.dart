import 'dart:typed_data';

import 'charset.dart';

/// sfnt(TrueType) 只读解析。只做子集化必需的那几件事：表目录、loca、cmap、
/// head/maxp/hhea/hmtx，以及复合字形的分量表。
///
/// 全程大端；越界一律当作"文件坏了"抛 [FontError]，不返回半截数据 ——
/// 子集化是"要么出一份能用的字体，要么明确失败"，不允许产出半成品。
///
/// 与 Kotlin 侧 Sfnt.kt 逐字节等价：所有偏移、掩码、截断行为都照抄
/// （Kotlin 的 Int 是 32 位有符号，这里用 [_i32] 显式模拟，避免 Dart 64 位
/// 整数把溢出悄悄"救回来"）。
class SfntTable {
  SfntTable(this.tag, this.offset, this.length, this.checksum);

  final String tag;
  final int offset;
  final int length;
  final int checksum;

  @override
  String toString() => 'SfntTable($tag, $offset, $length)';
}

/// 大端只读视图。
class Be {
  Be(this.b);

  final Uint8List b;

  int u8(int o) {
    if (o < 0 || o >= b.length) throw FontError('读越界 @$o');
    return b[o] & 0xFF;
  }

  int u16(int o) => (u8(o) << 8) | u8(o + 1);

  /// 有符号 16 位（等价 Kotlin 的 u16(o).toShort().toInt()）
  int i16(int o) => _i16(u16(o));

  int u32(int o) => (u16(o) << 16) | u16(o + 2);

  /// 等价 Kotlin 的 String(bytes, o, 4, US_ASCII)：非 ASCII 字节解成 U+FFFD
  String tag(int o) {
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < 4; i++) {
      final int v = u8(o + i);
      sb.writeCharCode(v < 0x80 ? v : 0xFFFD);
    }
    return sb.toString();
  }
}

/// 32 位有符号截断（等价 Kotlin 的 .toInt()）
int _i32(int v) {
  final int m = v & 0xFFFFFFFF;
  return m >= 0x80000000 ? m - 0x100000000 : m;
}

/// 16 位有符号截断（等价 Kotlin 的 .toShort().toInt()）
int _i16(int v) {
  final int m = v & 0xFFFF;
  return m >= 0x8000 ? m - 0x10000 : m;
}

class Sfnt {
  Sfnt(this.bytes) {
    final Be r = Be(bytes);
    if (bytes.length < 12) throw FontError('文件太短');
    final int ver = r.u32(0);
    // 0x00010000 是 TrueType, 'true'/'typ1' 也算; 'OTTO' 是 CFF 轮廓, 我们不做
    if (ver == 0x4F54544F) {
      throw FontError('这是 CFF(OTTO) 字体，本应用只做 TrueType 轮廓');
    }
    if (ver != 0x00010000 && ver != 0x74727565 && ver != 0x74797031) {
      final String hex =
          ver.toRadixString(16).toUpperCase().padLeft(8, '0');
      throw FontError('不是 TrueType 字体（魔数 0x$hex）');
    }
    final int n = r.u16(4);
    if (n <= 0 || n > 512) throw FontError('表目录条数异常: $n');
    final Map<String, SfntTable> m = <String, SfntTable>{};
    for (int i = 0; i < n; i++) {
      final int p = 12 + i * 16;
      final String tag = r.tag(p);
      final int off = _i32(r.u32(p + 8));
      final int len = _i32(r.u32(p + 12));
      if (off < 0 || len < 0 || off + len > bytes.length) {
        throw FontError('表 $tag 越界($off+$len > ${bytes.length})');
      }
      m[tag] = SfntTable(tag, off, len, r.u32(p + 4));
    }
    tables = m;
    numTables = n;
  }

  final Uint8List bytes;
  late final Map<String, SfntTable> tables;
  late final int numTables;

  SfntTable need(String tag) {
    final SfntTable? t = tables[tag];
    if (t == null) throw FontError('缺表 $tag');
    return t;
  }

  bool has(String tag) => tables.containsKey(tag);

  Uint8List slice(SfntTable t) =>
      Uint8List.sublistView(bytes, t.offset, t.offset + t.length);

  /// head 的两个字段：unitsPerEm 与 indexToLocFormat
  (int, int) headInfo() {
    final Be r = Be(slice(need('head')));
    return (r.u16(18), r.i16(50));
  }

  int numGlyphs() => Be(slice(need('maxp'))).u16(4);

  int numHMetrics() => Be(slice(need('hhea'))).u16(34);

  /// loca -> 字形数据在 glyf 表里的偏移（长度 numGlyphs+1）。
  /// indexToLocFormat: 0 表示短格式(u16, 值 ×2), 1 表示长格式(u32)。
  List<int> locaOffsets() {
    final int n = numGlyphs();
    final int fmt = headInfo().$2;
    final Be r = Be(slice(need('loca')));
    final List<int> out = List<int>.filled(n + 1, 0);
    for (int i = 0; i <= n; i++) {
      out[i] = fmt == 0 ? r.u16(i * 2) * 2 : _i32(r.u32(i * 4));
    }
    return out;
  }

  /// cmap -> 码点映射（只收 BMP，全部目标字符都在 BMP）。
  /// 优先级 (3,10) 格式 12 > (3,1) 格式 4 > (0,*) —— 与 fontTools getBestCmap 同序。
  Map<int, int> cmap() {
    final Uint8List c = slice(need('cmap'));
    final Be r = Be(c);
    final int n = r.u16(2);
    int best = -1;
    int bestRank = -1;
    for (int i = 0; i < n; i++) {
      final int p = 4 + i * 8;
      final int plat = r.u16(p);
      final int enc = r.u16(p + 2);
      final int off = _i32(r.u32(p + 4));
      if (off < 0 || off + 2 > c.length) continue;
      final int fmt = r.u16(off);
      int rank = -1;
      if (plat == 3 && enc == 10 && fmt == 12) {
        rank = 4;
      } else if (plat == 3 && enc == 1 && fmt == 4) {
        rank = 3;
      } else if (plat == 0 && fmt == 12) {
        rank = 2;
      } else if (plat == 0 && fmt == 4) {
        rank = 1;
      }
      if (rank > bestRank) {
        bestRank = rank;
        best = off;
      }
    }
    if (best < 0) throw FontError('cmap 里没有可用的 Unicode 子表');
    final int fmt = r.u16(best);
    if (fmt == 4) return _cmapFormat4(c, best);
    if (fmt == 12) return _cmapFormat12(c, best);
    throw FontError('不支持的 cmap 格式 $fmt');
  }

  Map<int, int> _cmapFormat4(Uint8List c, int o) {
    final Be r = Be(c);
    final int segX2 = r.u16(o + 6);
    final int seg = segX2 ~/ 2;
    final int endBase = o + 14;
    final int startBase = endBase + segX2 + 2;
    final int deltaBase = startBase + segX2;
    final int rangeBase = deltaBase + segX2;
    final Map<int, int> out = <int, int>{};
    for (int i = 0; i < seg; i++) {
      final int end = r.u16(endBase + i * 2);
      final int start = r.u16(startBase + i * 2);
      if (start > end || start == 0xFFFF) continue;
      final int delta = r.u16(deltaBase + i * 2);
      final int ro = r.u16(rangeBase + i * 2);
      for (int ch = start; ch <= end; ch++) {
        if (ch > 0xFFFF) break;
        final int gid;
        if (ro == 0) {
          gid = (ch + delta) & 0xFFFF;
        } else {
          // 地址 = &idRangeOffset[i] + ro + 2*(ch - start)
          final int at = rangeBase + i * 2 + ro + 2 * (ch - start);
          if (at + 1 >= c.length) continue;
          final int g = r.u16(at);
          gid = g == 0 ? 0 : (g + delta) & 0xFFFF;
        }
        if (gid != 0) out[ch] = gid;
      }
    }
    return out;
  }

  Map<int, int> _cmapFormat12(Uint8List c, int o) {
    final Be r = Be(c);
    final int groups = _i32(r.u32(o + 12));
    final Map<int, int> out = <int, int>{};
    for (int i = 0; i < groups; i++) {
      final int p = o + 16 + i * 12;
      final int start = r.u32(p);
      final int end = r.u32(p + 4);
      final int gid0 = r.u32(p + 8);
      int ch = start;
      while (ch <= end) {
        if (ch > 0xFFFF) break;
        out[ch] = gid0 + (ch - start);
        ch++;
      }
    }
    return out;
  }

  /// 字形数据（原始字节，含复合字形的分量表与指令）
  Uint8List glyph(Uint8List glyf, List<int> offsets, int gid) =>
      offsets[gid] >= offsets[gid + 1]
          ? Uint8List(0)
          : Uint8List.sublistView(glyf, offsets[gid], offsets[gid + 1]);
}

// ===== 复合字形 =====

const int arg1And2AreWords = 0x0001;
const int weHaveAScale = 0x0008;
const int moreComponents = 0x0020;
const int weHaveAnXAndYScale = 0x0040;
const int weHaveATwoByTwo = 0x0080;
const int weHaveInstructions = 0x0100;

/// 复合字形引用的分量 gid（非复合返回空表）
List<int> compositeComponents(Uint8List g) {
  if (g.length < 10) return <int>[];
  final Be r = Be(g);
  if (r.i16(0) >= 0) return <int>[];
  final List<int> out = <int>[];
  int o = 10;
  while (true) {
    if (o + 4 > g.length) throw FontError('复合字形分量表越界');
    final int flags = r.u16(o);
    out.add(r.u16(o + 2));
    o += 4;
    o += (flags & arg1And2AreWords) != 0 ? 4 : 2;
    if ((flags & weHaveAScale) != 0) {
      o += 2;
    } else if ((flags & weHaveAnXAndYScale) != 0) {
      o += 4;
    } else if ((flags & weHaveATwoByTwo) != 0) {
      o += 8;
    }
    if ((flags & moreComponents) == 0) {
      if ((flags & weHaveInstructions) != 0 && o + 2 <= g.length) {
        final int n = r.u16(o);
        o += 2 + n;
      }
      break;
    }
  }
  if (o > g.length) throw FontError('复合字形越界');
  return out;
}

/// 复合字形重写：分量表里的 glyphIndex 是**必须重编号**的字段（新字体里字序号全变了）。
/// 其余字节原样保留 —— 缩放、偏移、指令都不受影响。
Uint8List rewriteComposite(Uint8List g, int Function(int) remap) {
  if (g.length < 10) return g;
  final Be r = Be(g);
  if (r.i16(0) >= 0) return g;
  final Uint8List out = Uint8List.fromList(g);
  int o = 10;
  while (true) {
    if (o + 4 > out.length) throw FontError('复合字形分量表越界');
    final int flags = r.u16(o);
    final int gid = r.u16(o + 2);
    final int newGid = remap(gid);
    out[o + 2] = (newGid >> 8) & 0xFF;
    out[o + 3] = newGid & 0xFF;
    o += 4;
    o += (flags & arg1And2AreWords) != 0 ? 4 : 2;
    if ((flags & weHaveAScale) != 0) {
      o += 2;
    } else if ((flags & weHaveAnXAndYScale) != 0) {
      o += 4;
    } else if ((flags & weHaveATwoByTwo) != 0) {
      o += 8;
    }
    if ((flags & moreComponents) == 0) break;
  }
  return out;
}
