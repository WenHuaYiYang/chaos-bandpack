import 'dart:collection';
import 'dart:typed_data';

import 'charset.dart';
import 'metrics.dart';
import 'sfnt.dart';

/// 字体子集化（纯 Dart，不依赖 fontTools）。
///
/// 口径与 Kotlin 侧 FontSubset.kt 完全一致：字形集合取全 GB2312 + ASCII 可打印
/// + CJK 标点区，产出后**回读校验 GB2312 覆盖率必须 100%**。
///
/// 与 PC 侧（scripts/build_font_subset.py）的差异只有一处，是刻意的：**丢弃排版表**
/// （GSUB/GPOS/GDEF 与 AAT 那套）。理由：手环端渲染的是界面文字，排版表带来的连字/
/// 字距对手环界面没有意义，却要按新字序号逐条重写闭包 —— 那正是最容易出错、
/// 最难验证的部分。丢掉的表会在报告里逐个列出来，不藏着。
///
/// 这是要部署到真机的二进制：下面每一处表重写都必须与 Kotlin 逐字节相同。
class FontSubset {
  FontSubset._();

  /// 原样搬运的表（都不含字序号引用）
  static const List<String> copyTables = <String>[
    'name',
    'OS/2',
    'cvt ',
    'fpgm',
    'prep',
    'gasp',
  ];

  /// 源字体缺硬要求字符（汉字或 ASCII），交不出可用字体。
  /// [readable] 是可直接显示给用户的样例，[sample] 给日志。
  static MissingCharsError checkMissing(Map<int, int> cmap) {
    final int missN = Charset.missingRequiredCount(cmap);
    if (missN > 0) {
      final List<int> sample = Charset.missingRequired(cmap);
      throw MissingCharsError(missN, sample, _renderSample(sample));
    }
    return MissingCharsError(0, const <int>[], '');
  }

  /// 子集化。[src] 是源字体字节，返回 (产出字节, 报告)。
  static (Uint8List, Report) subset(
    Uint8List src, {
    Options options = const Options(),
  }) {
    final Sfnt sfnt = Sfnt(src);
    final Map<int, int> cmap = sfnt.cmap();

    final int missN = Charset.missingRequiredCount(cmap);
    if (missN > 0) {
      final List<int> sample = Charset.missingRequired(cmap);
      throw MissingCharsError(missN, sample, _renderSample(sample));
    }
    return _subset(sfnt, cmap, Charset.target(options.charset), options);
  }

  /// 只保留 [chars] 这些字符（Dart 侧新增的入口，Kotlin 侧只有全量档）。
  ///
  /// 用途：预览/测试里做小规模子集化。走的是与 [subset] 完全相同的搬运与重写逻辑，
  /// 只有目标字符集由调用方给定 —— [subset] 本身就是它取
  /// chars = Charset.target(kind) 的特例，两侧产出的字节规则一致。
  static (Uint8List, Report) subsetChars(
    Uint8List src,
    Set<int> chars, {
    Options options = const Options(),
  }) {
    final Sfnt sfnt = Sfnt(src);
    final Map<int, int> cmap = sfnt.cmap();
    final List<int> missing =
        chars.where((int c) => !cmap.containsKey(c)).toList()..sort();
    if (missing.isNotEmpty) {
      final List<int> sample =
          missing.length > 12 ? missing.sublist(0, 12) : missing;
      throw MissingCharsError(missing.length, sample, _renderSample(sample));
    }
    return _subset(sfnt, cmap, chars, options);
  }

  /// 子集化主体：目标字符集已定，且已验证源字体覆盖它们。
  static (Uint8List, Report) _subset(
    Sfnt sfnt,
    Map<int, int> cmap,
    Set<int> chars,
    Options options,
  ) {
    final int missOptional =
        Charset.missingOptionalCount(cmap, options.charset);

    final int numGlyphs = sfnt.numGlyphs();
    final List<int> locaO = sfnt.locaOffsets();
    final Uint8List glyf = sfnt.slice(sfnt.need('glyf'));

    // 1. 保留集: gid0(.notdef) + 目标字符 + 复合字形的分量(传递闭包)
    final SplayTreeSet<int> keep = SplayTreeSet<int>()..add(0);
    for (final int c in chars) {
      final int? g = cmap[c];
      if (g == null) continue;
      if (g >= 0 && g < numGlyphs) keep.add(g);
    }
    final Queue<int> queue = ListQueue<int>.of(keep);
    while (queue.isNotEmpty) {
      final int gid = queue.removeFirst();
      for (final int comp in compositeComponents(sfnt.glyph(glyf, locaO, gid))) {
        if (comp >= 0 && comp < numGlyphs && keep.add(comp)) queue.add(comp);
      }
    }
    // 排序: .notdef 固定在 0 号(缺字时渲染器回落的那个字形, 规范要求)。
    // 其余的有码点按最小码点升序, 只被复合字形引用的(无码点)排到最后 ——
    // 这样"码点连续且原 gid 连续"的区段在新字体里仍是连续 gid, cmap 段数最少,
    // 段内只用 idDelta, 也不必担心格式 4 的 64KB 长度上限。
    final Map<int, int> firstCp = <int, int>{};
    cmap.forEach((int c, int g) {
      if (!keep.contains(g)) return;
      final int? p = firstCp[g];
      if (p == null || c < p) firstCp[g] = c;
    });
    final List<int> rest = keep.where((int g) => g != 0).toList()
      ..sort((int a, int b) {
        final int pa = firstCp[a] ?? 0x7FFFFFFF;
        final int pb = firstCp[b] ?? 0x7FFFFFFF;
        if (pa != pb) return pa.compareTo(pb);
        return a.compareTo(b);
      });
    final List<int> list = <int>[0, ...rest];
    final List<int> remap = List<int>.filled(numGlyphs, -1);
    for (int i = 0; i < list.length; i++) {
      remap[list[i]] = i;
    }

    // 2. glyf + loca: 逐字形搬运(复合字形只重写分量表里的字序号)
    final _ByteSink glyfOut = _ByteSink(glyf.length ~/ 4);
    final List<int> offsets = List<int>.filled(list.length + 1, 0);
    for (int i = 0; i < list.length; i++) {
      final int gid = list[i];
      offsets[i] = glyfOut.length;
      Uint8List g = sfnt.glyph(glyf, locaO, gid);
      if (g.isNotEmpty && Be(g).i16(0) < 0) {
        g = rewriteComposite(g, (int old) {
          // 越界的分量(源字体本身就坏)在 Kotlin 侧会数组越界; 这里按 -1 处理,
          // 随后被回读校验拦下 —— 正常字体永远走不到这个分支。
          return old >= 0 && old < remap.length ? remap[old] : -1;
        });
      }
      glyfOut.write(g);
      while (glyfOut.length % 4 != 0) {
        glyfOut.writeByte(0);
      }
    }
    offsets[list.length] = glyfOut.length;
    final Uint8List glyfBytes = glyfOut.toBytes();
    final bool longLoca = offsets[list.length] > 0x1FFFF;

    // 3. loca
    final Uint8List locaBytes =
        Uint8List((list.length + 1) * (longLoca ? 4 : 2));
    for (int i = 0; i < offsets.length; i++) {
      final int v = offsets[i];
      if (longLoca) {
        put32(locaBytes, i * 4, v);
      } else {
        put16(locaBytes, i * 2, v ~/ 2);
      }
    }

    // 4. hmtx/hhea: 全量长条目(numGlyphs 条), hhea.numberOfHMetrics 跟着改;
    //    垂直度量归一化也落在这一步 —— 它改的正是 hhea 与 OS/2 的同一批字段
    final Uint8List hmtxBytes = _buildHmtx(sfnt, list);
    final Uint8List hheaBytes = _ensure(sfnt.slice(sfnt.need('hhea')), 36);
    put16(hheaBytes, 34, list.length);
    // OS/2 单独取出来(后面不再走无脑搬运), 因为它可能要被归一化改写
    final SfntTable? os2Table = sfnt.tables['OS/2'];
    final Uint8List? os2Bytes = os2Table == null ? null : sfnt.slice(os2Table);
    final MetricsReport? metrics = options.normalizeMetrics
        ? Metrics.apply(hheaBytes, os2Bytes, sfnt.headInfo().$1)
        : null;

    // 5. head: 只改 indexToLocFormat 与 checkSumAdjustment(后者最后算)
    final Uint8List headBytes = _ensure(sfnt.slice(sfnt.need('head')), 54);
    put16(headBytes, 50, longLoca ? 1 : 0);
    put32(headBytes, 8, 0);

    // 6. maxp: numGlyphs 改成新值, 其余上限字段沿用(是上界, 仍成立)
    final Uint8List maxpBytes = _ensure(sfnt.slice(sfnt.need('maxp')), 32);
    put16(maxpBytes, 4, list.length);

    // 7. post: 换成 3.0, 只留 32 字节头。字形名是按旧字序号排的, 留着不但错位,
    //    还是几百 KB 的死重(源字体 post 表 450KB, 其中绝大部分是字形名)。
    final Uint8List postSrc = sfnt.slice(sfnt.need('post'));
    final Uint8List postBytes = Uint8List(32);
    postBytes.setRange(0, 32 < postSrc.length ? 32 : postSrc.length, postSrc);
    put32(postBytes, 0, 0x00030000);

    // 8. cmap: 一张 (3,1) 格式 4 子表, 覆盖全部目标字符
    final Uint8List cmapBytes = _buildCmap4(cmap, remap, list.length);

    final Map<String, Uint8List> tables = <String, Uint8List>{};
    tables['head'] = headBytes;
    tables['hhea'] = hheaBytes;
    tables['maxp'] = maxpBytes;
    tables['hmtx'] = hmtxBytes;
    tables['loca'] = locaBytes;
    tables['glyf'] = glyfBytes;
    tables['cmap'] = cmapBytes;
    tables['post'] = postBytes;
    for (final String t in copyTables) {
      if (t == 'OS/2') {
        if (os2Bytes != null) tables[t] = os2Bytes;
        continue;
      }
      final SfntTable? st = sfnt.tables[t];
      if (st != null) tables[t] = sfnt.slice(st);
    }

    final List<String> dropped =
        sfnt.tables.keys.where((String t) => !tables.containsKey(t)).toList()
          ..sort();
    final Uint8List out = _assemble(tables);

    // 9. 回读校验: 用同一份解析器读产出, 覆盖率必须 100%
    final Sfnt chk = Sfnt(out);
    final Map<int, int> chkCmap = chk.cmap();
    final int outGlyphs = chk.numGlyphs();
    // 源字体本来就没有的符号区/繁体字不在检查范围内(见 Charset.missingOptionalCount)
    int still = 0;
    for (final int c in chars) {
      if (!cmap.containsKey(c)) continue;
      final int g = chkCmap[c] ?? 0;
      if (!(g >= 1 && g < outGlyphs)) still++;
    }
    if (still != 0) {
      throw FontError('产出字体自检失败: 仍有 $still 个目标字符缺字形');
    }

    final List<String> notes = <String>[];
    if (dropped.any((String t) => t == 'GSUB' || t == 'GPOS' || t == 'GDEF')) {
      notes.add('已丢弃排版表(GSUB/GPOS/GDEF): 手环界面文字用不到连字与字距');
    }
    if (longLoca) notes.add('字形偏移超过 128KB，loca 用了长格式');
    if (missOptional > 0) {
      notes.add('源字体缺 $missOptional 个可选字符(符号区/繁体)，已跳过');
    }
    if (metrics != null) {
      notes.add('垂直度量已按系统字体比例归一化: 行高比 '
          '${metrics.ratioBefore.toStringAsFixed(3)} -> '
          '${metrics.ratioAfter.toStringAsFixed(3)}');
    }

    final List<String> keptTables = tables.keys.toList()..sort();
    return (
      out,
      Report(
        srcBytes: sfnt.bytes.length,
        outBytes: out.length,
        srcGlyphs: numGlyphs,
        outGlyphs: outGlyphs,
        cmapChars: chkCmap.length,
        gbTotal: Charset.gb2312.length,
        charset: options.charset,
        traditional: Charset.traditionalHits(cmap),
        metrics: metrics,
        skippedOptional: missOptional,
        keptTables: keptTables,
        droppedTables: dropped,
        notes: notes,
      ),
    );
  }

  // ---- hmtx ----

  static Uint8List _buildHmtx(Sfnt sfnt, List<int> list) {
    final Uint8List h = sfnt.slice(sfnt.need('hmtx'));
    final Be r = Be(h);
    final int nhm = sfnt.numHMetrics();
    if (nhm <= 0 || nhm > sfnt.numGlyphs()) {
      throw FontError('hhea.numberOfHMetrics 异常: $nhm');
    }
    final Uint8List out = Uint8List(list.length * 4);
    for (int i = 0; i < list.length; i++) {
      final int gid = list[i];
      final int adv;
      final int lsb;
      if (gid < nhm) {
        adv = r.u16(gid * 4);
        lsb = r.i16(gid * 4 + 2);
      } else {
        // 超出的字形没有自己的 advance, 沿用最后一条(OpenType 规定的读法);
        // lsb 在 hmtx 尾部的数组里, 表被截断时按 0 处理
        adv = r.u16((nhm - 1) * 4);
        final int at = nhm * 4 + (gid - nhm) * 2;
        lsb = at + 1 < h.length ? r.i16(at) : 0;
      }
      put16(out, i * 4, adv);
      put16(out, i * 4 + 2, lsb & 0xFFFF);
    }
    return out;
  }

  // ---- cmap format 4 ----

  /// 段按"码点连续且字序号也连续"切分，段内用 idDelta（不写 glyphIdArray）。
  /// 目标字符集里连续区段占绝大多数，段数因此很小；零散字符各成一段也不亏。
  static Uint8List _buildCmap4(
      Map<int, int> cmap, List<int> remap, int numGlyphs) {
    final List<int> codes = <int>[];
    for (final int c in cmap.keys) {
      if (c < 0 || c > 0xFFFE) continue;
      final int g = cmap[c]!;
      // remap 只覆盖原字序号 0..numGlyphs-1；越界的码点在 Kotlin 侧会数组越界,
      // 这里直接跳过（产出仍会被回读校验守一道）。
      if (g < 0 || g >= remap.length) continue;
      if (remap[g] < 0) continue;
      codes.add(c);
    }
    codes.sort();

    final List<List<int>> segs = <List<int>>[]; // [start, end, delta]
    int i = 0;
    while (i < codes.length) {
      final int start = codes[i];
      final int g0 = remap[cmap[start]!];
      int end = start;
      int j = i + 1;
      while (j < codes.length) {
        final int cj = codes[j];
        if (cj != end + 1) break;
        if (remap[cmap[cj]!] != g0 + (cj - start)) break;
        end = cj;
        j++;
      }
      segs.add(<int>[start, end, (g0 - start) & 0xFFFF]);
      i = j;
    }
    segs.add(<int>[0xFFFF, 0xFFFF, 1]); // 结束段: 0xFFFF 必须映射到 gid 0

    final int segCount = segs.length;
    final int segX2 = segCount * 2;
    final int len = 16 + segX2 * 4;
    if (len > 0xFFFF) {
      throw FontError('cmap 段数过多($segCount)，超出行格式 4 的长度上限');
    }
    int p2 = 1;
    int sel = 0;
    while (p2 * 2 <= segCount) {
      p2 *= 2;
      sel++;
    }
    final Uint8List sub = Uint8List(len);
    put16(sub, 0, 4);
    put16(sub, 2, len);
    put16(sub, 4, 0); // language
    put16(sub, 6, segX2);
    put16(sub, 8, p2 * 2); // searchRange = 2 * 2^floor(log2(segCount))
    put16(sub, 10, sel); // entrySelector = floor(log2(segCount))
    put16(sub, 12, segX2 - p2 * 2); // rangeShift = 2*segCount - searchRange
    const int endB = 14;
    final int startB = endB + segX2 + 2;
    final int deltaB = startB + segX2;
    final int rangeB = deltaB + segX2;
    for (int k = 0; k < segCount; k++) {
      put16(sub, endB + k * 2, segs[k][1]);
      put16(sub, startB + k * 2, segs[k][0]);
      put16(sub, deltaB + k * 2, segs[k][2]);
      put16(sub, rangeB + k * 2, 0);
    }

    final Uint8List out = Uint8List(12 + len);
    put16(out, 0, 0); // version
    put16(out, 2, 1); // numTables
    put16(out, 4, 3); // platform = Windows
    put16(out, 6, 1); // encoding = Unicode BMP
    put32(out, 8, 12); // 子表偏移
    out.setRange(12, 12 + len, sub);
    return out;
  }

  // ---- sfnt 组装 ----

  static Uint8List _assemble(Map<String, Uint8List> tables) {
    final List<String> tags = tables.keys.toList()..sort();
    final int n = tags.length;
    final int dirLen = 12 + n * 16;
    int total = dirLen;
    for (final String t in tags) {
      total += _round4(tables[t]!.length);
    }
    final Uint8List out = Uint8List(total);
    put32(out, 0, 0x00010000);
    put16(out, 4, n);
    // searchRange 等三个值是给二分查找用的提示, FreeType 不依赖; 按规范给对
    int p2 = 1;
    int entrySel = 0;
    while (p2 * 2 <= n) {
      p2 *= 2;
      entrySel++;
    }
    put16(out, 6, p2 * 16);
    put16(out, 8, entrySel);
    put16(out, 10, n * 16 - p2 * 16);

    int off = dirLen;
    int headOff = -1;
    for (int i = 0; i < n; i++) {
      final String tag = tags[i];
      final Uint8List data = tables[tag]!;
      final int dp = 12 + i * 16;
      for (int k = 0; k < 4; k++) {
        out[dp + k] = tag.codeUnitAt(k) & 0xFF;
      }
      put32(out, dp + 4, _checksum(data));
      put32(out, dp + 8, off);
      put32(out, dp + 12, data.length);
      out.setRange(off, off + data.length, data);
      if (tag == 'head') headOff = off;
      off += _round4(data.length);
    }
    if (headOff < 0) throw FontError('组装时找不到 head');

    // head.checkSumAdjustment = 0xB1B0AFBA - 整文件校验和(此时该字段为 0)
    int sum = 0;
    int i = 0;
    while (i < out.length) {
      int v = 0;
      for (int k = 0; k < 4; k++) {
        v = (v << 8) | (i + k < out.length ? out[i + k] & 0xFF : 0);
      }
      sum = (sum + v) & 0xFFFFFFFF;
      i += 4;
    }
    final int adj = (0xB1B0AFBA - sum) & 0xFFFFFFFF;
    put32(out, headOff + 8, adj);
    return out;
  }

  static int _checksum(Uint8List d) {
    int sum = 0;
    int i = 0;
    while (i < d.length) {
      int v = 0;
      for (int k = 0; k < 4; k++) {
        v = (v << 8) | (i + k < d.length ? d[i + k] & 0xFF : 0);
      }
      sum = (sum + v) & 0xFFFFFFFF;
      i += 4;
    }
    return sum;
  }

  /// 缺字样例渲染成人能看的字: 汉字/可打印 ASCII 直接给字形, 其余只给码点
  static String _renderSample(List<int> cps) => cps.map((int c) {
        final String hex = c.toRadixString(16).toUpperCase().padLeft(4, '0');
        if ((c >= 0x20 && c <= 0x7E) || (c >= 0x4E00 && c <= 0x9FFF)) {
          return "'${String.fromCharCode(c)}'(U+$hex)";
        }
        return 'U+$hex';
      }).join('、');

  /// Kotlin 的 `ensure`: 长度不足时补 0 到 n 字节；总是返回**副本**（源表不可被改写）
  static Uint8List _ensure(Uint8List d, int n) {
    if (d.length >= n) return Uint8List.fromList(d);
    final Uint8List out = Uint8List(n);
    out.setRange(0, d.length, d);
    return out;
  }

  static int _round4(int n) => (n + 3) ~/ 4 * 4;

  static void put16(Uint8List d, int o, int v) {
    d[o] = (v >> 8) & 0xFF;
    d[o + 1] = v & 0xFF;
  }

  static void put32(Uint8List d, int o, int v) {
    d[o] = (v >> 24) & 0xFF;
    d[o + 1] = (v >> 16) & 0xFF;
    d[o + 2] = (v >> 8) & 0xFF;
    d[o + 3] = v & 0xFF;
  }
}

/// 打包选项：字集档位 + 是否做垂直度量归一化（两项都是用户在界面上可选的）
class Options {
  const Options({
    this.charset = Kind.simplified,
    this.normalizeMetrics = true,
  });

  final Kind charset;
  final bool normalizeMetrics;

  @override
  String toString() =>
      'Options(charset: ${charset.name}, normalizeMetrics: $normalizeMetrics)';
}

/// 子集化结果报告（给界面显示"保留了多少字/省了多少体积"）
class Report {
  const Report({
    required this.srcBytes,
    required this.outBytes,
    required this.srcGlyphs,
    required this.outGlyphs,
    required this.cmapChars,
    required this.gbTotal,
    required this.charset,
    required this.traditional,
    required this.metrics,
    required this.skippedOptional,
    required this.keptTables,
    required this.droppedTables,
    required this.notes,
  });

  final int srcBytes;
  final int outBytes;
  final int srcGlyphs;
  final int outGlyphs;
  final int cmapChars;
  final int gbTotal;
  final Kind charset;
  final int traditional;
  final MetricsReport? metrics;
  final int skippedOptional;
  final List<String> keptTables;
  final List<String> droppedTables;
  final List<String> notes;

  @override
  String toString() => 'Report($srcBytes -> $outBytes 字节, 字形 $srcGlyphs -> '
      '$outGlyphs, cmap $cmapChars 字)';
}

/// 源字体缺硬要求字符时抛出，文案与 Kotlin 侧 MissingChars 一致。
class MissingCharsError extends FontError {
  MissingCharsError(this.count, this.sample, this.readable)
      : super('源字体缺 $count 个必需字符（汉字/ASCII），例如 $readable');

  final int count;
  final List<int> sample;
  final String readable;
}

/// 可按需增长的字节缓冲（对应 Kotlin 的 ByteArrayOutputStream）
class _ByteSink {
  _ByteSink(int capacity) : _buf = Uint8List(capacity < 16 ? 16 : capacity);

  Uint8List _buf;
  int length = 0;

  void writeByte(int v) {
    if (length == _buf.length) {
      final Uint8List nb = Uint8List(_buf.length * 2);
      nb.setRange(0, length, _buf);
      _buf = nb;
    }
    _buf[length++] = v & 0xFF;
  }

  void write(Uint8List d) {
    if (length + d.length > _buf.length) {
      int cap = _buf.length;
      while (cap < length + d.length) {
        cap *= 2;
      }
      final Uint8List nb = Uint8List(cap);
      nb.setRange(0, length, _buf);
      _buf = nb;
    }
    _buf.setRange(length, length + d.length, d);
    length += d.length;
  }

  Uint8List toBytes() => Uint8List.sublistView(_buf, 0, length);
}
