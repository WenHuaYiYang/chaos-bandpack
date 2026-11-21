import 'dart:convert';
import 'dart:typed_data';

import 'shell_writer.dart';

/// 容器壳的**从零合成**(与 Chaos-Module 的 `tools/container_shell.py` 的 `build_shell()` 逐字节同构)。
///
/// 为什么不再拿一份主包当模板: 模板会漂移(主包换壳/换号, App 还在用旧的), 而壳里真正
/// 需要继承的只有"主题表那几个指针与计数", 那些本来就是可以从文件条数算出来的派生量。
///
/// ```
/// 0x00  u32 魔数 0x1234A55A     0x04 u32 容器版本(原包 0x10000, p67 支持 1.x)
/// 0x10  u32 0x800               0x14 u32 0x10000    0x18 0    0x1C 主题数 = 1
/// 0x20  u32 记录表结束地址( = 预览块起点)              0x24 0
/// 0x28  12 字节包名 pkgName(身份键, 撞号 = 同一个包)
/// 0x68  64 字节显示名(UTF-8, NUL 补齐)
/// 0xA8  主题表: (0x80000000, 记录表结束, 1, 0x148)
///       0xB8..0xFF 共 9 组 (u32,u32): 前 5 组的第二个字 = 首条文件记录地址,
///       后 4 组的第二个字 = 尾标记地址; 0xD8 那组的第一个字 = **文件条数**
///       0x100.. 主题名(默认"样式1")
/// 0x148 记录表: 首条 (0, 0, 尾标记地址, 0x10) + 每条文件 (0x05000000|槽号, 0, 偏移, 长度)
///       + 尾标记 (0x05000000, 0, 0, 0)
///       [预览块 12 字节头 + 数据]
///       [文件区: 每条 = u32((长度 & 0xFFFFFF) | (路径长 << 24)) + 16 字节零 + 路径 + 内容]
/// ```
class ShellBuilder {
  static const int magic = 0x1234A55A;
  static const int deviceCode = 0x10000;
  static const int previewTag = 0x410;
  static const int previewHdr = 12;

  static const int recOff = 0x148;
  static const int pkgOff = 0x28;
  static const int pkgLen = 12;
  static const int nameOff = 0x68;
  static const int nameMax = 64;
  static const int themeOff = 0xA8;
  static const int themeEnd = 0x148;
  static const int fileCntOff = 0xD8;
  static const int themeNameOff = 0x100;
  static const int themeNameMax = themeEnd - themeNameOff;
  static const int themePtrSlots = 5;
  static const int themeTailSlots = 4;
  static const int recUidBase = 0x05000000;
  static const int blobHdrLen = 20;
  static const String defaultThemeName = '样式1';

  static int recordEnd(int fileCount) => recOff + 16 * (2 + fileCount);

  /// 先按字符查再编码: `ascii.encode` 会把非 ASCII 换成 '?'(PC 侧是直接抛),
  /// 那样中文路径会被悄悄改写成一个不存在的名字。
  static Uint8List _blobFor(String path, Uint8List data) {
    for (final c in path.codeUnits) {
      if (c < 0x20 || c >= 0x7F) {
        throw PackError('槽路径必须是可打印 ASCII: $path');
      }
    }
    if (path.isEmpty) throw PackError('槽路径不能为空');
    final pb = ascii.encode(path);
    if (data.length >= (1 << 24)) throw PackError('$path 超过单槽 24bit 长度上限(16MB)');
    if (pb.length >= 256) throw PackError('槽路径太长: $path');
    final out = Uint8List(blobHdrLen + pb.length + data.length);
    ShellWriter.writeU32To(out, 0, (data.length & 0xFFFFFF) | (pb.length << 24));
    out.setRange(blobHdrLen, blobHdrLen + pb.length, pb);
    out.setRange(blobHdrLen + pb.length, out.length, data);
    return out;
  }

  /// 合成一份完整容器。[preview] 是预览块原始字节(含 12 字节头)。
  static Uint8List build({
    required List<ShellEntry> files,
    required String pkgName,
    required String displayName,
    required Uint8List preview,
    String themeName = defaultThemeName,
    int device = deviceCode,
  }) {
    ShellWriter.checkPkg(pkgName);
    ShellWriter.checkName(displayName);
    final pkg = ascii.encode(pkgName);
    final nb = utf8.encode(displayName);
    final tb = utf8.encode(themeName);
    if (tb.length > themeNameMax) throw PackError('主题名过长');
    checkPreview(preview);
    if (files.isEmpty || files.length >= 256) {
      throw PackError('文件条数必须在 1..255(槽号占一个字节), 现在 ${files.length}');
    }

    final n = files.length;
    final recEnd = recordEnd(n);
    final firstRec = recOff + 16;
    final tailRec = recEnd - 16;
    final fileRegion = recEnd + preview.length;

    final shell = Uint8List(fileRegion);
    ShellWriter.writeU32To(shell, 0x00, magic);
    ShellWriter.writeU32To(shell, 0x04, device);
    ShellWriter.writeU32To(shell, 0x10, 0x800);
    ShellWriter.writeU32To(shell, 0x14, 0x10000);
    ShellWriter.writeU32To(shell, 0x1C, 1);
    ShellWriter.writeU32To(shell, 0x20, recEnd);
    shell.setRange(pkgOff, pkgOff + pkgLen, pkg);
    shell.setRange(nameOff, nameOff + nb.length, nb);

    ShellWriter.writeU32To(shell, themeOff, 0x80000000);
    ShellWriter.writeU32To(shell, themeOff + 4, recEnd);
    ShellWriter.writeU32To(shell, themeOff + 8, 1);
    ShellWriter.writeU32To(shell, themeOff + 12, recOff);
    for (var i = 0; i < themePtrSlots; i++) {
      final at = themeOff + 16 + 8 * i;
      ShellWriter.writeU32To(shell, at, at == fileCntOff ? n : 0);
      ShellWriter.writeU32To(shell, at + 4, firstRec);
    }
    for (var i = 0; i < themeTailSlots; i++) {
      final at = themeOff + 16 + 8 * (themePtrSlots + i);
      ShellWriter.writeU32To(shell, at, 0);
      ShellWriter.writeU32To(shell, at + 4, tailRec);
    }
    shell.setRange(themeNameOff, themeNameOff + tb.length, tb);

    ShellWriter.writeU32To(shell, recOff, 0);
    ShellWriter.writeU32To(shell, recOff + 4, 0);
    ShellWriter.writeU32To(shell, recOff + 8, tailRec);
    ShellWriter.writeU32To(shell, recOff + 12, 0x10);

    final blobs = <Uint8List>[];
    var pos = fileRegion;
    for (var i = 0; i < n; i++) {
      final blob = _blobFor(files[i].path, files[i].data);
      final at = recOff + 16 * (1 + i);
      ShellWriter.writeU32To(shell, at, recUidBase + i);
      ShellWriter.writeU32To(shell, at + 4, 0);
      ShellWriter.writeU32To(shell, at + 8, pos);
      ShellWriter.writeU32To(shell, at + 12, blob.length);
      blobs.add(blob);
      pos += blob.length;
    }
    ShellWriter.writeU32To(shell, tailRec, recUidBase);
    ShellWriter.writeU32To(shell, tailRec + 4, 0);
    ShellWriter.writeU32To(shell, tailRec + 8, 0);
    ShellWriter.writeU32To(shell, tailRec + 12, 0);
    shell.setRange(recEnd, recEnd + preview.length, preview);

    final out = Uint8List(pos)..setRange(0, shell.length, shell);
    var at = shell.length;
    for (final b in blobs) {
      out.setRange(at, at + b.length, b);
      at += b.length;
    }
    if (out.length != pos) throw PackError('布局不自洽: 预期 $pos 实际 ${out.length}');
    return out;
  }

  static void checkPreview(Uint8List preview) {
    if (preview.length < previewHdr) throw PackError('预览块太短');
    final tag = ShellWriter.readU32Bytes(preview, 0);
    if (tag != previewTag) throw PackError('预览块标签不对: 0x${tag.toRadixString(16)}');
    final plen = ShellWriter.readU32Bytes(preview, 8);
    if (plen < 0 || preview.length != previewHdr + plen) {
      throw PackError('预览块长度与头里的字段不符');
    }
  }

  /// 取产物里的预览块原始字节
  static Uint8List previewOf(Uint8List raw) {
    if (raw.length < recOff) throw PackError('容器头太短');
    final recEnd = ShellWriter.readU32Bytes(raw, 0x20);
    if (recEnd < recOff || recEnd > raw.length - previewHdr) throw PackError('预览块起点越界');
    if (ShellWriter.readU32Bytes(raw, recEnd) != previewTag) throw PackError('预览块标签不对');
    final plen = ShellWriter.readU32Bytes(raw, recEnd + 8);
    if (plen < 0 || plen > raw.length - recEnd - previewHdr) throw PackError('预览块越界');
    return Uint8List.fromList(raw.sublist(recEnd, recEnd + previewHdr + plen));
  }

  /// 打包的最后一道门: 把自己刚写出来的字节拆回来逐字段核对。
  static ShellParsed parse(Uint8List raw) {
    if (raw.length > 32000000) throw PackError('容器超过 32 MB');
    if (raw.length < recOff + 16 * 3) throw PackError('容器太短');
    if (ShellWriter.readU32Bytes(raw, 0) != magic) throw PackError('容器魔数不符');
    if ((ShellWriter.readU32Bytes(raw, 4) >> 16) != 1) {
      throw PackError('不是支持的 p67 1.x 容器版本');
    }
    final n = ShellWriter.readU32Bytes(raw, fileCntOff);
    if (n < 1 || n > 255) throw PackError('文件条数非法: $n');
    final recEnd = ShellWriter.readU32Bytes(raw, 0x20);
    if (recEnd != recordEnd(n)) throw PackError('记录表结束地址与条数不符: $recEnd');
    if (recEnd > raw.length) throw PackError('记录表越界');
    if (ShellWriter.readU32Bytes(raw, themeOff + 4) != recEnd) {
      throw PackError('主题表的记录表指针与 0x20 不一致');
    }
    if (ShellWriter.readU32Bytes(raw, themeOff) != 0x80000000) {
      throw PackError('主题表首字不对');
    }
    if (ShellWriter.readU32Bytes(raw, themeOff + 8) != 1) throw PackError('主题数不是 1');
    if (ShellWriter.readU32Bytes(raw, themeOff + 12) != recOff) {
      throw PackError('主题表里的记录表地址不对');
    }
    final firstRec = recOff + 16;
    final tailRec = recEnd - 16;
    for (var i = 0; i < themePtrSlots; i++) {
      final at = themeOff + 16 + 8 * i;
      final cnt = ShellWriter.readU32Bytes(raw, at);
      if (cnt != (at == fileCntOff ? n : 0)) throw PackError('主题表计数槽 $i 不对');
      if (ShellWriter.readU32Bytes(raw, at + 4) != firstRec) {
        throw PackError('主题表首记录指针 $i 不对');
      }
    }
    for (var i = 0; i < themeTailSlots; i++) {
      final at = themeOff + 16 + 8 * (themePtrSlots + i);
      if (ShellWriter.readU32Bytes(raw, at) != 0) throw PackError('主题表尾槽 $i 计数不是 0');
      if (ShellWriter.readU32Bytes(raw, at + 4) != tailRec) {
        throw PackError('主题表尾记录指针 $i 不对');
      }
    }
    if (ShellWriter.readU32Bytes(raw, recOff) != 0 ||
        ShellWriter.readU32Bytes(raw, recOff + 12) != 0x10 ||
        ShellWriter.readU32Bytes(raw, recOff + 8) != tailRec) {
      throw PackError('记录表首条形状不对');
    }
    if (ShellWriter.readU32Bytes(raw, tailRec) != recUidBase ||
        ShellWriter.readU32Bytes(raw, tailRec + 4) != 0 ||
        ShellWriter.readU32Bytes(raw, tailRec + 8) != 0 ||
        ShellWriter.readU32Bytes(raw, tailRec + 12) != 0) {
      throw PackError('尾标记不对');
    }

    final preview = previewOf(raw);
    final fileRegion = recEnd + preview.length;
    final files = <MapEntry<String, Uint8List>>[];
    var expectOff = fileRegion;
    for (var i = 0; i < n; i++) {
      final at = recOff + 16 * (1 + i);
      if (ShellWriter.readU32Bytes(raw, at) != recUidBase + i) {
        throw PackError('第 ${i + 1} 条记录的槽号不对');
      }
      final off = ShellWriter.readU32Bytes(raw, at + 8);
      final len = ShellWriter.readU32Bytes(raw, at + 12);
      if (off != expectOff) throw PackError('第 ${i + 1} 条记录起点不连续: $off');
      if (off < 0 || off > raw.length || len < blobHdrLen || len > raw.length - off) {
        throw PackError('第 ${i + 1} 条记录越界');
      }
      if (ShellWriter.readU32Bytes(raw, at + 4) != 0) throw PackError('记录保留字段非零');
      final head = ShellWriter.readU32Bytes(raw, off);
      final dlen = head & 0xFFFFFF;
      final plen = head >> 24;
      if (blobHdrLen + plen + dlen != len) throw PackError('第 ${i + 1} 条小头长度对不上');
      for (var k = 4; k < blobHdrLen; k++) {
        if (raw[off + k] != 0) throw PackError('第 ${i + 1} 条小头保留字节非 0');
      }
      final path = ascii.decode(Uint8List.sublistView(raw, off + blobHdrLen, off + blobHdrLen + plen));
      if (path.isEmpty ||
          path.codeUnits.any((c) => c < 32 || c > 126) ||
          path.split('/').any((s) => s.isEmpty || s == '..')) {
        throw PackError('容器路径不合法');
      }
      final data = Uint8List.fromList(raw.sublist(off + blobHdrLen + plen, off + len));
      files.add(MapEntry(path, data));
      expectOff += len;
    }
    if (expectOff != raw.length) throw PackError('文件区结尾多出 ${raw.length - expectOff} 字节');
    if (files.map((e) => e.key).toSet().length != files.length) throw PackError('容器路径重复');

    final zero = _zterm(raw, nameOff, nameMax);
    final themeZero = _zterm(raw, themeNameOff, themeNameMax);
    return ShellParsed(
      files: files,
      device: ShellWriter.readU32Bytes(raw, 4),
      pkg: ascii.decode(Uint8List.sublistView(raw, pkgOff, pkgOff + pkgLen)),
      displayName: utf8.decode(Uint8List.sublistView(raw, nameOff, nameOff + zero)),
      themeName: utf8.decode(Uint8List.sublistView(raw, themeNameOff, themeNameOff + themeZero)),
      preview: preview,
      fileRegion: fileRegion,
    );
  }

  static int _zterm(Uint8List raw, int off, int max) {
    for (var i = 0; i < max; i++) {
      if (raw[off + i] == 0) return i;
    }
    return max;
  }
}

class ShellEntry {
  ShellEntry(this.path, this.data);
  final String path;
  final Uint8List data;
}

class ShellParsed {
  ShellParsed({
    required this.files,
    required this.device,
    required this.pkg,
    required this.displayName,
    required this.themeName,
    required this.preview,
    required this.fileRegion,
  });

  final List<MapEntry<String, Uint8List>> files;

  /// 容器版本号(0x04)。真包 0x10000, p67 图标包 0x00010107 —— 重建时必须原样带回,
  /// 否则固件会当成另一个容器版本。
  final int device;
  final String pkg;
  final String displayName;
  final String themeName;
  final Uint8List preview;
  final int fileRegion;
}