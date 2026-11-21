import 'dart:convert';
import 'dart:typed_data';

import '../icon/lvgl_icon_codec.dart';
import '../icon/nine_icon_spec.dart';
import 'cipk.dart';
import 'nine_shell_builder.dart';
import 'pack_builders.dart';
import 'shell_writer.dart';

/// 9 Pro 的独立素材导入协议: 一个 64000 字节分片的字体包, 或一个多槽图标包。
///
/// 与 10 Pro 那条路的差别不只是容器格式:
/// - 9 Pro 的素材全部走 _lua/_Lua/*.dat, 没有 CIPK, 每片长度只有 16 位;
/// - 清单写在 _lua/_Lua/main.lua 的 local M=__N67_MANIFEST__ 处, 由模板
///   pack_n67/importer.lua.in 消费;
/// - 包名必须同时避开主包号与 9 Pro 的主包号 990000000028。
abstract final class NinePackBuilder {
  static const String mainPkg = '990000000028';
  static const int chunkBytes = 64000;
  static const int maxFontBytes = 8000000;
  static const String manifestPlaceholder = '__N67_MANIFEST__';

  /// 9 Pro 字体包: 按 64000 字节切片, 片名 font-000.dat / font-001.dat ...
  static FontPackResult font({
    required String template,
    required FontPackInputs inputs,
    required Uint8List preview,
  }) {
    _checkLabel(inputs.label);
    final Uint8List font = inputs.font;
    if (font.length < 12 || font.length > maxFontBytes) {
      throw PackError('9 Pro 需要不超过 8 MB 的独立 TrueType 字体');
    }
    if (!(font[0] == 0 && font[1] == 1 && font[2] == 0 && font[3] == 0)) {
      throw PackError('9 Pro 需要独立的 TrueType(0x00010000) 字体');
    }
    final List<NineShellEntry> leaves = <NineShellEntry>[];
    for (var i = 0, at = 0; at < font.length; i++, at += chunkBytes) {
      final int end = (at + chunkBytes < font.length) ? at + chunkBytes : font.length;
      leaves.add(NineShellEntry(
        '_lua/_Lua/font-' + i.toString().padLeft(3, '0') + '.dat',
        Uint8List.sublistView(font, at, end),
      ));
    }
    final String pkg = inputs.pkgName ??
        ShellWriter.pkgFor(_concat(<Uint8List>[
          font,
          Uint8List.fromList(utf8.encode(inputs.label)),
        ]));
    final Uint8List out = _build(
      template: template,
      kind: 'font',
      pkg: pkg,
      label: inputs.label,
      title: inputs.title,
      display: inputs.packName,
      leaves: leaves,
      stems: const <String>[],
      preview: preview,
    );
    return FontPackResult(out, pkg, inputs.packName);
  }

  /// 9 Pro 图标包: 每个槽位一片 stem.dat, 清单里带 stem 与尺寸。
  static IconPackResult icons({
    required String template,
    required IconPackInputs inputs,
    required Uint8List preview,
  }) {
    _checkLabel(inputs.short);
    final List<CipkIcon> icons = <CipkIcon>[...inputs.files]
      ..sort((CipkIcon a, CipkIcon b) => a.stem.compareTo(b.stem));
    if (icons.isEmpty || icons.length > NineIconSpec.slots.length) {
      throw PackError('9 Pro 图标数必须是 1..' + NineIconSpec.slots.length.toString());
    }
    if (icons.map((CipkIcon i) => i.stem).toSet().length != icons.length) {
      throw PackError('9 Pro 图标里有重复槽位');
    }
    final List<_Slot> info = <_Slot>[];
    for (final CipkIcon icon in icons) {
      _Slot? hit;
      for (final _Slot s in _nineSlots) {
        if (s.stem == icon.stem) {
          hit = s;
          break;
        }
      }
      if (hit == null) throw PackError('9 Pro 没有图标槽: ' + icon.stem);
      final LvglImage image = LvglIconCodec.decode(icon.data);
      if (image.width != hit.width || image.height != hit.height) {
        throw PackError(hit.stem +
            ' 尺寸应为 ' +
            hit.width.toString() +
            ' x ' +
            hit.height.toString() +
            ', 实际 ' +
            image.width.toString() +
            ' x ' +
            image.height.toString());
      }
      if (icon.data.length != 4 + hit.width * hit.height * 4) {
        throw PackError(hit.stem + ' 的字节数与尺寸不符');
      }
      info.add(hit);
    }
    // 原始包身份算法支持更多素材, CIPK 仅用于哈希(与 Kotlin 版逐字节一致)。
    final BytesBuilder identity = BytesBuilder(copy: false);
    identity.add(<int>[0x43, 0x49, 0x50, 0x4B]); // CIPK
    identity.add(_u32(icons.length));
    for (final CipkIcon icon in icons) {
      final List<int> name = utf8.encode(icon.fileName);
      identity.add(_u32(icon.data.length));
      identity.addByte(name.length);
      identity.add(name);
      identity.add(icon.data);
    }
    final String pkg = inputs.pkgName ??
        ShellWriter.pkgFor(_concat(<Uint8List>[
          identity.takeBytes(),
          Uint8List.fromList(utf8.encode(inputs.short)),
        ]));
    final List<NineShellEntry> leaves = <NineShellEntry>[
      for (final CipkIcon i in icons) NineShellEntry('_lua/_Lua/' + i.stem + '.dat', i.data),
    ];
    final Uint8List out = _build(
      template: template,
      kind: 'icons',
      pkg: pkg,
      label: inputs.short,
      title: inputs.title,
      display: inputs.packName,
      leaves: leaves,
      stems: <String>[for (final CipkIcon i in icons) i.stem],
      preview: preview,
    );
    return IconPackResult(out, pkg, inputs.packName, icons.length);
  }

  static final List<_Slot> _nineSlots = <_Slot>[
    for (final slot in NineIconSpec.slots)
      _Slot(slot.stem, slot.fileStem, slot.width, slot.height),
  ];

  static void _checkLabel(String label) {
    final List<int> bytes = utf8.encode(label);
    if (bytes.isEmpty || bytes.length > 12) {
      throw PackError('9 Pro 素材短名须为 1..12 个 UTF-8 字节');
    }
    for (final int c in bytes) {
      if (c <= 32 || c == 127) {
        throw PackError('9 Pro 素材短名不能含空格或控制字符');
      }
    }
  }

  static Uint8List _build({
    required String template,
    required String kind,
    required String pkg,
    required String label,
    required String title,
    required String display,
    required List<NineShellEntry> leaves,
    required List<String> stems,
    required Uint8List preview,
  }) {
    ShellWriter.checkPkg(pkg);
    ShellWriter.checkPkgAgainst(pkg);
    if (pkg == mainPkg) throw PackError('表盘 ID 撞上了 9 Pro 主包号 ' + pkg);
    ShellWriter.checkName(display);
    if (title.isEmpty || title.length > 256) throw PackError('标题为空或过长');
    for (final int c in title.codeUnits) {
      if (c < 32) throw PackError('标题不能含控制字符');
    }
    final List<String> rows = <String>[];
    for (var i = 0; i < leaves.length; i++) {
      final NineShellEntry e = leaves[i];
      final StringBuffer row = StringBuffer('{src=');
      row.write(_quoted(e.path.split('/').last));
      row.write(',bytes=');
      row.write(e.data.length);
      row.write(',sum=');
      var sum = 0;
      for (final int b in e.data) {
        sum += b & 0xFF;
      }
      row.write(sum);
      if (kind == 'icons') {
        _Slot? hit;
        for (final _Slot s in _nineSlots) {
          if (s.stem == stems[i]) {
            hit = s;
            break;
          }
        }
        if (hit == null) throw PackError('9 Pro 没有图标槽: ' + stems[i]);
        row.write(',stem=');
        row.write(_quoted(stems[i]));
        row.write(',width=');
        row.write(hit.width);
        row.write(',height=');
        row.write(hit.height);
      }
      row.write('}');
      rows.add(row.toString());
    }
    // 清单里的 stems 是整台机可能出现的全量槽位, 不是本次选中的那些:
    // 设备侧靠它判断哪些图标还有旧文件占着位置。
    final List<String> allStems = <String>[
      for (final slot in NineIconSpec.slots) slot.fileStem,
      'ctrl_phone_conn',
      'ctrl_phone_disconn',
    ];
    final String manifest = '{kind=' +
        _quoted(kind) +
        ',pkg=' +
        _quoted(pkg) +
        ',label=' +
        _quoted(label) +
        ',title=' +
        _quoted(title) +
        ',stems={' +
        allStems.map(_quoted).join(',') +
        '},entries={' +
        rows.join(',\n') +
        '}}';
    final String norm = template.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final int hits = manifestPlaceholder.allMatches(norm).length;
    if (hits != 1) {
      throw PackError('9 Pro 模板里 ' +
          manifestPlaceholder +
          ' 应恰好出现 1 次, 实际 ' +
          hits.toString() +
          ' 次');
    }
    final Uint8List lua = Uint8List.fromList(
      utf8.encode(norm.replaceFirst(manifestPlaceholder, manifest)),
    );
    if (lua.length > 65535) throw PackError('9 Pro 清单超过 65535 字节');
    final List<NineShellEntry> entries = <NineShellEntry>[
      NineShellEntry('_lua/_Lua/main.lua', lua),
      ...leaves,
    ];
    final Uint8List out = NineShellBuilder.build(
      files: entries,
      pkgName: pkg,
      displayName: display,
      preview: preview,
    );
    final NineShellParsed back = NineShellBuilder.parse(out);
    if (back.pkg != pkg) throw PackError('包名写错: ' + back.pkg);
    if (back.displayName != display) throw PackError('表盘名写错: ' + back.displayName);
    if (back.files.length != entries.length) throw PackError('槽数不符');
    for (var i = 0; i < entries.length; i++) {
      if (back.files[i].key != entries[i].path) {
        throw PackError('第 ' + (i + 1).toString() + ' 槽路径不符');
      }
      if (!bytesEqual(back.files[i].value, entries[i].data)) {
        throw PackError('第 ' + (i + 1).toString() + ' 槽内容不一致: ' + entries[i].path);
      }
    }
    return out;
  }

  static String _quoted(String text) => '"' + luaQuote(text) + '"';

  static Uint8List _u32(int v) => Uint8List.fromList(<int>[
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF,
      ]);

  static Uint8List _concat(List<Uint8List> parts) {
    final BytesBuilder b = BytesBuilder(copy: false);
    for (final Uint8List p in parts) {
      b.add(p);
    }
    return b.takeBytes();
  }
}

/// 9 Pro 某个槽位的尺寸与文件 stem。
class _Slot {
  const _Slot(this.stem, this.fileStem, this.width, this.height);

  final String stem;
  final String fileStem;
  final int width;
  final int height;
}
