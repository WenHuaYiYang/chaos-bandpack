import 'dart:typed_data';

import '../pack/cipk.dart';
import 'animated_icons.dart';
import 'device_target.dart';
import 'lvgl_icon_codec.dart';
import 'native_icon_stems.dart';
import 'nine_icon_spec.dart';

/// 图标槽位、尺寸及导出资源。
class IconSpec {
  /// 9 Pro 旧版画布边长。
  static const int legacyCanvas = 112;

  /// p67 桌面画布边长。
  static const int canvas = 96;

  /// p67 桌面内容框边长。
  static const int content = 96;

  /// 内容框相对画布的留白。
  static const int margin = (canvas - content) ~/ 2;

  /// 导出的 p67 图标字节数: 12 字节头 + 96 × 96 × BGRA。
  static const int outBytes = 12 + canvas * canvas * 4;

  /// 导出的图像头(12 字节, BGRA, 未压缩)。
  static final Uint8List header = LvglIconCodec.header(canvas, canvas, 16, 0, canvas * 4);

  /// 某型号上不存在的槽位。
  static const Set<String> absentOnDevice = <String>{};

  /// 桌面图标(38 槽, 默认 96 × 96)。
  static final List<IconSpecSlot> desktop = <IconSpecSlot>[
    IconSpecSlot('activities', '活力指标'),
    IconSpecSlot('aivs', '小爱同学'),
    IconSpecSlot('alarm', '闹钟'),
    IconSpecSlot('alipay', '支付宝'),
    IconSpecSlot('breath', '呼吸放松'),
    IconSpecSlot('calendar', '日程'),
    IconSpecSlot('perpetual_calendar', '日历'),
    IconSpecSlot('camera', '遥控拍照'),
    IconSpecSlot('card', '卡包'),
    IconSpecSlot('chronograph', '秒表'),
    IconSpecSlot('compass', '指南针'),
    IconSpecSlot('dealt', '旧版待办'),
    IconSpecSlot('findphone', '找手机'),
    IconSpecSlot('flashlight', '手电筒'),
    IconSpecSlot('heartrate', '心率'),
    IconSpecSlot('innovation_research', '创新研究'),
    IconSpecSlot('interconnect', '多端联动'),
    IconSpecSlot('mijia', '米家'),
    IconSpecSlot('music', '音乐'),
    IconSpecSlot('mute', '手机静音'),
    IconSpecSlot('oxygen', '血氧'),
    IconSpecSlot('pressure', '压力'),
    IconSpecSlot('recorder', '录音机'),
    IconSpecSlot('settings', '设置'),
    IconSpecSlot('share', '融合设备中心'),
    IconSpecSlot('sleep', '睡眠'),
    IconSpecSlot('sports', '运动'),
    IconSpecSlot('sports_course', '跑步课程'),
    IconSpecSlot('sports_record', '运动记录'),
    IconSpecSlot('sports_status', '训练状态'),
    IconSpecSlot('timer', '倒计时'),
    IconSpecSlot('todo', '待办'),
    IconSpecSlot('tomato_clock', '番茄钟'),
    IconSpecSlot('vitality', '元气值'),
    IconSpecSlot('weather', '天气'),
    IconSpecSlot('womenhealth', '女性健康'),
    IconSpecSlot('worldclock', '世界时钟'),
    IconSpecSlot('wxpay', '微信支付'),
  ];

  /// 控制中心(9 槽)。
  static final List<IconSpecSlot> control = <IconSpecSlot>[
    IconSpecSlot('ctrl_flashlight', '手电筒', IconSpecGroup.control),
    IconSpecSlot('ctrl_setting', '设置', IconSpecGroup.control),
    IconSpecSlot('ctrl_battery', '省电', IconSpecGroup.control),
    IconSpecSlot('ctrl_bright', '亮度', IconSpecGroup.control),
    IconSpecSlot('ctrl_alarm', '闹钟', IconSpecGroup.control),
    IconSpecSlot('ctrl_findphone', '找手机', IconSpecGroup.control),
    IconSpecSlot('ctrl_disturb', '勿扰', IconSpecGroup.control),
    IconSpecSlot('ctrl_raise', '抬腕亮屏', IconSpecGroup.control),
    IconSpecSlot('ctrl_game', '游戏模式', IconSpecGroup.control),
  ];

  /// 设置(10 槽)。
  static final List<IconSpecSlot> settings = <IconSpecSlot>[
    IconSpecSlot('set_notify', '通知', IconSpecGroup.settings),
    IconSpecSlot('set_desktop', '桌面', IconSpecGroup.settings),
    IconSpecSlot('set_display', '显示', IconSpecGroup.settings),
    IconSpecSlot('set_disturb', '勿扰', IconSpecGroup.settings),
    IconSpecSlot('set_safe', '安全', IconSpecGroup.settings),
    IconSpecSlot('set_battery', '电池', IconSpecGroup.settings),
    IconSpecSlot('set_motion', '运动', IconSpecGroup.settings),
    IconSpecSlot('set_preference', '偏好', IconSpecGroup.settings),
    IconSpecSlot('set_mydevice', '我的设备', IconSpecGroup.settings),
    IconSpecSlot('set_wrist', '佩戴方式', IconSpecGroup.settings),
  ];

  /// 原生资源: 从 [NativeIconStems.all] 里摘掉控制中心与设置, 按字母序排。
  static final List<IconSpecSlot> native = <IconSpecSlot>[
    for (final stem in (NativeIconStems.all
            .difference(<String>{
              for (final s in <IconSpecSlot>[...control, ...settings]) s.stem,
            })
            .toList()
          ..sort()))
      IconSpecSlot(stem, stem, IconSpecGroup.native),
  ];

  /// 全部槽位(桌面 + 控制中心 + 设置 + 原生)。
  static final List<IconSpecSlot> slots = <IconSpecSlot>[
    ...desktop,
    ...control,
    ...settings,
    ...native,
  ];

  /// 按设备型号取槽位表: p67 用本表, n67 用 [NineIconSpec.slots]。
  static List<IconSpecSlot> all([DeviceTarget device = DeviceTarget.tenPro]) =>
      device == DeviceTarget.tenPro ? slots : NineIconSpec.slots;

  /// 按 stem 找槽位。
  static IconSpecSlot? stemOf(String s, [DeviceTarget device = DeviceTarget.tenPro]) {
    for (final slot in all(device)) {
      if (slot.stem == s) return slot;
    }
    return null;
  }

  /// 按分组取槽位。
  static List<IconSpecSlot> slotsOf(IconSpecGroup group,
          [DeviceTarget device = DeviceTarget.tenPro]) =>
      all(device).where((s) => s.group == group).toList();

  /// 日历的日期由程序绘制，预览只读取它自己的底图。
  static List<String> previewStems(String stem) => switch (stem) {
        'perpetual_calendar' => <String>['calendar_background'],
        'set_safe' => <String>['set_wrist'],
        'set_wrist' => <String>['set_safe'],
        _ => <String>[stem],
      };

  /// 精确匹配英文名或分类中文名；未注明分类的重名不匹配。
  static IconSpecSlot? matchName(String base, [DeviceTarget device = DeviceTarget.tenPro]) {
    final name = base.trim();
    for (final slot in all(device)) {
      if (slot.fileStem == name.toLowerCase()) return slot;
    }
    final byStem = stemOf(name.toLowerCase(), device);
    if (byStem != null) return byStem;
    final hits = all(device).where((slot) {
      if (slot.label == name) return true;
      for (final sep in const <String>['_', '-', '·', ' ']) {
        if (name == slot.group.label + sep + slot.label) return true;
      }
      return false;
    }).toList();
    return hits.length == 1 ? hits.first : null;
  }

  /// 一组 stem 里出现不止一次的那些(保持首次出现的顺序)。
  static Set<String> duplicateStems(List<String?> stems) {
    final counts = <String, int>{};
    for (final s in stems) {
      if (s == null) continue;
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return <String>{
      for (final e in counts.entries)
        if (e.value > 1) e.key,
    };
  }

  /// 各应用分别导出，勿扰自动补齐动画画布。
  static List<CipkIcon> export(Map<String, Uint8List> picked,
      [DeviceTarget device = DeviceTarget.tenPro,
      Map<String, Uint8List> animations = const <String, Uint8List>{}]) {
    if (picked.isEmpty) {
      if (animations.isNotEmpty) throw IconSpecError('动画缺少静态封面');
      return <CipkIcon>[];
    }
    final normalized = <String, Uint8List>{};
    picked.forEach((stem, bin) {
      final slot = stemOf(stem, device);
      if (slot == null) throw IconSpecError('未知图标槽位: $stem');
      if (normalized.containsKey(slot.stem)) {
        throw IconSpecError('图标槽位重复: ${slot.label}');
      }
      final decoded = LvglIconCodec.decode(bin);
      if (!(device == DeviceTarget.tenPro ||
          (decoded.width == slot.width && decoded.height == slot.height))) {
        throw IconSpecError('${slot.label}尺寸不匹配');
      }
      normalized[slot.fileStem] = bin;
    });
    final out = <CipkIcon>[
      for (final e in normalized.entries) CipkIcon(e.key, e.value),
    ];
    final disturb = normalized['ctrl_disturb'];
    if (disturb != null && device == DeviceTarget.tenPro && !normalized.containsKey('ctrl_dnd')) {
      final image = LvglIconCodec.decode(disturb);
      if (image.width == 64 && image.height == 64) {
        final canvas = List<int>.filled(160 * 124, 0);
        for (var y = 0; y < 64; y++) {
          canvas.setRange((y + 30) * 160 + 48, (y + 30) * 160 + 48 + 64, image.pixels, y * 64);
        }
        out.add(CipkIcon('ctrl_dnd', LvglIconCodec.indexedRle(canvas, 160, 124)));
      }
    }
    out.sort((a, b) => a.stem.compareTo(b.stem));
    return device == DeviceTarget.tenPro ? AnimatedIcons.prepare(out, animations) : out;
  }

  /// 手环上的落盘路径。
  static String devicePath(String stem) => '/data/chaos/icons/$stem.bin';
}

/// 槽位分组。
enum IconSpecGroup {
  desktop('桌面'),
  control('控制中心'),
  settings('设置'),
  system('系统应用'),
  native('原生资源');

  const IconSpecGroup(this.label);

  /// 给界面看的中文名。
  final String label;
}

/// 一个图标槽位: stem、中文名、分组、目标尺寸与文件名。
class IconSpecSlot {
  IconSpecSlot(this.stem, this.label,
      [this.group = IconSpecGroup.desktop,
      int? width,
      int? height,
      String? fileStem,
      this.device = DeviceTarget.tenPro])
      : width = width ?? (group == IconSpecGroup.desktop ? IconSpec.canvas : 64),
        height = height ?? width ?? (group == IconSpecGroup.desktop ? IconSpec.canvas : 64),
        fileStem = fileStem ?? stem;

  /// 槽位标识。
  final String stem;

  /// 中文名。
  final String label;

  /// 分组。
  final IconSpecGroup group;

  /// 目标宽。
  final int width;

  /// 目标高。
  final int height;

  /// 落到手环上的文件名(不带扩展名)。
  final String fileStem;

  /// 目标设备。
  final DeviceTarget device;

  /// 画布边长(宽高取大)。
  int get canvas => width > height ? width : height;

  /// 内容框边长: 桌面固定 96(9 Pro 为 100), 其它取宽高较小者。
  int get content => group == IconSpecGroup.desktop
      ? (device == DeviceTarget.ninePro ? 100 : IconSpec.content)
      : (width < height ? width : height);
}

class IconSpecError implements Exception {
  IconSpecError(this.message);

  final String message;

  @override
  String toString() => 'IconSpecError: $message';
}
