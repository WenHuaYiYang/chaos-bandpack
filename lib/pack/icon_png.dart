import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../icon/lvgl_icon_codec.dart';

/// 把 LVGL 图标 BIN(索引/RLE/BGRA8)解成 PNG, 给界面做缩略图。
abstract final class IconPng {
  /// 解出 RGBA 像素(每像素 4 字节, R,G,B,A)。
  static Uint8List rgba(LvglImage image) {
    final int n = image.width * image.height;
    final Uint8List out = Uint8List(n * 4);
    for (int i = 0; i < n; i++) {
      final int argb = image.pixels[i];
      final int o = i * 4;
      out[o] = (argb >> 16) & 0xFF;
      out[o + 1] = (argb >> 8) & 0xFF;
      out[o + 2] = argb & 0xFF;
      out[o + 3] = (argb >> 24) & 0xFF;
    }
    return out;
  }

  /// BIN -> PNG 字节。解不开就返回 null(界面显示占位)。
  static Uint8List? encode(Uint8List bin) {
    try {
      final LvglImage image = LvglIconCodec.decode(bin);
      final Uint8List rgbaBytes = rgba(image);
      final img.Image out = img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: rgbaBytes.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      return Uint8List.fromList(img.encodePng(out));
    } catch (_) {
      return null;
    }
  }
}
