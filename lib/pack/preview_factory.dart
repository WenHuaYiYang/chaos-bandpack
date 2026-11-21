import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextDirection, TextPainter, TextSpan, TextStyle;


/// 投递包的预览块 —— 与设备侧 `scripts/gen_preview.py` 同一个格式, 由 Flutter 的
/// `dart:ui` 现场光栅化, 不再依赖 Android 的 `android.graphics`。
///
/// 块结构(外层 12 字节头 + 压缩流):
///
/// ```
/// [0]      cf    = 0x10 厂商自定义格式
/// [1]      flags = 0x04, 其中 bits2..4 = 1 → 小米 RLE 压缩分支
/// [2..3]   0
/// [4..5]   w (u16LE)
/// [6..7]   h (u16LE)
/// [8..11]  压缩流长度 (u32LE)
/// 流:      u32LE 魔数 0x5AA521E0
///          u32LE 低 4 位 = 单元字节数 m(=1), bits4..27 = 解压总长 T(=1024 + w*h)
///          RLE: 控制字节 <0x80 → 重复 m 字节; >=0x80 → 字面拷贝 (c & 0x7F) * m 字节
/// ```
///
/// 解压出来是 `1024 字节 BGRA 调色板 + w*h 索引`, 与固件解压函数(0x0CA91EC4)一致。
///
/// 两条踩过的红线(PC 侧同款, 不得回退):
///   1. 可见像素一律**不透明**(预合成观感), 只有页面圆角外 a < 16 透明 ——
///      半透明 ramp 阶梯会在多圆角对象上产生黑晕;
///   2. 可见像素直接量化, **禁止再做 rgb*a/255**(二次预乘会把边缘压成黑点/白点)。
class PreviewFactory {
  static const int w = 336;
  static const int h = 480;
  static const double radius = 48;

  static const int magic = 0x5AA521E0;
  static const int visMin = 16;

  static const List<int> page = [0x1C, 0x1C, 0x1E];
  static const List<int> brandBlue = [0x2A, 0x82, 0xE4];
  static const List<int> brandYellow = [0xFF, 0xC3, 0x00];

  /// 字体包的界面几何(取自 `_lua/fontpack/main.lua`): 标题 -170 / 状态卡 -20 / 按钮 +110。
  static const double packTitleY = -170;
  static const double packTitleSize = 40;
  static const double packCardY = -20;
  static const double packCardW = 304;
  static const double packCardH = 150;
  static const double packBtnY1 = 110;
  static const double packBtnY2 = 186;
  static const double packBtnW = 304;
  static const double packBtnH = 64;
  static const double packStatusSize = 22;
  static const double packBtnTextSize = 24;

  /// 安装器界面的几何(取自安装器 Lua): 标题 -212(32 号) / 状态卡 -150 (304x68) /
  /// 五个 304x56 的按钮 -76, -12, 52, 116, 180。
  static const double installerTitleY = -212;
  static const double installerTitleSize = 32;
  static const double installerCardY = -150;
  static const double installerCardW = 304;
  static const double installerCardH = 68;
  static const double installerBtnW = 304;
  static const double installerBtnH = 56;
  static const List<double> installerBtnYs = [-76, -12, 52, 116, 180];

  // ===== 三种包的入口(文案与各自 Lua 一致) =====

  static Future<Uint8List> fontBlob(String title) => buildBlob(
        title: title,
        status: '已加载',
        buttons: const [PreviewButton('投递字体', PreviewStyle.primary)],
      );

  static Future<Uint8List> iconBlob(String title, String short) => buildBlob(
        title: title,
        status: '$short 已加载',
        buttons: const [PreviewButton('投递图标', PreviewStyle.primary)],
      );

  static Future<Uint8List> buildBlob({
    required String title,
    required String status,
    required List<PreviewButton> buttons,
  }) async {
    if (buttons.isEmpty || buttons.length > 2) {
      throw PreviewError('预览块最多两个按钮, 现在 ${buttons.length} 个');
    }
    final image = await _render(title, status, buttons);
    final rgba = await _rgba(image);
    final (indices, palette) = _quantize(rgba);
    final blob = _encode(indices, palette);
    // roundtrip 自校验: 解码器是固件逻辑的镜像, 必须逐字节还原索引区。
    final dec = decodeBlock(blob);
    if (dec.w != w || dec.h != h) throw PreviewError('预览块尺寸不符: ${dec.w}x${dec.h}');
    final raw = dec.raw;
    if (raw.length != 1024 + w * h) throw PreviewError('预览块解压长度不符: ${raw.length}');
    for (var i = 0; i < indices.length; i++) {
      if (raw[1024 + i] != indices[i]) throw PreviewError('预览块索引 roundtrip 失败');
    }
    return blob;
  }

  // ===== 绘制 =====

  /// 预览里那行中文用的字族。设备侧用 MiSans 的 GB2312+ASCII 子集;
  /// Flutter 侧由调用方先 `loadFontFromList` 注册, 再把这个名字传进来;
  /// 不传时退回系统字体(布局一样, 只是字形不同)。
  static String? fontFamily;

  static Future<ui.Image> _render(
    String title,
    String status,
    List<PreviewButton> buttons,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));

    void roundRect(double cx, double cy, double cw, double ch, ui.Color bg, ui.Color? line) {
      final r = ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(cx - cw / 2, cy - ch / 2, cw, ch),
        const ui.Radius.circular(24),
      );
      canvas.drawRRect(r, ui.Paint()..color = bg..style = ui.PaintingStyle.fill);
      if (line != null && line != bg) {
        canvas.drawRRect(
          r.deflate(0.5),
          ui.Paint()
            ..color = line
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }

    void text(String s, double cx, double cy, double size, ui.Color color) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: color,
            fontSize: size,
            fontFamily: fontFamily,
            height: 1.2,
          ),
        ),
        textAlign: ui.TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      // TextPainter 的 height 含行距, 直接居中会让汉字看起来偏下; 用行框中心对齐标题基线。
      tp.paint(canvas, ui.Offset(cx - tp.width / 2, cy - tp.height / 2 - size * 0.08));
    }

    // 页面底: 圆角 = 贴屏口径, 圆角外留透明
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        const ui.Radius.circular(radius),
      ),
      ui.Paint()..color = _c(page),
    );

    text(title, 168, 240 + packTitleY, packTitleSize, _c(const [0xF2, 0xF2, 0xF2]));
    roundRect(168, 240 + packCardY, packCardW, packCardH, _c(const [0x2C, 0x2C, 0x2E]),
        _c(const [0x3C, 0x3C, 0x3E]));
    text(status, 168, 240 + packCardY, packStatusSize, _c(const [0xB3, 0xB3, 0xB3]));

    final ys = buttons.length == 1 ? [packBtnY1] : [packBtnY1, packBtnY2];
    for (var i = 0; i < buttons.length; i++) {
      final b = buttons[i];
      final y = 240 + ys[i];
      switch (b.style) {
        case PreviewStyle.primary:
          roundRect(168, y, packBtnW, packBtnH, _c(const [0x25, 0x63, 0xEB]), null);
          text(b.text, 168, y, packBtnTextSize, _c(const [0xF2, 0xF2, 0xF2]));
        case PreviewStyle.danger:
          // 页底与红按 15% 混, 红字(与设备侧 danger 样式同口径)
          final red = const [0xFF, 0x45, 0x3A];
          final mix = [for (var j = 0; j < 3; j++) page[j] + ((red[j] - page[j]) * 0.15).toInt()];
          roundRect(168, y, packBtnW, packBtnH, _c(mix), null);
          text(b.text, 168, y, packBtnTextSize, _c(red));
      }
    }

    final picture = recorder.endRecording();
    return picture.toImage(w, h);
  }

  static ui.Color _c(List<int> rgb) => ui.Color.fromARGB(0xFF, rgb[0], rgb[1], rgb[2]);

  static Future<Uint8List> _rgba(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw PreviewError('预览图取不到像素');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  // ===== 量化: 直接入 5bit 网格桶(取高频代表色), 可见门限 16 =====

  static int _qkey(int r, int g, int b) => ((r >> 3) << 12) | ((g >> 3) << 6) | (b >> 3);

  static (Uint8List, List<List<int>>) _quantize(Uint8List rgba) {
    final counts = <int, int>{};
    final repr = <int, List<int>>{};
    for (var i = 0; i < w * h; i++) {
      final o = i * 4;
      if (rgba[o + 3] < visMin) continue; // 页面圆角外 → 透明
      final r = rgba[o], g = rgba[o + 1], b = rgba[o + 2];
      final k = _qkey(r, g, b);
      counts[k] = (counts[k] ?? 0) + 1;
      repr.putIfAbsent(k, () => [r, g, b]);
    }
    final keys = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final colors = [for (final k in keys) repr[k]!];
    for (final c in [page, brandBlue, brandYellow]) {
      if (!colors.any((x) => x[0] == c[0] && x[1] == c[1] && x[2] == c[2])) colors.add(c);
    }
    final palette = <List<int>>[
      [0, 0, 0, 0], // 条目 0 = 透明
      for (final c in colors) [c[2], c[1], c[0], 255], // B,G,R,A
    ];
    if (palette.length > 256) throw PreviewError('调色板超出 256 色: ${palette.length}');
    final palIndex = <int, int>{};
    for (var i = 0; i < colors.length; i++) {
      palIndex[_qkey(colors[i][0], colors[i][1], colors[i][2])] = i + 1;
    }
    final indices = Uint8List(w * h);
    for (var i = 0; i < w * h; i++) {
      final o = i * 4;
      if (rgba[o + 3] < visMin) continue;
      indices[i] = palIndex[_qkey(rgba[o], rgba[o + 1], rgba[o + 2])]!;
    }
    return (indices, palette);
  }

  // ===== 编码 =====

  static Uint8List _rleEncode(Uint8List data) {
    final out = BytesBuilder(copy: true);
    var i = 0;
    final n = data.length;
    while (i < n) {
      var j = i;
      while (j < n && data[j] == data[i]) {
        j++;
      }
      var run = j - i;
      if (run >= 3) {
        while (run > 0) {
          final cnt = math.min(run, 127);
          out.addByte(cnt);
          out.addByte(data[i]);
          run -= cnt;
          i += cnt;
        }
      } else {
        var k = i;
        while (k < n && k - i < 127) {
          if (k + 2 < n && data[k] == data[k + 1] && data[k] == data[k + 2]) break;
          k++;
        }
        out.addByte(0x80 | (k - i));
        out.add(Uint8List.sublistView(data, i, k));
        i = k;
      }
    }
    return out.takeBytes();
  }

  static Uint8List _u32(int v) => Uint8List.fromList(
      [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  static Uint8List _encode(Uint8List indices, List<List<int>> palette) {
    final total = 1024 + indices.length;
    final palBytes = Uint8List(1024);
    var off = 0;
    for (final c in palette) {
      palBytes[off] = c[0];
      palBytes[off + 1] = c[1];
      palBytes[off + 2] = c[2];
      palBytes[off + 3] = c[3];
      off += 4;
    }
    final payload = Uint8List(1024 + indices.length)
      ..setRange(0, 1024, palBytes)
      ..setRange(1024, 1024 + indices.length, indices);
    final stream = <int>[..._u32(magic), ..._u32(1 | (total << 4)), ..._rleEncode(payload)];
    final head = <int>[
      0x10, 0x04, 0, 0, //
      w & 0xFF, (w >> 8) & 0xFF, h & 0xFF, (h >> 8) & 0xFF,
      ..._u32(stream.length),
    ];
    return Uint8List.fromList([...head, ...stream]);
  }

  // ===== 解码(镜像固件 0x0CA91EC4, 自校验与测试用) =====

  static PreviewBlock decodeBlock(Uint8List blob) {
    if (blob.length < 20) throw PreviewError('预览块太短');
    if (blob[1] != 0x04 || ((blob[1] >> 2) & 7) != 1) throw PreviewError('不是小米 RLE 压缩分支');
    final bw = blob[4] | (blob[5] << 8);
    final bh = blob[6] | (blob[7] << 8);
    final dlen = blob[8] | (blob[9] << 8) | (blob[10] << 16) | (blob[11] << 24);
    if (12 + dlen > blob.length) throw PreviewError('预览块数据长度越界');
    final data = Uint8List.sublistView(blob, 12, 12 + dlen);
    if (data.length < 8) throw PreviewError('压缩流太短');
    final m0 = (data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24)) & 0xFFFFFFFF;
    if (m0 != magic) throw PreviewError('预览数据魔数不符');
    final w1 = (data[4] | (data[5] << 8) | (data[6] << 16) | (data[7] << 24)) & 0xFFFFFFFF;
    final m = w1 & 0xF;
    final total = (w1 >> 4) & 0xFFFFFF;
    if (m != 1 || total != 1024 + bw * bh) throw PreviewError('解压总长与规格不符: $total');
    final out = Uint8List(total);
    var oi = 0;
    var i = 8;
    while (oi < total) {
      if (i >= data.length) throw PreviewError('RLE 流提前结束');
      final cmd = data[i++];
      if (cmd < 0x80) {
        final cnt = cmd * m;
        if (i + m > data.length) throw PreviewError('RLE 流截断');
        for (var k = 0; k < cnt; k++) {
          out[oi + k] = data[i];
        }
        oi += cnt;
        i += m;
      } else {
        final k = (cmd & 0x7F) * m;
        if (i + k > data.length || oi + k > total) throw PreviewError('RLE 字面段越界');
        out.setRange(oi, oi + k, data, i);
        oi += k;
        i += k;
      }
    }
    if (i != data.length) throw PreviewError('RLE 流长度不符: i=$i');
    return PreviewBlock(w: bw, h: bh, raw: out);
  }
}

class PreviewBlock {
  PreviewBlock({required this.w, required this.h, required this.raw});
  final int w;
  final int h;

  /// 解压结果: 前 1024 字节是 BGRA 调色板, 之后是 w*h 个索引
  final Uint8List raw;

  List<int> paletteEntry(int i) {
    final o = i * 4;
    return [raw[o + 2], raw[o + 1], raw[o], raw[o + 3]]; // 还原成 R,G,B,A
  }

  int indexAt(int x, int y) => raw[1024 + y * w + x];
}

enum PreviewStyle { primary, danger }

class PreviewButton {
  const PreviewButton(this.text, this.style);
  final String text;
  final PreviewStyle style;
}

class PreviewError implements Exception {
  PreviewError(this.message);
  final String message;
  @override
  String toString() => 'PreviewError: $message';
}
