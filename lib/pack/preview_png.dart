import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'preview_factory.dart';

/// 把预览块解成 PNG, 给 Flutter 的 Image.memory 用。
///
/// 走 PNG 而不是直接塞原始索引有两个原因: Image.memory 只吃编码过的图片;
/// 而预览块的调色板是 BGRA + 索引, 设备上的固件解压函数认, Flutter 不认。
abstract final class PreviewPng {
  /// 解出 RGBA 像素(每像素 4 字节, R,G,B,A)。
  static Uint8List rgba(PreviewBlock block) {
    final int n = block.w * block.h;
    final Uint8List out = Uint8List(n * 4);
    final List<List<int>> palette = <List<int>>[
      for (int i = 0; i < 256; i++) block.paletteEntry(i),
    ];
    for (int i = 0; i < n; i++) {
      final List<int> e = palette[block.raw[1024 + i]];
      final int o = i * 4;
      out[o] = e[0];
      out[o + 1] = e[1];
      out[o + 2] = e[2];
      out[o + 3] = e[3];
    }
    return out;
  }

  /// 预览块 -> PNG 字节。
  static Uint8List encode(Uint8List blob) {
    final PreviewBlock block = PreviewFactory.decodeBlock(blob);
    final Uint8List rgbaBytes = rgba(block);
    final img.Image image = img.Image.fromBytes(
      width: block.w,
      height: block.h,
      bytes: rgbaBytes.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodePng(image));
  }
}
