import 'dart:typed_data';

import '../icon/animated_icons.dart';
import '../icon/device_target.dart';
import '../icon/dgf1.dart';
import '../icon/icon_input_names.dart';
import '../icon/icon_spec.dart';
import 'icon_make.dart';

/// 把一次批量导入里「同一槽位的若干个文件」变成一个槽位的成品。
///
/// 抽出来是为了能单独测: 一组要么全部成功, 要么原样不动。GIF 和 _anim.bin 这类
/// 成对素材只写一半, 工程里就会留下一张没有动画的封面, 下次打开很难看出少了什么。
abstract final class IconImport {
  /// [inputs] 的下标与 [IconInputSource.index] 对齐; bytes 为 null 表示那个文件读不出来。
  static (Map<String, Uint8List>, int) group({
    required IconInputGroup group,
    required List<Uint8List?> inputs,
    required List<String> names,
    required DeviceTarget device,
    Uint8List? existingCover,
  }) {
    final IconSpecSlot? slot = IconSpec.stemOf(group.stem, device);
    if (slot == null) throw IconMakeError('这台机型没有这个图标槽');

    IconInputSource? firstOf(Set<IconInputKind> kinds) {
      for (final IconInputSource s in group.sources) {
        if (kinds.contains(s.kind)) return s;
      }
      return null;
    }

    IconMade read(IconInputSource s, {Uint8List? cover}) {
      final Uint8List? bytes = inputs[s.index];
      if (bytes == null) throw IconMakeError('读不到文件内容: ' + names[s.index]);
      return IconMake.convert(
        bytes: bytes,
        name: names[s.index],
        slot: slot,
        existingCover: cover,
      );
    }

    Uint8List? cover;
    Uint8List? animation;
    var frames = 0;

    final IconInputSource? gifSource = firstOf(<IconInputKind>{IconInputKind.gif});
    if (gifSource != null) {
      final IconMade made = read(gifSource);
      if (made.animation == null) throw IconMakeError('GIF 文件内容与扩展名不符');
      cover = made.bytes;
      animation = made.animation;
      frames = made.frames;
    }

    final IconInputSource? still =
        firstOf(<IconInputKind>{IconInputKind.image, IconInputKind.bin});
    if (still != null) {
      final IconMade made = read(still);
      if (made.animation != null) {
        throw IconMakeError('动画 BIN 要命名成 <stem>_anim.bin');
      }
      cover = made.bytes;
    }

    final IconInputSource? animSource =
        firstOf(<IconInputKind>{IconInputKind.animation});
    if (animSource != null) {
      final IconMade made = read(animSource, cover: cover ?? existingCover);
      if (made.animation == null) throw IconMakeError('_anim.bin 里没有 DGF1 动画');
      cover = made.bytes;
      animation = made.animation;
      frames = made.frames;
    }

    if (cover == null) throw IconMakeError('缺少静态封面');
    final Map<String, Uint8List> out = <String, Uint8List>{group.stem: cover};
    if (animation != null) out[AnimatedIcons.key(group.stem)] = animation;
    AnimatedIcons.validateProject(out);
    return (out, frames);
  }

  /// 单个文件的换算, 不含分组。界面上的「点格子选一张」走这条。
  static IconMade one({
    required Uint8List bytes,
    required String name,
    required IconSpecSlot slot,
    Uint8List? existingCover,
  }) =>
      IconMake.convert(
        bytes: bytes,
        name: name,
        slot: slot,
        existingCover: existingCover,
      );

  /// 动画文件的帧数; 读不出帧表就返回 0(界面上不显示角标)。
  static int frames(Uint8List animation) {
    try {
      return Dgf1.parse(animation).frames.length;
    } on Dgf1Error {
      return 0;
    }
  }
}
