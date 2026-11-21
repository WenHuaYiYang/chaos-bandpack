import 'dart:convert';
import 'dart:typed_data';

/// 图标包容器(CIPK)—— 手环侧 `icon_pack.lua` 按这个格式解包, 两侧必须逐字节一致:
///
/// ```
/// [4 字节 'CIPK'][u32 张数]
/// 张数 次: [u32 数据长度][u8 名字长度][名字][数据]
/// ```
///
/// 名字形如 `<stem>.bin`(ASCII, `^[A-Za-z0-9_]+\.bin$`, 64 字节以内); 手环只认
/// 内核桌面表与系统资源重定向表中的 stem。
class Cipk {
  static const List<int> magic = [0x43, 0x49, 0x50, 0x4B]; // CIPK
  static const int nameMax = 64;
  static const int iconLenMax = 0x80000;
  static const int animationLenMax = 0x100000;
  static const int countMax = 256;
  static const int totalMax = 0xFFFFFF;

  static final RegExp _nameRe = RegExp(r'^[A-Za-z0-9_]+\.bin$');

  /// 一张图标: stem(不带扩展名) + 按槽位规格转换的图标 bin
  static CipkIcon icon(String stem, Uint8List data) => CipkIcon(stem, data);

  static int limitFor(String fileName) =>
      fileName.toLowerCase().endsWith('.dgf') ? animationLenMax : iconLenMax;

  static Uint8List build(List<CipkIcon> icons) {
    if (icons.isEmpty) throw CipkError('一张图标都没有, 打不出包');
    if (icons.length > countMax) throw CipkError('图标张数超过上限 $countMax');
    final seen = <String>{};
    var total = 8;
    for (final i in icons) {
      final nb = ascii.encode(i.fileName);
      if (nb.length > nameMax) throw CipkError('图标文件名太长: ${i.fileName}');
      if (!_nameRe.hasMatch(i.fileName)) throw CipkError('图标文件名不合规: ${i.fileName}');
      if (!seen.add(i.stem)) throw CipkError('图标重复: ${i.stem}');
      final limit = limitFor(i.fileName);
      if (i.data.isEmpty || i.data.length > limit) {
        throw CipkError('${i.fileName} 长度 ${i.data.length} 超出上限 $limit');
      }
      total += 5 + nb.length + i.data.length;
    }
    if (total > totalMax) {
      throw CipkError('内部图标包超过 16777215 字节(外容器的 24 位资源长度上限)');
    }
    final out = BytesBuilder(copy: true);
    out.add(magic);
    out.add(u32(icons.length));
    for (final i in icons) {
      final nb = ascii.encode(i.fileName);
      out.add(u32(i.data.length));
      out.addByte(nb.length);
      out.add(nb);
      out.add(i.data);
    }
    final bytes = out.takeBytes();
    if (bytes.length != total) {
      throw CipkError('布局不自洽: 预期 $total 实际 ${bytes.length}');
    }
    return bytes;
  }

  /// 拆开。手环侧与 App 侧各有一份实现, 任一方改了格式这里会立刻发现。
  static List<CipkIcon> parse(Uint8List raw) {
    if (raw.length < 8) throw CipkError('CIPK 太短');
    for (var i = 0; i < 4; i++) {
      if (raw[i] != magic[i]) throw CipkError('CIPK 魔数不对');
    }
    final n = readU32(raw, 4);
    if (n < 1 || n > countMax) throw CipkError('张数非法: $n');
    var off = 8;
    final out = <CipkIcon>[];
    for (var k = 0; k < n; k++) {
      if (off + 5 > raw.length) throw CipkError('第 ${k + 1} 张越界');
      final len = readU32(raw, off);
      final nl = raw[off + 4];
      off += 5;
      if (off + nl + len > raw.length) throw CipkError('第 ${k + 1} 张数据越界');
      final name = ascii.decode(Uint8List.sublistView(raw, off, off + nl), allowInvalid: true);
      off += nl;
      final data = Uint8List.sublistView(raw, off, off + len);
      off += len;
      if (!_nameRe.hasMatch(name)) throw CipkError('图标文件名不合规: $name');
      out.add(CipkIcon(name.substring(0, name.length - 4), Uint8List.fromList(data)));
    }
    if (off != raw.length) throw CipkError('尾部多出 ${raw.length - off} 字节');
    return out;
  }

  static Uint8List u32(int v) => Uint8List.fromList([
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF,
      ]);

  static int readU32(Uint8List b, int o) =>
      (b[o] & 0xFF) | ((b[o + 1] & 0xFF) << 8) | ((b[o + 2] & 0xFF) << 16) | ((b[o + 3] & 0xFF) << 24);
}

class CipkIcon {
  CipkIcon(this.stem, this.data);
  final String stem;
  final Uint8List data;
  String get fileName => '$stem.bin';
}

class CipkError implements Exception {
  CipkError(this.message);
  final String message;
  @override
  String toString() => 'CipkError: $message';
}
