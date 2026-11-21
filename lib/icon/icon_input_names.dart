import 'device_target.dart';
import 'icon_spec.dart';

/// 不管选择器的顺序如何, 先按槽位把封面与动画归组, 再动工程里的文件。
class IconInputNames {
  /// 按文件名认出输入的用途。
  static (String, IconInputKind)? match(String name, DeviceTarget device) {
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    final base = (dot < 0 ? name : name.substring(0, dot)).trim();
    final IconInputKind kind;
    switch (extension) {
      case 'gif':
        kind = IconInputKind.gif;
      case 'bin':
        kind = base.toLowerCase().endsWith('_anim')
            ? IconInputKind.animation
            : IconInputKind.bin;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
      case 'bmp':
      case 'heic':
      case 'heif':
      case '':
        kind = IconInputKind.image;
      default:
        return null;
    }
    final key = kind == IconInputKind.animation
        ? base.substring(0, base.length - 5)
        : base;
    final slot = IconSpec.matchName(key, device);
    if (slot == null) return null;
    if (slot.group == IconSpecGroup.native && kind != IconInputKind.bin) {
      return null;
    }
    return (slot.stem, kind);
  }

  /// 按槽位归组, 并标出"一个槽位给了两份封面/两份动画"这类错误。
  static IconInputPlan plan(List<String> names, DeviceTarget device) {
    final matched = <IconInputSource>[];
    for (var i = 0; i < names.length; i++) {
      final (stem, kind) = asMatch(names[i], device);
      if (stem != null) matched.add(IconInputSource(i, stem, kind!));
    }
    final byStem = <String, List<IconInputSource>>{};
    for (final s in matched) {
      (byStem[s.stem] ??= <IconInputSource>[]).add(s);
    }
    final groups = <IconInputGroup>[
      for (final e in byStem.entries)
        IconInputGroup(e.key, e.value, _problem(e.value)),
    ];
    return IconInputPlan(groups, names.length - matched.length);
  }

  static (String?, IconInputKind?) asMatch(String name, DeviceTarget device) {
    final hit = match(name, device);
    return hit == null ? (null, null) : (hit.$1, hit.$2);
  }

  static String? _problem(List<IconInputSource> items) {
    final covers = items
        .where((s) =>
            s.kind == IconInputKind.image || s.kind == IconInputKind.bin)
        .length;
    final animations = items
        .where((s) =>
            s.kind == IconInputKind.gif || s.kind == IconInputKind.animation)
        .length;
    if (covers > 1) return '同一槽位不能有多个静态封面（PNG/图片与 BIN 也不能同时提供）';
    if (animations > 1) return '同一槽位不能有多个动画（GIF 与 _anim.bin 也不能同时提供）';
    return null;
  }
}

/// 输入用途(Kotlin 的 IconInputNames.Kind; Dart 不能嵌套类, 提到顶层)。
enum IconInputKind { image, bin, gif, animation }

/// 一个输入文件: 在原始列表里的下标、落到的 stem、用途。
class IconInputSource {
  const IconInputSource(this.index, this.stem, this.kind);

  final int index;
  final String stem;
  final IconInputKind kind;
}

/// 同一槽位的所有输入; [error] 非空表示这组不能直接用。
class IconInputGroup {
  const IconInputGroup(this.stem, this.sources, this.error);

  final String stem;
  final List<IconInputSource> sources;
  final String? error;
}

/// 归组结果: 各组 + 没认出来的文件数。
class IconInputPlan {
  const IconInputPlan(this.groups, this.unmatched);

  final List<IconInputGroup> groups;
  final int unmatched;
}
