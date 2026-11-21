import 'dart:typed_data';

import '../icon/device_target.dart';
import '../icon/portable_icons.dart';
import '../pack/cipk.dart';
import '../pack/nine_pack_builder.dart';
import '../pack/pack_builders.dart';
import '../pack/preview_factory.dart';
import 'assets_bundle.dart';

/// 打包编排: 读素材 -> 出预览块 -> 拼容器。
///
/// 与 Kotlin 版 PackMake 同口径: 素材在进程里只读一次, 预览块每次现渲染
/// (预览必须反映当前输入, 不能是缓存)。三个名字别搞混:
/// [packName] 是手环表盘列表里看到的显示名, [label] / [short] 是投递清单里的
/// 短名, [title] 是表盘内那行标题。
abstract final class PackMake {
  /// 按机型把已转换的槽位 BIN 收成 CIPK 条目。
  ///
  /// 换机型导出时只走这一层, 不用重新解码源图: 工程里存的是槽位 BIN, 尺寸换算
  /// 由 [PortableIcons.convert] 负责。
  static Future<List<CipkIcon>> iconFiles({
    required Map<String, Uint8List> picked,
    Map<String, Uint8List> animations = const <String, Uint8List>{},
    DeviceTarget device = DeviceTarget.tenPro,
  }) async {
    if (animations.isEmpty) {
      return PortableIcons.forTarget(picked, device).icons;
    }
    final Map<String, Uint8List> merged = <String, Uint8List>{
      for (final e in picked.entries) e.key: e.value,
      for (final e in animations.entries) '${e.key}_anim': e.value,
    };
    return PortableIcons.forTarget(merged, device).icons;
  }

  /// 字体包。[font] 是已子集化的 font.ttf 字节。
  ///
  /// 两个机型的容器完全不同: 10 Pro 是四槽 CIPK + 投递 Lua, 9 Pro 是 64000 字节
  /// 分片 + 清单 Lua。预览块两边共用。
  static Future<FontPackResult> fontPack({
    required String label,
    required String packName,
    required String title,
    required Uint8List font,
    String? pkgName,
    DeviceTarget device = DeviceTarget.tenPro,
  }) async {
    final PackAssetsBundle bundle = await PackAssetsBundle.load();
    final Uint8List preview = await PreviewFactory.fontBlob(title);
    final FontPackInputs inputs = FontPackInputs(
      label: label,
      packName: packName,
      title: title,
      font: font,
      pkgName: pkgName,
    );
    if (device == DeviceTarget.ninePro) {
      return NinePackBuilder.font(
        template: bundle.n67Lua,
        inputs: inputs,
        preview: preview,
      );
    }
    return FontPackBuilder.build(
      assets: bundle.assets,
      inputs: inputs,
      preview: preview,
    );
  }

  /// 图标包。[files] 是已经按槽位导出好的 CIPK 条目。
  static Future<IconPackResult> iconPack({
    required String short,
    required String packName,
    required String title,
    required List<CipkIcon> files,
    String? pkgName,
    DeviceTarget device = DeviceTarget.tenPro,
  }) async {
    final PackAssetsBundle bundle = await PackAssetsBundle.load();
    final Uint8List preview = await PreviewFactory.iconBlob(title, short);
    final IconPackInputs inputs = IconPackInputs(
      short: short,
      packName: packName,
      title: title,
      files: files,
      pkgName: pkgName,
    );
    if (device == DeviceTarget.ninePro) {
      return NinePackBuilder.icons(
        template: bundle.n67Lua,
        inputs: inputs,
        preview: preview,
      );
    }
    return IconPackBuilder.build(
      template: bundle.assets.iconLua,
      inputs: inputs,
      preview: preview,
    );
  }
}
