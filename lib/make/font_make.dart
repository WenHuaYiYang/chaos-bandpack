import 'dart:typed_data';

import '../font/charset.dart';
import '../font/font_subset.dart';
import '../font/sfnt.dart';

/// 字体处理编排: 源字体 -> (归一化 + 子集化) -> 可预览的产出。
///
/// 一条纪律: **预览的字体和打进包里的字体必须是同一份字节**。所以这里只做一次
/// 子集化, 预览用它、打包也用它 —— 不做"预览用一套、打包另算一套"的事(那等于
/// 预览在说谎)。
///
/// 与 Kotlin 版 FontMake 的差别只有一处: Kotlin 顺手落了份 ttf 给
/// Typeface.createFromFile, Flutter 侧由界面自己把 [Made.font] 交给
/// FontLoader, 这里不碰文件系统。
abstract final class FontMake {
  /// 子集化。[src] 是源字体字节。几 MB 的字体要几秒, 调用方要放到
  /// compute()/isolate 里跑, 别卡界面。
  ///
  /// [preserve] 为 true 时原样保留字节(导入投递包时用: 那份字体已经是设备
  /// 在用的口径, 再裁一次等于换字体)。
  static Made build(
    Uint8List src, {
    Options options = const Options(),
    bool preserve = false,
  }) {
    if (preserve) {
      final Sfnt sfnt = Sfnt(src);
      final Map<int, int> cmap = sfnt.cmap();
      return Made(
        font: src,
        report: Report(
          srcBytes: src.length,
          outBytes: src.length,
          srcGlyphs: sfnt.numGlyphs(),
          outGlyphs: sfnt.numGlyphs(),
          cmapChars: cmap.length,
          gbTotal: Charset.gb2312.length,
          charset: options.charset,
          traditional: Charset.traditionalHits(cmap),
          metrics: null,
          skippedOptional: 0,
          keptTables: sfnt.tables.keys.toList()..sort(),
          droppedTables: const <String>[],
          notes: const <String>['保留导入投递包的字体字节，未再次裁剪或归一化'],
        ),
      );
    }
    final (Uint8List out, Report report) = FontSubset.subset(src, options: options);
    return Made(font: out, report: report);
  }

  /// 源字体可读性预检(选文件后立刻给反馈, 不等到打包)。
  static Precheck precheck(Uint8List src) {
    final Sfnt sfnt = Sfnt(src);
    final Map<int, int> cmap = sfnt.cmap();
    final List<int> sample = Charset.missingRequired(cmap);
    return Precheck(
      glyphs: sfnt.numGlyphs(),
      cmapChars: cmap.length,
      missingRequired: Charset.missingRequiredCount(cmap),
      sample: sample,
      traditional: Charset.traditionalHits(cmap),
    );
  }
}

/// 子集化产出: 字体字节 + 报告。
class Made {
  const Made({required this.font, required this.report});

  final Uint8List font;
  final Report report;
}

/// 预检结果: 字形数、cmap 字符数、缺字数量与样例。
class Precheck {
  const Precheck({
    required this.glyphs,
    required this.cmapChars,
    required this.missingRequired,
    required this.sample,
    required this.traditional,
  });

  final int glyphs;
  final int cmapChars;
  final int missingRequired;
  final List<int> sample;
  final int traditional;

  bool get ok => missingRequired == 0;

  /// 缺字样例, 形如 "U+4E00、U+9F99"。
  String get sampleText => sample.map((int c) {
        final String hex = c.toRadixString(16).toUpperCase().padLeft(4, '0');
        return 'U+$hex';
      }).join('、');
}
