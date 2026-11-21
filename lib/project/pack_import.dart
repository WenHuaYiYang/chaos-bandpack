import 'dart:convert';
import 'dart:typed_data';

import '../font/sfnt.dart';
import '../icon/animated_icons.dart';
import '../icon/device_target.dart';
import '../icon/icon_spec.dart';
import '../icon/lvgl_icon_codec.dart';
import '../icon/nine_icon_spec.dart';
import '../pack/cipk.dart';
import '../pack/nine_shell_builder.dart';
import '../pack/shell_builder.dart';
import '../pack/shell_writer.dart';
import 'chaos_project.dart';
import 'lua_literal.dart';

/// 从已投递的容器里反推工程。
///
/// 只提取素材字节与清单里的**字面量**, 不加载、不执行容器里的 Lua(设备侧脚本
/// 在手机上跑等于远程代码执行), 也不加载 .ko。
abstract final class PackImport {
  /// 10 Pro 图标包可能在两个根下(旧版 `_lua/iconpack/`, 现行
  /// `_lua/xiaomi-band-10-pro/`)。
  static const List<String> _iconRoots = <String>[
    '_lua/iconpack/',
    '_lua/xiaomi-band-10-pro/',
  ];

  /// 读一个投递容器, 还原成可继续编辑的工程。
  static ChaosProject read(Uint8List bytes) {
    if (bytes.length > ProjectCodec.maxBytes) throw const ImportError('投递包超过 32 MB');

    ShellParsed? ten;
    try {
      ten = ShellBuilder.parse(bytes);
    } on PackError {
      ten = null;
    }
    final NineShellParsed? nine = ten == null ? NineShellBuilder.parse(bytes) : null;
    final List<MapEntry<String, Uint8List>> files =
        ten?.files ?? nine!.files;
    final String pkg = ten?.pkg ?? nine!.pkg;
    final String display = ten?.displayName ?? nine!.displayName;
    ShellWriter.checkPkg(pkg);

    final List<String> packPaths = <String>[
      for (final String root in _iconRoots) '${root}pack.bin',
    ];
    final List<MapEntry<String, Uint8List>> packs = files
        .where((MapEntry<String, Uint8List> e) => packPaths.contains(e.key))
        .toList();
    if (packs.length > 1) throw const ImportError('容器包含重复的图标载荷');

    if (packs.isNotEmpty) {
      final MapEntry<String, Uint8List> cipk = packs.single;
      final String base = cipk.key.substring(0, cipk.key.length - 'pack.bin'.length);
      final String? lua = _find(files, '${base}main.lua');
      if (lua == null) throw const ImportError('缺少图标投递清单');
      final PackInfo info = PackInfo(
        short: _localString(lua, 'PACK_NAME') ?? 'MyIcons',
        display: display,
        title: _localString(lua, 'PACK_TITLE') ?? '图标投递',
        pkg: pkg,
      );
      final List<CipkIcon> icons = Cipk.parse(cipk.value);
      AnimatedIcons.validateFiles(icons);
      final Map<String, Uint8List> images = <String, Uint8List>{
        for (final CipkIcon icon in icons)
          if (icon.stem != 'animations') icon.stem: icon.data,
      };
      // p67 的勿扰动画(160x124)是静态图的派生物: 老包里如果只剩动画, 就从
      // 动画首帧贴回 64x64 的静态槽, 否则用户一存盘就把静态图弄丢了。
      if (!images.containsKey('ctrl_disturb')) {
        final Uint8List? animation = images['ctrl_dnd'];
        if (animation != null) {
          final LvglImage image = LvglIconCodec.decode(animation);
          if (image.width != 160 || image.height != 124) {
            throw const ImportError('勿扰动画尺寸不支持');
          }
          final List<int> statics = List<int>.filled(64 * 64, 0);
          for (int y = 0; y < 64; y++) {
            for (int x = 0; x < 64; x++) {
              statics[y * 64 + x] = image.pixels[(y + 30) * 160 + 48 + x];
            }
          }
          images['ctrl_disturb'] = LvglIconCodec.bgra(statics, 64, 64);
        }
      }
      return ChaosProject(
        device: DeviceTarget.tenPro,
        icons: IconProject(info: info, images: images),
      );
    }

    final Uint8List? font = _findBytes(files, '_lua/fontpack/font.ttf');
    if (font != null) {
      Sfnt(font);
      final String? lua = _find(files, '_lua/fontpack/main.lua');
      if (lua == null) throw const ImportError('缺少字体投递清单');
      final PackInfo info = PackInfo(
        short: _localString(lua, 'FONT_NAME') ?? 'font',
        display: display,
        title: _localString(lua, 'PACK_TITLE') ?? '字体投递',
        pkg: pkg,
      );
      return ChaosProject(
        device: DeviceTarget.tenPro,
        font: FontProject(
          info: info,
          sourceName: '$display.ttf',
          source: font,
          preserve: true,
        ),
      );
    }

    return _readNine(files, pkg, display);
  }

  static Uint8List? _findBytes(
      List<MapEntry<String, Uint8List>> files, String path) {
    for (final MapEntry<String, Uint8List> e in files) {
      if (e.key == path) return e.value;
    }
    return null;
  }

  static String? _find(
      List<MapEntry<String, Uint8List>> files, String path) {
    final Uint8List? bytes = _findBytes(files, path);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  /// 取 `local KEY = '...'` 的字面量。
  ///
  /// 刻意不写正则: 引号字符类在 Dart 里要反两层转义, 读起来比手写扫描还危险,
  /// 而这里只认"行首 local KEY = <字符串>"这一种形态, 逐字符扫更直白。
  static String? _localString(String text, String key) {
    final String head = 'local $key';
    for (final String line in const LineSplitter().convert(text)) {
      final String row = line.trimLeft();
      if (!row.startsWith(head)) continue;
      final int eq = row.indexOf('=', head.length);
      if (eq < 0) continue;
      int quote = -1;
      for (int i = eq + 1; i < row.length; i++) {
        final int c = row.codeUnitAt(i);
        if (c == 0x22 || c == 0x27) {
          quote = i;
          break;
        }
        if (c != 0x20 && c != 0x09) break;
      }
      if (quote < 0) continue;
      final Object? value = LuaLiteral(row.substring(quote)).value();
      if (value is String) return value;
    }
    return null;
  }

  static ChaosProject _readNine(
    List<MapEntry<String, Uint8List>> files,
    String pkg,
    String display,
  ) {
    final String? lua = _find(files, '_lua/_Lua/main.lua');
    if (lua == null) throw const ImportError('这不是可编辑的 Chaos 图标或字体投递包');
    final RegExpMatch? start =
        RegExp(r'(?m)^local\s+M\s*=\s*\{').firstMatch(lua);
    if (start == null) {
      throw const ImportError('这是主安装包或其他表盘，请导入图标 / 字体投递包');
    }
    final Object? manifest = LuaLiteral(lua, start.end - 1).value();
    if (manifest is! Map<String, Object?>) {
      throw const ImportError('投递清单类型不合法');
    }
    String text(String key) {
      final Object? v = manifest[key];
      if (v is! String) throw ImportError('投递清单缺少 $key');
      return v;
    }

    if (text('pkg') != pkg) throw const ImportError('清单与容器的表盘 ID 不一致');
    final PackInfo info =
        PackInfo(short: text('label'), display: display, title: text('title'), pkg: pkg);
    final Object? entryRows = manifest['entries'];
    if (entryRows is! List<Object?>) throw const ImportError('投递清单缺少素材');
    if (entryRows.isEmpty || entryRows.length > 126) {
      throw const ImportError('投递清单素材数量不合法');
    }
    final Map<String, Uint8List> leaves = <String, Uint8List>{};
    for (final MapEntry<String, Uint8List> e in files) {
      if (e.key != '_lua/_Lua/main.lua') leaves[e.key] = e.value;
    }

    Uint8List payload(Object? element) {
      final Map<String, Object?> row = element as Map<String, Object?>;
      final Object? name = row['src'];
      if (name is! String || !RegExp(r'^[a-z0-9_-]+\.dat$').hasMatch(name)) {
        throw const ImportError('素材名不合法');
      }
      final Uint8List? data = leaves.remove('_lua/_Lua/$name');
      if (data == null) throw ImportError('素材缺失或重复：$name');
      int sum = 0;
      for (final int b in data) {
        sum += b;
      }
      if (row['bytes'] != data.length || row['sum'] != sum) {
        throw ImportError('素材校验失败：$name');
      }
      return data;
    }

    final String kind = text('kind');
    if (kind == 'icons') {
      final Map<String, Uint8List> images = <String, Uint8List>{};
      for (final Object? element in entryRows) {
        final Map<String, Object?> row = element as Map<String, Object?>;
        final Object? fileStem = row['stem'];
        if (fileStem is! String) throw const ImportError('图标槽位缺失');
        IconSpecSlot? slot;
        for (final IconSpecSlot s in NineIconSpec.slots) {
          if (s.fileStem == fileStem) {
            slot = s;
            break;
          }
        }
        if (slot == null &&
            fileStem != 'ctrl_phone_conn' &&
            fileStem != 'ctrl_phone_disconn') {
          throw ImportError('9 Pro 图标槽位未知：$fileStem');
        }
        final Uint8List data = payload(element);
        final LvglImage image = LvglIconCodec.decode(data);
        final int width = slot?.width ?? 48;
        final int height = slot?.height ?? 48;
        if (image.width != width ||
            image.height != height ||
            row['width'] != width ||
            row['height'] != height) {
          throw ImportError('图标尺寸不匹配：$fileStem');
        }
        if (data.length != 4 + width * height * 4) {
          throw ImportError('图标数据长度不符：$fileStem');
        }
        final String key = slot?.stem ?? fileStem;
        if (images.containsKey(key)) throw const ImportError('图标槽位重复');
        images[key] = data;
      }
      return ChaosProject(
        device: DeviceTarget.ninePro,
        icons: IconProject(info: info, images: images),
      );
    }

    if (kind == 'font') {
      for (int i = 0; i < entryRows.length; i++) {
        final Map<String, Object?> row = entryRows[i] as Map<String, Object?>;
        if (row['src'] != 'font-${i.toString().padLeft(3, '0')}.dat') {
          throw const ImportError('字体分块顺序不完整');
        }
      }
      final BytesBuilder output = BytesBuilder(copy: false);
      for (final Object? element in entryRows) {
        final Uint8List data = payload(element);
        if (data.isEmpty ||
            data.length > NinePack.chunkBytes ||
            output.length + data.length > NinePack.maxFontBytes) {
          throw const ImportError('字体分块超出容量');
        }
        output.add(data);
      }
      final Uint8List source = output.takeBytes();
      Sfnt(source);
      return ChaosProject(
        device: DeviceTarget.ninePro,
        font: FontProject(
          info: info,
          sourceName: '$display.ttf',
          source: source,
          preserve: true,
        ),
      );
    }

    throw const ImportError('投递素材类型不支持');
  }
}
