import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../pack/pack_builders.dart';

/// 打包素材的读取口。
///
/// 素材不进版本库(见 tool/sync_assets.dart), 构建前从 Chaos-Module 拷进
/// assets/pack/。这里只负责读一次并缓存 —— 一次运行里它们不会变, 每次打包都
/// 重新解一遍没有意义。
class PackAssetsBundle {
  PackAssetsBundle._(this.assets, this.n67Lua);

  final PackAssets assets;

  /// 9 Pro 的清单模板(pack_n67/importer.lua.in), 10 Pro 那两件套之外的单件。
  final String n67Lua;

  static PackAssetsBundle? _cached;

  /// 读一次并缓存。缺素材时抛出带具体文件名与修复命令的异常。
  static Future<PackAssetsBundle> load([AssetBundle? bundle]) async {
    final PackAssetsBundle? hit = _cached;
    if (hit != null) return hit;
    final AssetBundle source = bundle ?? rootBundle;
    final Uint8List ko = await _read(source, 'chaos_sup.ko');
    final Uint8List iconBin = await _read(source, 'chaos_icon.bin');
    final String fontLua = await _readText(source, 'font_pack.lua');
    final String iconLua = await _readText(source, 'icon_pack.lua');
    final String n67Lua = await _readText(source, 'n67_importer.lua.in');
    final PackAssetsBundle made = PackAssetsBundle._(
      PackAssets(
        ko: ko,
        iconBin: iconBin,
        fontLua: fontLua,
        iconLua: iconLua,
      ),
      n67Lua,
    );
    _cached = made;
    return made;
  }

  /// 只测试用: 清掉缓存。
  static void reset() => _cached = null;

  static Future<Uint8List> _read(AssetBundle bundle, String name) async {
    try {
      final ByteData data = await bundle.load('assets/pack/$name');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object {
      throw MissingPackAsset(name);
    }
  }

  /// 模板是 UTF-8 源码, 不是字节表 —— 用 fromCharCodes 会把中文拆成乱码,
  /// 再编码回去就污染了设备侧读到的 Lua。
  static Future<String> _readText(AssetBundle bundle, String name) async {
    final Uint8List bytes = await _read(bundle, name);
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// 打包素材缺失 —— 需要先跑 tool/sync_assets.dart。
class MissingPackAsset implements Exception {
  const MissingPackAsset(this.name);

  final String name;

  @override
  String toString() =>
      '缺少打包素材 assets/pack/$name。先在 Chaos-Module 检出里跑 '
      'dart run tool/sync_assets.dart <Chaos-Module 路径>。';
}
