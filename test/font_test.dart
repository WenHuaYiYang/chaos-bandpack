import 'dart:io';
import 'dart:typed_data';

import 'package:chaos_bandpack/font/charset.dart';
import 'package:chaos_bandpack/font/font_subset.dart';
import 'package:chaos_bandpack/font/metrics.dart';
import 'package:chaos_bandpack/font/sfnt.dart';
import 'package:test/test.dart';

/// 本机候选源字体（按“能覆盖 GB2312 全量”优先排列）。
/// 测试不依赖任何单个文件：找不到就用下一个，全都找不到就跳过并 report。
const List<String> _fontCandidates = <String>[
  'C:/Users/YiYang/Downloads/LXGWWenKai-Regular.ttf',
  'C:/Users/YiYang/Documents/chaos-bandpack-flutter/assets/fonts/LXGWWenKai-Regular.ttf',
  'C:/Users/YiYang/Documents/xiaomi band 10 pro/scripts/MiSans-Regular.ttf',
  'C:/Users/YiYang/Documents/xiaomi band 10 pro/posters/assets/AlibabaPuHuiTi-2-55-Regular.ttf',
  'C:/Users/YiYang/Documents/xiaomi band 10 pro/android/app/build/font-check/lxgw-wenkai-band.ttf',
  'C:/Users/YiYang/Documents/xiaomi band 10 pro/android/app/build/intermediates/assets/debug/mergeDebugAssets/fonts/MiSans-Regular-subset.ttf',
  'C:/Windows/Fonts/simhei.ttf',
  'C:/Windows/Fonts/Deng.ttf',
];

/// Kotlin 侧真机用的产出，作为“逐字节对拍”的金标准（存在才比）。
const String _goldenPath =
    'C:/Users/YiYang/Documents/xiaomi band 10 pro/android/app/build/font-check/lxgw-wenkai-band.ttf';
const String _goldenSource = 'C:/Users/YiYang/Downloads/LXGWWenKai-Regular.ttf';

/// 一份已解析的源字体。
class _Source {
  _Source(this.path, this.bytes) : sfnt = Sfnt(bytes);

  final String path;
  final Uint8List bytes;
  final Sfnt sfnt;
  late final Map<int, int> cmap = sfnt.cmap();
  late final int gbMissing = Charset.missingRequiredCount(cmap);

  @override
  String toString() =>
      '$path (${bytes.length} 字节, ${sfnt.numGlyphs()} 字形, 缺 $gbMissing 个必需字符)';
}

_Source? _full;
_Source? _any;
bool _scanned = false;

/// 只扫一遍：[_full] 是 GB2312 全覆盖的，[_any] 是任何能解析的。
void _scan() {
  if (_scanned) return;
  _scanned = true;
  for (final String p in _fontCandidates) {
    final File f = File(p);
    if (!f.existsSync()) continue;
    _Source s;
    try {
      s = _Source(p, f.readAsBytesSync());
    } on FontError {
      continue;
    }
    _any ??= s;
    if (s.gbMissing == 0) {
      _full = s;
      break;
    }
  }
}

(_Source?, String) _need(String why) {
  _scan();
  final _Source? s = _full;
  return s == null ? (null, why) : (s, '');
}

// ===== 小工具 =====

void _put16(Uint8List b, int o, int v) {
  b[o] = (v >> 8) & 0xFF;
  b[o + 1] = v & 0xFF;
}

void _put32(Uint8List b, int o, int v) {
  b[o] = (v >> 24) & 0xFF;
  b[o + 1] = (v >> 16) & 0xFF;
  b[o + 2] = (v >> 8) & 0xFF;
  b[o + 3] = v & 0xFF;
}

void _putTag(Uint8List b, int o, String tag) {
  for (int i = 0; i < 4; i++) {
    b[o + i] = tag.codeUnitAt(i);
  }
}

/// 整文件校验和：全部 32 位大端字相加（TrueType 要求等于 0xB1B0AFBA）
int _fileChecksum(Uint8List d) {
  int sum = 0;
  for (int i = 0; i < d.length; i += 4) {
    int w = 0;
    for (int j = 0; j < 4; j++) {
      w = (w << 8) | (i + j < d.length ? d[i + j] & 0xFF : 0);
    }
    sum = (sum + w) & 0xFFFFFFFF;
  }
  return sum;
}

/// 测试日志走 stdout（不用 print，避免 lint 噪音）。
void _log(String s) => stdout.writeln(s);

String _diff(Uint8List a, Uint8List b) {
  if (a.length != b.length) return '长度不同: ${a.length} vs ${b.length}';
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return '首个差异在 $i: 0x${a[i].toRadixString(16)} vs 0x${b[i].toRadixString(16)}';
    }
  }
  return '完全相同';
}

/// 最小可解析字体：只有一张 cmap 表（用来测子表优先级与格式 4 的两个分支）。
Uint8List _fmt4Subtable() {
  final Uint8List t = Uint8List(44);
  _put16(t, 0, 4); // format
  _put16(t, 2, 44); // length
  _put16(t, 4, 0); // language
  _put16(t, 6, 6); // segCountX2 = 3 段
  _put16(t, 8, 4); // searchRange
  _put16(t, 10, 1); // entrySelector
  _put16(t, 12, 2); // rangeShift
  _put16(t, 14, 0x41); // endCode
  _put16(t, 16, 0x43);
  _put16(t, 18, 0xFFFF);
  _put16(t, 20, 0); // reservedPad
  _put16(t, 22, 0x41); // startCode
  _put16(t, 24, 0x42);
  _put16(t, 26, 0xFFFF);
  _put16(t, 28, 5 - 0x41); // idDelta: 'A' -> 5
  _put16(t, 30, 0);
  _put16(t, 32, 1);
  _put16(t, 34, 0); // idRangeOffset
  _put16(t, 36, 4); // 指向 glyphIdArray 的第一个字
  _put16(t, 38, 0);
  _put16(t, 40, 0x20); // glyphIdArray: 'B' -> 0x20, 'C' -> 0x21
  _put16(t, 42, 0x21);
  return t;
}

Uint8List _fmt12Subtable(int gidOfA) {
  final Uint8List t = Uint8List(28);
  _put16(t, 0, 12);
  _put16(t, 2, 0);
  _put32(t, 4, 28);
  _put32(t, 8, 0);
  _put32(t, 12, 1); // 1 个 group
  _put32(t, 16, 0x41);
  _put32(t, 20, 0x41);
  _put32(t, 24, gidOfA);
  return t;
}

Uint8List _cmapFixture({required bool withTwelve, required int gid12}) {
  final Uint8List f4 = _fmt4Subtable();
  final Uint8List f12 = _fmt12Subtable(gid12);
  final int n = withTwelve ? 2 : 1;
  final int headLen = 4 + n * 8;
  final int off4 = headLen;
  final int off12 = headLen + f4.length;
  final int cmapLen = headLen + f4.length + (withTwelve ? f12.length : 0);
  final Uint8List cmap = Uint8List(cmapLen);
  _put16(cmap, 0, 0);
  _put16(cmap, 2, n);
  _put16(cmap, 4, 3);
  _put16(cmap, 6, 1);
  _put32(cmap, 8, off4);
  if (withTwelve) {
    _put16(cmap, 12, 3);
    _put16(cmap, 14, 10);
    _put32(cmap, 16, off12);
  }
  cmap.setRange(off4, off4 + f4.length, f4);
  if (withTwelve) cmap.setRange(off12, off12 + f12.length, f12);

  final Uint8List font = Uint8List(28 + cmapLen);
  _put32(font, 0, 0x00010000);
  _put16(font, 4, 1); // 1 张表
  _putTag(font, 12, 'cmap');
  _put32(font, 16, 0); // checksum（解析器不校验）
  _put32(font, 20, 28);
  _put32(font, 24, cmapLen);
  font.setRange(28, font.length, cmap);
  return font;
}

void main() {
  setUpAll(() {
    _scan();
    for (final String p in _fontCandidates) {
      if (File(p).existsSync()) _log('[候选] $p');
    }
    if (_full != null) {
      _log('[源字体] $_full');
    } else {
      _log('[警告] 本机没找到覆盖 GB2312 的 .ttf，相关用例将跳过');
    }
  });

  // ===== Charset =====
  group('Charset', () {
    test('简体字集 = GB2312 全量(6763 汉字 + 682 符号)', () {
      expect(Charset.gb2312.length, 6763);
      expect(Charset.gb2312Symbols.length, 682);
      // 汉字 + ASCII 0x20..0x7E 就是打包时“一个都不能少”的硬要求
      expect(Charset.required.length, 6858);
      expect(Charset.required.length, Charset.gb2312.length + 0x5F);
      expect(Charset.big5.length, 13051);

      // GB2312 的汉字必须全在 CJK 统一汉字区，且不碰私用区
      int notCjk = 0;
      int pua = 0;
      for (final int c in Charset.gb2312) {
        if (c < 0x4E00 || c > 0x9FFF) notCjk++;
        if (c >= 0xE000 && c <= 0xF8FF) pua++;
      }
      expect(notCjk, 0);
      expect(pua, 0);
    });

    test('ASCII 0x20..0x7E 进 required 但不算汉字', () {
      for (int c = 0x20; c <= 0x7E; c++) {
        expect(Charset.required.contains(c), true, reason: 'U+$c 应在 required');
        expect(Charset.gb2312.contains(c), false, reason: 'U+$c 不是汉字');
      }
      expect(Charset.required.contains(0x1F), false);
      expect(Charset.required.contains(0x7F), false);
    });

    test('RANGES 标点段 9 段', () {
      expect(Charset.ranges.length, 9);
      expect(Charset.ranges.first, <int>[0x00A0, 0x00FF]);
      expect(Charset.ranges.last, <int>[0xFF00, 0xFFEF]);
      expect(Charset.extraSymbols.length, 1168);
      // 符号区里的 GB2312 字符大多落在 RANGES 之外（日文假名等），只收进来的那部分
      expect(Charset.gb2312Symbols.where(Charset.extraSymbols.contains).length,
          215);
    });

    test('抽样码位在/不在集合', () {
      // 在：GB2312 首尾字与常用字
      for (final int c in <int>[0x4E00, 0x4E2D, 0x554A, 0x9F99, 0x9FA0]) {
        expect(Charset.gb2312.contains(c), true,
            reason: 'U+${c.toRadixString(16)} 应在 GB2312');
      }
      // 不在：越过 GB2312 末字、Android 私用区映射、假名、未定义区
      for (final int c in <int>[
        0x9FA1,
        0x9FA5,
        0x9FFF,
        0xD7FA,
        0xE810,
        0xE814,
        0x3040,
        0xFFF0
      ]) {
        expect(Charset.gb2312.contains(c), false,
            reason: 'U+${c.toRadixString(16)} 不该在 GB2312');
        expect(Charset.required.contains(c), false);
        expect(Charset.extraSymbols.contains(c), false);
      }
      // 只在标点段里
      for (final int c in <int>[
        0x3000,
        0x3001,
        0x3002,
        0xFF01,
        0xFFE5,
        0xFF21,
        0x00A0,
        0xFFEF
      ]) {
        expect(Charset.extraSymbols.contains(c), true,
            reason: 'U+${c.toRadixString(16)} 应在标点段');
        expect(Charset.required.contains(c), false);
      }
    });

    test('繁体段: Big5 汉字与简体档互斥', () {
      // Big5 0xA440..0xC67E 与 0xC940..0xF9D5 解出来的汉字并集，与 GB2312 有 4383 个交集
      expect(Charset.big5.where(Charset.gb2312.contains).length, 4383);
      const List<int> trad = <int>[
        0x5011,
        0x70BA,
        0x570B,
        0x5B78,
        0x81FA,
        0x9F8D
      ];
      for (final int c in trad) {
        expect(Charset.big5.contains(c), true,
            reason: 'U+${c.toRadixString(16)} 应在 Big5');
        expect(Charset.gb2312.contains(c), false);
        expect(Charset.target(Kind.withTraditional).contains(c), true);
        expect(Charset.target(Kind.simplified).contains(c), false);
      }
      expect(Charset.target(Kind.simplified).length, 8026);
      expect(Charset.target(Kind.withTraditional).length, 16694);
    });

    test('missingRequired 报告缺字(升序, 受 limit 约束)', () {
      final Map<int, int> cmap = <int, int>{0x4E2D: 1, 0x41: 2};
      final List<int> miss = Charset.missingRequired(cmap, limit: 5);
      expect(miss.length, 5);
      expect(miss, equals(<int>[...miss]..sort()));
      expect(Charset.missingRequiredCount(cmap), Charset.required.length - 2);

      // 可选字只数符号区；繁体档再把 Big5 的缺口并进来（缺繁体是常态，不拒绝）
      expect(Charset.missingOptionalCount(cmap, Kind.simplified),
          Charset.extraSymbols.length);
      // '中' 同时在 Big5 里(Big5∩GB2312 = 4383 字)，'A' 不在；只有纯繁体才算新增
      expect(Charset.traditionalHits(cmap), 1);
      expect(Charset.traditionalHits(<int, int>{0x5011: 9}), 1); // 們
      expect(Charset.traditionalHits(<int, int>{0x41: 9, 0x4E2D: 0}), 1);
      final Map<int, int> withSym = <int, int>{0x4E2D: 1, 0x41: 2, 0x3000: 3};
      expect(Charset.missingOptionalCount(withSym, Kind.simplified),
          Charset.extraSymbols.where((int c) => c != 0x3000).length);
      expect(
          Charset.missingOptionalCount(withSym, Kind.withTraditional),
          Charset.extraSymbols.where((int c) => c != 0x3000).length +
              Charset.big5.where((int c) => !withSym.containsKey(c)).length);
    });
  });

  // ===== Metrics =====
  group('Metrics', () {
    Uint8List hhea(int asc, int desc, int gap) {
      final Uint8List b = Uint8List(36);
      _put16(b, 4, asc & 0xFFFF);
      _put16(b, 6, desc & 0xFFFF);
      _put16(b, 8, gap & 0xFFFF);
      return b;
    }

    Uint8List os2() {
      final Uint8List b = Uint8List(78);
      _put16(b, 62, 0xC0FF); // fsSelection 带 USE_TYPO_METRICS(0x80)
      _put16(b, 68, 880);
      _put16(b, 70, 120);
      _put16(b, 72, 0);
      _put16(b, 74, 1000);
      _put16(b, 76, 200);
      return b;
    }

    test('upm=1000 直接套系统比例', () {
      final Uint8List h = hhea(1000, -200, 0);
      final Uint8List o = os2();
      final MetricsReport r = Metrics.apply(h, o, 1000);
      expect(r.upm, 1000);
      expect(r.ratioBefore, closeTo(1.2, 1e-9));
      expect(r.ratioAfter, closeTo(1.326, 1e-9));
      expect(Be(h).i16(4), 1044);
      expect(Be(h).i16(6), -282);
      expect(Be(h).i16(8), 0);
      expect(Be(o).i16(68), 890);
      expect(Be(o).i16(70), -110);
      expect(Be(o).i16(72), 326);
      expect(Be(o).i16(74), 1044);
      expect(Be(o).i16(76), 282); // -MI_DESC
      expect(Be(o).u16(62) & 0x0080, 0); // 清掉 USE_TYPO_METRICS
      expect(Be(o).u16(62) & 0x00FF, 0x7F); // 其余位不动
    });

    test('upm=2048 按 k=2.048 缩放并四舍五入', () {
      final Uint8List h = hhea(2048, -410, 0);
      final Uint8List o = os2();
      Metrics.apply(h, o, 2048);
      expect(Be(h).i16(4), (1044 * 2.048).round());
      expect(Be(h).i16(6), (-282 * 2.048).round());
      expect(Be(h).i16(6), -578);
      expect(Be(o).i16(68), (890 * 2.048).round());
      expect(Be(o).i16(76), (282 * 2.048).round());
    });

    test('没有 OS/2(或太短)时只改 hhea', () {
      final Uint8List h = hhea(1000, -200, 0);
      final MetricsReport r = Metrics.apply(h, null, 1000);
      expect(Be(h).i16(4), 1044);
      expect(r.ratioAfter, closeTo(1.326, 1e-9));

      final Uint8List h2 = hhea(1000, -200, 0);
      final Uint8List short = Uint8List(40);
      Metrics.apply(h2, short, 1000);
      expect(Be(short).u16(0), 0); // 没被写
    });
  });

  // ===== Sfnt =====
  group('Sfnt', () {
    test('拒绝 OTTO / 太短 / 非 TrueType / 表目录异常 / 表越界', () {
      void bad(Uint8List b, String msg) {
        expect(
          () => Sfnt(b),
          throwsA(predicate<Object>(
              (Object e) => e is FontError && e.message.contains(msg),
              'FontError 含 "$msg"')),
        );
      }

      bad(Uint8List(8), '文件太短');
      bad(_cmapFixture(withTwelve: false, gid12: 1).sublist(0, 0), '文件太短');

      Uint8List header(int ver, int n) {
        final Uint8List b = Uint8List(12);
        _put32(b, 0, ver);
        _put16(b, 4, n);
        return b;
      }

      bad(header(0x4F54544F, 1), 'CFF(OTTO)');
      bad(header(0x74746366, 1), '不是 TrueType 字体（魔数 0x74746366）');
      bad(header(0x00010000, 0), '表目录条数异常: 0');
      bad(header(0x00010000, 513), '表目录条数异常: 513');

      final Uint8List over = Uint8List(28);
      _put32(over, 0, 0x00010000);
      _put16(over, 4, 1);
      _putTag(over, 12, 'glyf');
      _put32(over, 20, 0x1000); // offset 远超文件长度
      _put32(over, 24, 0x100);
      bad(over, '表 glyf 越界');
    });

    test('cmap 优先级 (3,10)格式12 > (3,1)格式4，格式4 的 idRangeOffset 分支正确', () {
      // 只有 (3,1) 格式 4：A -> 5（idDelta），B/C -> glyphIdArray（idRangeOffset）
      final Map<int, int> four =
          Sfnt(_cmapFixture(withTwelve: false, gid12: 0)).cmap();
      expect(four[0x41], 5);
      expect(four[0x42], 0x20);
      expect(four[0x43], 0x21);
      expect(four.containsKey(0xFFFF), false); // 收尾段必须被跳过

      // 加上 (3,10) 格式 12 后必须改用后者（A -> 7，B/C 不再存在）
      final Map<int, int> twelve =
          Sfnt(_cmapFixture(withTwelve: true, gid12: 7)).cmap();
      expect(twelve[0x41], 7);
      expect(twelve.containsKey(0x42), false);
    });

    test('解析本机 ttf: 表目录/head/maxp/loca/glyf 自洽', () {
      final (_Source?, String) got = _need('本机没有可用的 .ttf 源字体');
      final _Source? s = got.$1;
      if (s == null) {
        markTestSkipped(got.$2);
        return;
      }
      expect(s.sfnt.numTables, greaterThan(0));
      expect(s.sfnt.numTables, s.sfnt.tables.length);
      expect(s.sfnt.has('head'), true);
      expect(s.sfnt.has('glyf'), true);

      final (int upm, int locFmt) = s.sfnt.headInfo();
      expect(upm, inInclusiveRange(16, 16384));
      expect(locFmt == 0 || locFmt == 1, true);

      final int n = s.sfnt.numGlyphs();
      expect(n, greaterThan(1000));
      final List<int> loca = s.sfnt.locaOffsets();
      expect(loca.length, n + 1);
      int backwards = 0;
      for (int i = 0; i < n; i++) {
        if (loca[i + 1] < loca[i]) backwards++;
      }
      expect(backwards, 0);
      expect(loca.last, s.sfnt.need('glyf').length);

      // cmap 里每个 gid 都得在 [1, numGlyphs)
      int bad = 0;
      s.cmap.forEach((int cp, int gid) {
        if (gid < 1 || gid >= n) bad++;
      });
      expect(bad, 0);
      expect(s.cmap.length, greaterThan(1000));
      expect(s.gbMissing, 0, reason: '源字体 $s 必须覆盖 GB2312');
    });

    test('复合字形分量可解析且可重编号', () {
      final (_Source?, String) got = _need('本机没有可用的 .ttf 源字体');
      final _Source? s = got.$1;
      if (s == null) {
        markTestSkipped(got.$2);
        return;
      }
      final Uint8List glyf = s.sfnt.slice(s.sfnt.need('glyf'));
      final List<int> loca = s.sfnt.locaOffsets();
      final int n = s.sfnt.numGlyphs();
      int composites = 0;
      int badComp = 0;
      int rewritten = 0;
      for (int g = 0; g < n; g++) {
        final Uint8List data = s.sfnt.glyph(glyf, loca, g);
        if (data.isEmpty || data[0] < 0x80) continue;
        composites++;
        final List<int> comps = compositeComponents(data);
        for (final int c in comps) {
          if (c < 0 || c >= n) badComp++;
        }
        // 重编号：gid -> gid+1，读回来必须每个分量都 +1
        final Uint8List out = rewriteComposite(data, (int x) => x + 1);
        final List<int> after = compositeComponents(out);
        if (after.length != comps.length) {
          badComp++;
          continue;
        }
        for (int i = 0; i < comps.length; i++) {
          if (after[i] != comps[i] + 1) badComp++;
        }
        if (out.length != data.length) badComp++;
        rewritten++;
      }
      _log('复合字形 $composites 个，重写 $rewritten 个');
      expect(badComp, 0);
    });
  });

  // ===== FontSubset =====
  group('FontSubset', () {
    test('子集化到 100 个汉字: 可回读、覆盖 100 字、体积显著变小', () {
      final (_Source?, String) got = _need('本机没有可用的 .ttf 源字体');
      final _Source? s = got.$1;
      if (s == null) {
        markTestSkipped(got.$2);
        return;
      }
      final List<int> pool = Charset.gb2312.toList()..sort();
      final List<int> pick = <int>[];
      for (final int c in pool) {
        if (pick.length >= 100) break;
        if (s.cmap.containsKey(c)) pick.add(c);
      }
      expect(pick.length, 100);

      final (Uint8List out, Report rep) =
          FontSubset.subsetChars(s.bytes, pick.toSet());
      _log('100 字子集: ${s.bytes.length} -> ${out.length} 字节, '
          '字形 ${rep.srcGlyphs} -> ${rep.outGlyphs}, cmap ${rep.cmapChars} 字');

      // 体积：只剩百分之一量级
      expect(out.length, lessThan(s.bytes.length ~/ 10));
      expect(out.length, lessThan(200000));
      expect(rep.outGlyphs, lessThan(rep.srcGlyphs));
      expect(rep.charset, Kind.simplified);

      // 能被 Sfnt 重新解析
      final Sfnt f = Sfnt(out);
      final Map<int, int> cm = f.cmap();
      final int n = f.numGlyphs();
      expect(cm.length, 100);
      expect(rep.cmapChars, 100);
      expect(n, greaterThanOrEqualTo(101)); // .notdef + 100 个字
      int covered = 0;
      for (final int c in pick) {
        final int g = cm[c] ?? 0;
        if (g >= 1 && g < n) covered++;
      }
      expect(covered, 100);
      // 没有字符落到 .notdef
      int toNotdef = 0;
      cm.forEach((int cp, int gid) {
        if (gid == 0) toNotdef++;
      });
      expect(toNotdef, 0);

      // 表：该留的都在，该丢的都丢了
      for (final String t in <String>[
        'head',
        'hhea',
        'maxp',
        'hmtx',
        'loca',
        'glyf',
        'cmap',
        'post',
        'name',
        'OS/2'
      ]) {
        expect(f.has(t), true, reason: '缺表 $t');
      }
      expect(f.has('GSUB'), false);
      expect(f.has('GPOS'), false);
      expect(f.has('GDEF'), false);
      expect(f.has('vhea'), false);
      expect(f.has('vmtx'), false);

      // loca 与 glyf 自洽
      final List<int> loca = f.locaOffsets();
      expect(loca.length, n + 1);
      expect(loca.last, f.need('glyf').length);
      for (int i = 0; i < n; i++) {
        expect(loca[i + 1] >= loca[i], true);
      }
      expect(loca.last % 4, 0); // 每个字形都补到 4 字节

      // hmtx = 每个字形一条长记录；hhea.numberOfHMetrics 与之对齐
      expect(f.numHMetrics(), n);
      expect(f.need('hmtx').length, 4 * n);
      expect(Be(f.slice(f.need('post'))).u32(0), 0x00030000);

      // 每张表 4 字节对齐，整文件校验和 = 0xB1B0AFBA
      for (final SfntTable t in f.tables.values) {
        expect(t.offset % 4, 0, reason: '表 ${t.tag} 未对齐');
      }
      expect(_fileChecksum(out), 0xB1B0AFBA);

      // 复合字形的分量 gid 都必须落在新字体范围内
      final Uint8List glyf = f.slice(f.need('glyf'));
      final List<int> loca2 = f.locaOffsets();
      int badComp = 0;
      for (int g = 0; g < n; g++) {
        for (final int c in compositeComponents(f.glyph(glyf, loca2, g))) {
          if (c < 0 || c >= n) badComp++;
        }
      }
      expect(badComp, 0);
    });

    test('GB2312 全量子集化: 6858 个必需字符 100% 覆盖', () {
      final (_Source?, String) got = _need('本机没有可用的 .ttf 源字体');
      final _Source? s = got.$1;
      if (s == null) {
        markTestSkipped(got.$2);
        return;
      }
      final (Uint8List out, Report rep) = FontSubset.subset(s.bytes);
      _log('全量子集: ${s.bytes.length} -> ${out.length} 字节, '
          '字形 ${rep.srcGlyphs} -> ${rep.outGlyphs}, cmap ${rep.cmapChars} 字, '
          '缺可选 ${rep.skippedOptional} 个');

      expect(rep.charset, Kind.simplified);
      expect(rep.outGlyphs, lessThan(rep.srcGlyphs));
      expect(rep.gbTotal, 6763);
      expect(rep.metrics, isNotNull);
      expect(rep.notes.any((String n) => n.contains('GSUB/GPOS/GDEF')), true);
      expect(rep.keptTables.contains('glyf'), true);

      final Sfnt f = Sfnt(out);
      final Map<int, int> cm = f.cmap();
      final int n = f.numGlyphs();
      expect(cm.length, greaterThanOrEqualTo(Charset.required.length));
      int missing = 0;
      for (final int c in Charset.required) {
        final int g = cm[c] ?? 0;
        if (!(g >= 1 && g < n)) missing++;
      }
      expect(missing, 0);
      expect(rep.cmapChars, cm.length);
      expect(rep.outBytes, out.length);
      expect(_fileChecksum(out), 0xB1B0AFBA);
    });

    test('与 Kotlin 产出逐字节一致(有金标准时)', () {
      final (_Source?, String) got = _need('本机没有可用的 .ttf 源字体');
      final _Source? s = got.$1;
      if (s == null) {
        markTestSkipped(got.$2);
        return;
      }
      if (s.path != _goldenSource || !File(_goldenPath).existsSync()) {
        markTestSkipped('本机没有 Kotlin 侧金标准($_goldenPath) 或源字体不是 $_goldenSource');
        return;
      }
      final Uint8List golden = File(_goldenPath).readAsBytesSync();
      final (Uint8List out, Report rep) = FontSubset.subset(s.bytes);
      _log('金标准对拍: Dart ${out.length} 字节 vs Kotlin ${golden.length} 字节 -> '
          '${_diff(out, golden)}');
      expect(_diff(out, golden), '完全相同');
      expect(rep.skippedOptional, 389);
      expect(rep.outGlyphs, 7636);
      expect(rep.cmapChars, 7644);
      expect(rep.droppedTables,
          containsAll(<String>['GPOS', 'GSUB', 'vhea', 'vmtx']));
    });

    test('源字体缺必需字符时抛 MissingCharsError', () {
      final (_Source?, String) got = _need('本机没有可用的 .ttf 源字体');
      final _Source? s = got.$1;
      if (s == null) {
        markTestSkipped(got.$2);
        return;
      }
      // 拿上一步的 100 字小子集当“残缺字体”：它必然缺绝大多数 GB2312 字
      final List<int> pick = (Charset.gb2312.toList()..sort())
          .where(s.cmap.containsKey)
          .take(100)
          .toList();
      final (Uint8List small, Report _) =
          FontSubset.subsetChars(s.bytes, pick.toSet());
      expect(
        () => FontSubset.subset(small),
        throwsA(predicate<Object>(
            (Object e) => e is MissingCharsError && e.count > 5000,
            'MissingCharsError 且缺字数量 > 5000')),
      );
      try {
        FontSubset.subset(small);
      } on MissingCharsError catch (e) {
        expect(e.message, startsWith('源字体缺 '));
        expect(e.message, contains('个必需字符（汉字/ASCII），例如 '));
        expect(e.sample.length, 12);
        expect(e.readable, contains('(U+'));
      }
    });

    test('subsetChars 缺字时也报错', () {
      final (_Source?, String) got = _need('本机没有可用的 .ttf 源字体');
      final _Source? s = got.$1;
      if (s == null) {
        markTestSkipped(got.$2);
        return;
      }
      // U+E000 是私用区，任何正文字体都不该有
      expect(
        () => FontSubset.subsetChars(s.bytes, <int>{0xE000}),
        throwsA(isA<MissingCharsError>()),
      );
    });
  });
}
