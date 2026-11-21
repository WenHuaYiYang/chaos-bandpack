import 'dart:convert';
import 'dart:typed_data';

import '../pack/cipk.dart';
import 'dgf1.dart';
import 'icon_spec.dart';
import 'lvgl_icon_codec.dart';
import 'native_icon_stems.dart';

/// CIA1 的位序是 ABI, 与界面上的槽位顺序无关。
class AnimatedIcons {
  /// 支持 DGF1 动画的桌面 stem(38 个, 顺序即 CIA1 的位序)。
  static const List<String> stems = <String>[
    'activities',
    'aivs',
    'alarm',
    'alipay',
    'breath',
    'calendar',
    'camera',
    'card',
    'chronograph',
    'compass',
    'dealt',
    'findphone',
    'flashlight',
    'heartrate',
    'innovation_research',
    'interconnect',
    'mijia',
    'music',
    'mute',
    'oxygen',
    'perpetual_calendar',
    'pressure',
    'recorder',
    'settings',
    'share',
    'sleep',
    'sports',
    'sports_course',
    'sports_record',
    'sports_status',
    'timer',
    'todo',
    'tomato_clock',
    'vitality',
    'weather',
    'womenhealth',
    'worldclock',
    'wxpay',
  ];

  /// 动画文件在投递包里的 stem: `<stem>_anim`。
  static String key(String stem) => '${stem}_anim';

  /// 这个 stem 是不是动画键。
  static bool isAnimationKey(String key) => key.endsWith('_anim');

  /// 动画键对应的桌面 stem。
  static String base(String key) =>
      key.endsWith('_anim') ? key.substring(0, key.length - 5) : key;

  /// 去掉某个槽位的静态图、动画以及它带出来的伴生文件。
  static Map<String, Uint8List> withoutSlot(
          Map<String, Uint8List> images, String stem) =>
      <String, Uint8List>{
        for (final e in images.entries)
          if (e.key != stem &&
              e.key != key(stem) &&
              !(stem == 'ctrl_disturb' && e.key == 'ctrl_dnd'))
            e.key: e.value,
      };

  /// 生成 CIA1 索引: 20 字节, u64 位掩码标出哪些桌面 stem 有动画。
  static Uint8List index(Set<String> stemsWithAnimation) {
    for (final s in stemsWithAnimation) {
      if (!stems.contains(s)) {
        throw AnimatedIconsError('只有 38 个桌面 stem 支持 DGF1 动画');
      }
    }
    final out = Uint8List(20);
    out.setRange(0, 4, 'CIA1'.codeUnits); // ASCII
    Dgf1.w16(out, 4, 96);
    Dgf1.w16(out, 6, 96);
    Dgf1.w16(out, 8, 38);
    var mask = 0;
    for (final s in stemsWithAnimation) {
      mask |= 1 << stems.indexOf(s);
    }
    Dgf1.w32(out, 12, mask & 0xFFFFFFFF);
    Dgf1.w32(out, 16, (mask >> 32) & 0xFFFFFFFF);
    return out;
  }

  /// 读回 CIA1 索引里的 stem 集合。
  static Set<String> readIndex(Uint8List bytes) {
    if (!(bytes.length == 20 &&
        ascii.decode(Uint8List.sublistView(bytes, 0, 4), allowInvalid: true) == 'CIA1' &&
        Dgf1.u16(bytes, 4) == 96 &&
        Dgf1.u16(bytes, 6) == 96 &&
        Dgf1.u16(bytes, 8) == 38 &&
        Dgf1.u16(bytes, 10) == 0)) {
      throw AnimatedIconsError('CIA1 索引头不合法');
    }
    final mask = Dgf1.u32(bytes, 12) | (Dgf1.u32(bytes, 16) << 32);
    if (mask >> 38 != 0) throw AnimatedIconsError('CIA1 第 38–63 位必须为 0');
    return <String>{
      for (var i = 0; i < stems.length; i++)
        if (mask & (1 << i) != 0) stems[i],
    };
  }

  /// 工程里的负载可以直接带回动画, 导出 9 Pro 时再换成静态封面。
  static void validateProject(Map<String, Uint8List> images) {
    if (images.containsKey('animations')) {
      throw AnimatedIconsError('工程中的动画索引由导出时自动生成');
    }
    images.forEach((stem, bytes) {
      if (isAnimationKey(stem)) {
        final source = base(stem);
        if (!stems.contains(source)) {
          throw AnimatedIconsError('未知桌面动画槽位：$source');
        }
        Dgf1.parse(bytes);
        final cover = images[source];
        if (cover == null) {
          throw AnimatedIconsError('$source 的动画缺少静态封面');
        }
        final decoded = LvglIconCodec.decode(cover);
        if (!(decoded.width == 96 && decoded.height == 96)) {
          throw AnimatedIconsError('$source 动画的封面必须为 96 × 96');
        }
      } else {
        if (!(bytes.length <= Cipk.iconLenMax)) {
          throw AnimatedIconsError('$stem 静态文件超过 512 KiB');
        }
        LvglIconCodec.decode(bytes);
      }
    });
  }

  /// 投递前自查: stem 不重复、没有未知 stem、静态文件是 p67 原生头、CIA1 与动画文件对得上。
  static void validateFiles(List<CipkIcon> files, {bool requireIndex = false}) {
    if (files.map((f) => f.stem).toSet().length != files.length) {
      throw AnimatedIconsError('图标文件名重复');
    }
    final map = <String, Uint8List>{for (final f in files) f.stem: f.data};
    final images = <String, Uint8List>{
      for (final e in map.entries)
        if (e.key != 'animations') e.key: e.value,
    };
    final known = <String>{
      ...stems,
      ...NativeIconStems.all,
      for (final s in IconSpec.slots) s.stem,
    };
    for (final stem in images.keys) {
      final ok =
          isAnimationKey(stem) ? stems.contains(base(stem)) : known.contains(stem);
      if (!ok) throw AnimatedIconsError('投递包包含未知 stem');
    }
    if (!images.keys.any((k) => !isAnimationKey(k))) {
      throw AnimatedIconsError('投递包没有静态封面或图标');
    }
    for (final e in images.entries) {
      if (isAnimationKey(e.key)) continue;
      if (e.value.isEmpty || e.value.first != LvglIconCodec.headerTag) {
        throw AnimatedIconsError('p67 静态文件必须使用原生图像头，不能直接放入 9 Pro DAT');
      }
    }
    validateProject(images);
    final animated = <String>{
      for (final k in images.keys)
        if (isAnimationKey(k)) base(k),
    };
    final index = map['animations'];
    if (requireIndex && index == null) {
      throw AnimatedIconsError('投递包缺少 CIA1 索引');
    }
    if (index != null) {
      final read = readIndex(index);
      if (read.length != animated.length || !read.containsAll(animated)) {
        throw AnimatedIconsError('CIA1 索引与动画文件不一致');
      }
    }
  }

  /// 把静态图与动画拼成投递包(动画按 stem 排序, 最后补 CIA1 索引)。
  static List<CipkIcon> prepare(
      List<CipkIcon> statics, Map<String, Uint8List> animations) {
    final keys = animations.keys.toList()..sort();
    final result = <CipkIcon>[
      ...statics,
      for (final stem in keys) CipkIcon(key(stem), animations[stem]!),
      CipkIcon('animations', index(animations.keys.toSet())),
    ];
    validateFiles(result, requireIndex: true);
    return result;
  }

  /// 投递包视图: 已经有索引的就地校验, 否则按静态图 + 动画重新拼一遍。
  static List<CipkIcon> payload(List<CipkIcon> files) {
    if (files.any((f) => f.stem == 'animations')) {
      validateFiles(files, requireIndex: true);
      return files;
    }
    if (files.map((f) => f.stem).toSet().length != files.length) {
      throw AnimatedIconsError('图标文件名重复');
    }
    return prepare(
      <CipkIcon>[
        for (final f in files)
          if (!isAnimationKey(f.stem)) f,
      ],
      <String, Uint8List>{
        for (final f in files)
          if (isAnimationKey(f.stem)) base(f.stem): f.data,
      },
    );
  }
}

class AnimatedIconsError implements Exception {
  AnimatedIconsError(this.message);

  final String message;

  @override
  String toString() => 'AnimatedIconsError: $message';
}
