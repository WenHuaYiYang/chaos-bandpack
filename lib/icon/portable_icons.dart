import 'dart:typed_data';

import '../pack/cipk.dart';
import 'animated_icons.dart';
import 'device_target.dart';
import 'icon_convert.dart';
import 'icon_spec.dart';
import 'lvgl_icon_codec.dart';
import 'nine_icon_spec.dart';

/// 工程内保留源素材，导出时才转换目标规格。
class PortableIcons {
  /// 按目标型号导出: 先校验工程, 再逐个槽位转换规格。
  static PortableResult forTarget(
      Map<String, Uint8List> picked, DeviceTarget target) {
    AnimatedIcons.validateProject(picked);
    final selected = <String, Uint8List>{
      for (final e in picked.entries)
        if (IconSpec.stemOf(e.key, target) != null) e.key: e.value,
    };
    final converted = <String, Uint8List>{
      for (final e in selected.entries)
        e.key: convert(e.value, IconSpec.stemOf(e.key, target)!),
    };
    final animations = <String, Uint8List>{
      if (target == DeviceTarget.tenPro)
        for (final e in picked.entries)
          if (AnimatedIcons.isAnimationKey(e.key))
            AnimatedIcons.base(e.key): e.value,
    };
    return PortableResult(IconSpec.export(converted, target, animations),
        selected.length, omitted(picked, target));
  }

  /// 目标型号上没有对应槽位的键。
  static List<String> omitted(
          Map<String, Uint8List> picked, DeviceTarget target) =>
      omittedKeys(picked.keys.toSet(), target);

  static List<String> omittedKeys(Set<String> keys, DeviceTarget target) => <String>[
        for (final key in keys)
          if (IconSpec.stemOf(key, target) == null &&
              !(target == DeviceTarget.tenPro &&
                  AnimatedIcons.isAnimationKey(key) &&
                  AnimatedIcons.stems.contains(AnimatedIcons.base(key))))
            key,
      ];

  /// 把源素材转成目标槽位的规格。p67 的原生 BGRA 直接原样带走。
  static Uint8List convert(Uint8List bytes, IconSpecSlot slot) {
    final image = LvglIconCodec.decode(bytes);
    final nine = (bytes[0] & 255) != LvglIconCodec.headerTag;
    if (!nine && slot.device == DeviceTarget.tenPro) return bytes;
    if (image.width == slot.width && image.height == slot.height) {
      if (nine == (slot.device == DeviceTarget.ninePro)) return bytes;
      return slot.device == DeviceTarget.ninePro
          ? LvglIconCodec.bgra8(image.pixels, image.width, image.height)
          : LvglIconCodec.bgra(image.pixels, image.width, image.height);
    }
    if (!(slot.group == IconSpecGroup.desktop &&
        image.width == image.height &&
        (image.width == 96 || image.width == 100 || image.width == 112))) {
      throw PortableIconsError(
          '${slot.label}源图尺寸不支持转换：${image.width} × ${image.height}');
    }
    final content = image.width == 112
        ? <int>[
            for (var y = 0; y < 100; y++)
              ...image.pixels.sublist(
                  (y + 6) * 112 + 6, (y + 6) * 112 + 6 + 100),
          ]
        : image.pixels;
    final side = image.width == 112 ? 100 : image.width;
    final canvas = IconConvert.fitCanvas(content, side, side, slot.width);
    return slot.device == DeviceTarget.ninePro
        ? LvglIconCodec.bgra8(canvas, slot.width, slot.height)
        : LvglIconCodec.bgra(canvas, slot.width, slot.height);
  }

  /// 界面上的中文标签: "分组 · 名字", 动画再加"动画"。
  static String label(String key) {
    final base = AnimatedIcons.base(key);
    for (final slot in <IconSpecSlot>[...IconSpec.slots, ...NineIconSpec.slots]) {
      if (slot.stem == base) {
        final suffix = AnimatedIcons.isAnimationKey(key) ? '动画' : '';
        return '${slot.group.label} · ${slot.label}$suffix';
      }
    }
    return key;
  }
}

/// 导出结果: 图标列表、选中的槽位数、被跳过的键。
class PortableResult {
  const PortableResult(this.icons, this.selected, this.omitted);

  final List<CipkIcon> icons;
  final int selected;
  final List<String> omitted;
}

class PortableIconsError implements Exception {
  PortableIconsError(this.message);

  final String message;

  @override
  String toString() => 'PortableIconsError: $message';
}
