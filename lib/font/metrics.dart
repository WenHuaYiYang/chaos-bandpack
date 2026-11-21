import 'dart:typed_data';

/// 垂直度量归一化：把任意字体的 hhea / OS/2 度量对齐到固件自带字体的比例。
///
/// 为什么必须做：手环的行盒与标题位置是按固件自带 MiSans-Regular 的度量排死的
/// （参考值从固件资源包里那份 TTF 实读：upm 1000, hhea 1044/-282/0,
/// OS/2 typo 890/-110/326, win 1044/282 —— 行高比 1.326em）。自定义字体行高比不同
/// 就会在固定行盒里错位：霞鹜文楷 1.184 偏小(标题文字贴顶)、花朝粗 1.722 偏大 30%
/// (每行顶部留一大块空白)。对齐比例之后基线落点与系统字体一致。
///
/// 两个容易漏的点：
///   - **fsSelection 的 USE_TYPO_METRICS 位(0x0080)要清掉**：置位时渲染器改用 typo
///     那套度量，行盒算法与系统字体不同；固件的 MiSans 没置这个位。
///   - upm 不是 1000 的字体要按 upm/1000 **等比折算**，不能直接写常数。
///
/// 与 Kotlin 侧 Metrics.kt 完全等价（含 Math.round 的取整方向与负数处理）。
class Metrics {
  Metrics._();

  /// 固件 MiSans-Regular 的度量（从固件字体文件实测读出）
  static const int miUpm = 1000;
  static const int miAsc = 1044;
  static const int miDesc = -282;
  static const int miGap = 0;
  static const int miTypoAsc = 890;
  static const int miTypoDesc = -110;
  static const int miTypoGap = 326;

  /// OS/2 fsSelection 里的 USE_TYPO_METRICS 位
  static const int useTypoMetrics = 0x0080;

  // hhea 里的字段偏移
  static const int _hheaAsc = 4;
  static const int _hheaDesc = 6;
  static const int _hheaGap = 8;

  // OS/2 里的字段偏移
  static const int _os2FsSelection = 62;
  static const int _os2TypoAsc = 68;
  static const int _os2TypoDesc = 70;
  static const int _os2TypoGap = 72;
  static const int _os2WinAsc = 74;
  static const int _os2WinDesc = 76;
  static const int _os2MinLen = 78;

  /// 就地改写立即可用的度量字段。[upm] 是源字体 head.unitsPerEm。
  /// [hhea] 必须是可写副本（长度 >= 36）；[os2] 传 null 表示源字体没有 OS/2 表。
  static MetricsReport apply(Uint8List hhea, Uint8List? os2, int upm) {
    final double k = upm / miUpm;

    final int ascBefore = _readI16(hhea, _hheaAsc);
    final int descBefore = _readI16(hhea, _hheaDesc);
    final double ratioBefore = (ascBefore - descBefore) / upm;

    _writeI16(hhea, _hheaAsc, _scale(miAsc, k));
    _writeI16(hhea, _hheaDesc, _scale(miDesc, k));
    _writeI16(hhea, _hheaGap, _scale(miGap, k));

    if (os2 != null && os2.length >= _os2MinLen) {
      _writeI16(os2, _os2TypoAsc, _scale(miTypoAsc, k));
      _writeI16(os2, _os2TypoDesc, _scale(miTypoDesc, k));
      _writeI16(os2, _os2TypoGap, _scale(miTypoGap, k));
      _writeI16(os2, _os2WinAsc, _scale(miAsc, k));
      _writeI16(os2, _os2WinDesc, _scale(-miDesc, k));
      final int sel = _readU16(os2, _os2FsSelection);
      _writeU16(os2, _os2FsSelection, sel & (~useTypoMetrics & 0xFFFF));
    }

    final double ratioAfter = (_scale(miAsc, k) - _scale(miDesc, k)) / upm;
    return MetricsReport(upm, ratioBefore, ratioAfter);
  }

  /// 四舍五入到最近的整数（度量字段是 FWORD，负数也要正确取整）。
  /// Kotlin 的 Math.round(-282.9) = -283（向 +∞ 取整），Dart 的 double.round() 同向。
  static int _scale(int v, double k) => (v * k).round();

  static int _readU16(Uint8List b, int o) => ((b[o] & 0xFF) << 8) | (b[o + 1] & 0xFF);

  static int _readI16(Uint8List b, int o) {
    final int v = _readU16(b, o);
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  static void _writeU16(Uint8List b, int o, int v) {
    b[o] = (v >> 8) & 0xFF;
    b[o + 1] = v & 0xFF;
  }

  static void _writeI16(Uint8List b, int o, int v) => _writeU16(b, o, v & 0xFFFF);
}

/// 归一化结果（给界面显示"行高比从多少改到多少"）。
class MetricsReport {
  const MetricsReport(this.upm, this.ratioBefore, this.ratioAfter);

  final int upm;
  final double ratioBefore;
  final double ratioAfter;

  @override
  String toString() => 'MetricsReport(upm: $upm, 行高比: $ratioBefore -> $ratioAfter)';
}
