import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 容器公共校验与小端读写。所有"写进表盘文件"的字段都走这里, 保证大小端口径只有一处。
class ShellWriter {
  /// 主包身份: 必须与设备侧 `build_chaos_installer_043.py` 的 PKG_NAME 一致,
  /// 否则装上去会被当成另一个应用(桌面出现两个图标 / 覆盖不掉旧包)。
  static const String mainPkg = '979820260926';
  static const String pkgPrefix = '4348';
  static const int pkgLen = 12;
  static const int nameMax = 64;

  static final RegExp _pkgRe = RegExp(r'^[0-9]{12}$');

  /// 由包体内容派生包名: 前缀固定 4348, 后 8 位是 SHA-256 前 5 字节拼成的整数取模 1e8。
  /// 这样同一个包体永远得到同一个包名(覆盖安装), 不同包体一定撞不到一起。
  static String pkgFor(Uint8List blob) {
    final d = sha256.convert(blob).bytes;
    var v = 0;
    for (var i = 0; i < 5; i++) {
      v = (v * 256 + d[i]) & 0xFFFFFFFF;
    }
    return pkgPrefix + (v % 100000000).toString().padLeft(8, '0');
  }

  static void checkPkg(String pkg) {
    if (pkg.length != pkgLen || !_pkgRe.hasMatch(pkg)) {
      throw PackError('包名必须是 $pkgLen 位数字: $pkg');
    }
  }

  /// 显示名上限 64 字节(UTF-8), 但只能用到最后一个 NUL 之前。
  /// 与主包号相同会被侧载判成重复安装 —— 直接拦住。
  static void checkPkgAgainst(String pkg) {
    if (pkg == mainPkg) {
      throw PackError('表盘 ID 撞上了主包号 $pkg, 侧载会判重复安装');
    }
  }

  static void checkName(String name) {
    if (name.isEmpty) throw PackError('显示名不能为空');
    final b = utf8.encode(name);
    if (b.length >= nameMax) throw PackError('显示名超过 ${nameMax - 1} 字节');
    if (name.contains('\u0000')) throw PackError('显示名不能含 NUL');
  }

  static Uint8List writeU32To(Uint8List b, int off, int v) {
    b[off] = v & 0xFF;
    b[off + 1] = (v >> 8) & 0xFF;
    b[off + 2] = (v >> 16) & 0xFF;
    b[off + 3] = (v >> 24) & 0xFF;
    return b;
  }

  static int readU32Bytes(Uint8List b, int off) =>
      (b[off] & 0xFF) | ((b[off + 1] & 0xFF) << 8) | ((b[off + 2] & 0xFF) << 16) | ((b[off + 3] & 0xFF) << 24);
}

class PackError implements Exception {
  PackError(this.message);
  final String message;
  @override
  String toString() => 'PackError: $message';
}