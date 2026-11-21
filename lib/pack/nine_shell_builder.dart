import 'dart:convert';
import 'dart:typed_data';

import 'shell_writer.dart';

/// 9 Pro 容器的 16 位文件长度与独立记录表布局。
///
/// 与 10 Pro 的 [ShellBuilder] 差别: 文件长度只有 16 位、没有 `plen` 高位,
/// 记录表从 0x158 起、每条记录前 4 字节是 `REC_UID_BASE | 序号`。
class NineShellBuilder {
  static const int magic = 0x1234A55A;
  static const int deviceCode = 0x10000;
  static const int previewTag = 0x410;
  static const int previewHdr = 12;
  static const int recOff = 0x148;
  static const int luaTable = 0x158;
  static const int pkgOff = 0x28;
  static const int pkgLen = 12;
  static const int nameOff = 0x68;
  static const int nameMax = 64;
  static const int themeOff = 0xA8;
  static const int themeEnd = 0x148;
  static const int fileCntOff = 0xD8;
  static const int themeNameOff = 0x100;
  static const int themeNameMax = 0x48;
  static const int recUidBase = 0x05000000;
  static const int blobHdrLen = 20;
  static const String defaultThemeName = '格式1';

  /// 记录表结束位置(= 预览块起点 - 16 字节的尾巴)。
  static int recordEnd(int fileCount) => luaTable + 16 * fileCount + 16;

  static void checkPreview(Uint8List preview) {
    if (preview.length < 12) throw PackError('预览块太短');
    if (ShellWriter.readU32Bytes(preview, 0) != previewTag) {
      throw PackError('预览块标签不匹配');
    }
    if (ShellWriter.readU32Bytes(preview, 8) != preview.length - 12) {
      throw PackError('预览块长度字段与内容不符');
    }
    final int w = preview[4] | (preview[5] << 8);
    final int h = preview[6] | (preview[7] << 8);
    if (w != 336 || h != 480) throw PackError('预览块尺寸必须是 336x480');
  }

  static Uint8List build({
    required List<NineShellEntry> files,
    required String pkgName,
    required String displayName,
    required Uint8List preview,
    String themeName = defaultThemeName,
    int device = deviceCode,
  }) {
    ShellWriter.checkPkg(pkgName);
    ShellWriter.checkPkgAgainst(pkgName);
    ShellWriter.checkName(displayName);
    if (device != deviceCode) throw PackError('9 Pro 容器版本不对: 0x${device.toRadixString(16)}');
    if (files.isEmpty || files.length > 128) throw PackError('文件数必须是 1..128');
    if (files.map((NineShellEntry e) => e.path).toSet().length != files.length) {
      throw PackError('容器里出现了重复路径');
    }
    checkPreview(preview);

    final int end = luaTable + files.length * 16;
    final int previewAt = end + 16;
    final Uint8List head = Uint8List(previewAt);
    void w(int at, int value) => ShellWriter.writeU32To(head, at, value);
    w(0, magic);
    w(4, deviceCode);
    w(0x10, 0x800);
    w(0x14, 0x10000);
    w(0x1C, 1);
    head.setRange(pkgOff, pkgOff + pkgLen, _ascii(pkgName));
    final Uint8List name = _utf8(displayName, 63, '显示名');
    head.setRange(nameOff, nameOff + name.length, name);
    final Uint8List theme = _utf8(themeName, themeNameMax - 1, '主题名');
    head.setRange(themeNameOff, themeNameOff + theme.length, theme);
    w(0x20, previewAt);
    w(themeOff, 0x80000000);
    w(0xAC, previewAt);
    w(0xB0, 1);
    w(0xB4, recOff);
    for (final int at in <int>[0xB8, 0xC0, 0xC8, 0xD0, 0xE0, 0xE8, 0xF0, 0xF8]) {
      w(at + 4, end);
    }
    w(fileCntOff, files.length);
    w(0xDC, luaTable);
    w(recOff + 8, end);
    w(recOff + 12, 16);
    w(end, recUidBase);

    int pos = previewAt + preview.length;
    final List<Uint8List> blobs = <Uint8List>[];
    for (int i = 0; i < files.length; i++) {
      final NineShellEntry entry = files[i];
      if (!entry.path.startsWith('_lua/_Lua/') ||
          entry.path.codeUnits.any((int c) => c < 32 || c > 126)) {
        throw PackError('9 Pro 素材路径必须是 _lua/_Lua/ 下的可打印 ASCII');
      }
      final Uint8List name = _ascii(entry.path);
      if (name.isEmpty || name.length > 120) throw PackError('素材路径长度必须在 1..120 字节');
      if (entry.data.length > 65535) throw PackError('9 Pro 单个素材不能超过 64 KB');
      final Uint8List blob = Uint8List(blobHdrLen + name.length + entry.data.length);
      blob[0] = entry.data.length & 0xFF;
      blob[1] = (entry.data.length >> 8) & 0xFF;
      blob[3] = name.length;
      blob.setRange(blobHdrLen, blobHdrLen + name.length, name);
      blob.setRange(blobHdrLen + name.length, blob.length, entry.data);
      final int at = luaTable + i * 16;
      w(at, recUidBase | i);
      w(at + 8, pos);
      w(at + 12, blob.length);
      pos += blob.length;
      blobs.add(blob);
    }

    final Uint8List out = Uint8List(pos);
    out.setRange(0, head.length, head);
    out.setRange(head.length, head.length + preview.length, preview);
    int cursor = head.length + preview.length;
    for (final Uint8List blob in blobs) {
      out.setRange(cursor, cursor + blob.length, blob);
      cursor += blob.length;
    }
    return out;
  }

  /// 从容器里取预览块(12 字节头 + 数据)。
  static Uint8List previewOf(Uint8List raw) {
    final int at = ShellWriter.readU32Bytes(raw, 0x20);
    if (at < recOff || at > raw.length - 12) throw PackError('预览块偏移越界');
    final int size = ShellWriter.readU32Bytes(raw, at + 8);
    if (size < 0 || size > raw.length - at - 12) throw PackError('预览块长度越界');
    final Uint8List preview = Uint8List.sublistView(raw, at, at + 12 + size);
    checkPreview(preview);
    return preview;
  }

  static NineShellParsed parse(Uint8List raw) {
    if (raw.length < luaTable + 32 || raw.length > 32000000) {
      throw PackError('这不是 9 Pro 投递包');
    }
    if (ShellWriter.readU32Bytes(raw, 0) != magic) throw PackError('容器魔数不匹配');
    if (ShellWriter.readU32Bytes(raw, 4) != deviceCode) throw PackError('容器机型不匹配');
    final int count = ShellWriter.readU32Bytes(raw, fileCntOff);
    final int table = ShellWriter.readU32Bytes(raw, 0xDC);
    if (count < 1 || count > 128 || table != luaTable) throw PackError('记录表不合法');
    final int end = table + 16 * count;
    if (end + 16 > raw.length || ShellWriter.readU32Bytes(raw, 0x20) != end + 16) {
      throw PackError('预览块起点与记录表不自洽');
    }
    if (ShellWriter.readU32Bytes(raw, recOff + 8) != end ||
        ShellWriter.readU32Bytes(raw, end) != recUidBase) {
      throw PackError('记录表结尾标记不匹配');
    }
    final Uint8List preview = previewOf(raw);
    int next = end + 16 + preview.length;
    final int region = next;
    final List<MapEntry<String, Uint8List>> files = <MapEntry<String, Uint8List>>[];
    for (int i = 0; i < count; i++) {
      final int at = table + i * 16;
      if (ShellWriter.readU32Bytes(raw, at) != (recUidBase | i) ||
          ShellWriter.readU32Bytes(raw, at + 4) != 0) {
        throw PackError('第 ${i + 1} 条记录头不合法');
      }
      final int off = ShellWriter.readU32Bytes(raw, at + 8);
      final int len = ShellWriter.readU32Bytes(raw, at + 12);
      if (off != next || off > raw.length || len < 21 || len > raw.length - off) {
        throw PackError('第 ${i + 1} 条记录偏移越界');
      }
      final int size = raw[off] | (raw[off + 1] << 8);
      final int nameLen = raw[off + 3];
      if (nameLen < 1 || nameLen > 120 || raw[off + 2] != 0 || len != blobHdrLen + nameLen + size) {
        throw PackError('第 ${i + 1} 条记录长度不自洽');
      }
      for (int k = 4; k < blobHdrLen; k++) {
        if (raw[off + k] != 0) throw PackError('记录头保留字节应为 0');
      }
      final String name = String.fromCharCodes(
        Uint8List.sublistView(raw, off + blobHdrLen, off + blobHdrLen + nameLen),
      );
      if (!name.startsWith('_lua/_Lua/') ||
          name.codeUnits.any((int c) => c < 32 || c > 126) ||
          name.split('/').any((String s) => s.isEmpty || s == '..')) {
        throw PackError('素材路径不合法: $name');
      }
      next += len;
      files.add(MapEntry<String, Uint8List>(
        name,
        Uint8List.sublistView(raw, off + blobHdrLen + nameLen, next),
      ));
    }
    if (next != raw.length) throw PackError('容器尾部有未声明的数据');
    if (files.map((MapEntry<String, Uint8List> e) => e.key).toSet().length != count) {
      throw PackError('容器里出现了重复路径');
    }
    return NineShellParsed(
      files: files,
      pkg: String.fromCharCodes(Uint8List.sublistView(raw, pkgOff, pkgOff + pkgLen)),
      displayName: _decodeUtf8(Uint8List.sublistView(raw, nameOff, nameOff + nameMax)),
      themeName: _decodeUtf8(Uint8List.sublistView(raw, themeNameOff, themeNameOff + themeNameMax)),
      preview: preview,
      fileRegion: region,
    );
  }

  static String _decodeUtf8(Uint8List raw) {
    int n = raw.length;
    for (int i = 0; i < raw.length; i++) {
      if (raw[i] == 0) {
        n = i;
        break;
      }
    }
    return utf8.decode(Uint8List.sublistView(raw, 0, n), allowMalformed: true);
  }

  static Uint8List _ascii(String s) {
    final Uint8List out = Uint8List(s.length);
    for (int i = 0; i < s.length; i++) {
      final int c = s.codeUnitAt(i);
      if (c > 126) throw PackError('这里只能是 ASCII: $s');
      out[i] = c;
    }
    return out;
  }

  static Uint8List _utf8(String s, int max, String what) {
    final Uint8List bytes = Uint8List.fromList(utf8.encode(s));
    if (bytes.length > max) throw PackError('$what 太长(${bytes.length} 字节, 上限 $max)');
    return bytes;
  }
}

/// 9 Pro 容器里的一条素材。
class NineShellEntry {
  const NineShellEntry(this.path, this.data);

  final String path;
  final Uint8List data;
}

/// [NineShellBuilder.parse] 的结果。
class NineShellParsed {
  const NineShellParsed({
    required this.files,
    required this.pkg,
    required this.displayName,
    required this.themeName,
    required this.preview,
    required this.fileRegion,
  });

  final List<MapEntry<String, Uint8List>> files;
  final String pkg;
  final String displayName;
  final String themeName;
  final Uint8List preview;
  final int fileRegion;
}

/// 9 Pro 素材包的容量口径。
abstract final class NinePack {
  /// 9 Pro 主包号, 撞上就判重复安装。
  static const String mainPkg = '990000000028';

  /// 字体分块的单片字节数。
  static const int chunkBytes = 64000;

  /// 9 Pro 字体总量上限。
  static const int maxFontBytes = 8000000;
}
