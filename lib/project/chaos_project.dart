import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../font/sfnt.dart';
import '../icon/animated_icons.dart';
import '../icon/device_target.dart';

/// 工程里的一个包: 三个名字 + 可选的包名。
///
/// 与 Kotlin 版 PackInfo 同构。[short] 是投递清单短名, [display] 是手环表盘
/// 列表里的显示名, [title] 是表盘内那行标题, [pkg] 是 12 位表盘 ID(空串表示
/// 由内容推导)。
class PackInfo {
  const PackInfo({
    required this.short,
    required this.display,
    required this.title,
    this.pkg = '',
  });

  final String short;
  final String display;
  final String title;
  final String pkg;

  PackInfo copyWith({String? short, String? display, String? title, String? pkg}) =>
      PackInfo(
        short: short ?? this.short,
        display: display ?? this.display,
        title: title ?? this.title,
        pkg: pkg ?? this.pkg,
      );
}

/// 图标工程: 槽位 -> 源素材字节(未转换; 导出时才按目标型号转换规格)。
class IconProject {
  const IconProject({required this.info, required this.images});

  final PackInfo info;
  final Map<String, Uint8List> images;
}

/// 字体工程: 源字体字节 + 子集化选项。
class FontProject {
  const FontProject({
    required this.info,
    required this.sourceName,
    required this.source,
    this.charset = 'SIMPLIFIED',
    this.normalize = true,
    this.preserve = false,
  });

  final PackInfo info;
  final String sourceName;
  final Uint8List source;
  final String charset;
  final bool normalize;

  /// 导入投递包时置 true: 那份字体已经是设备在用的口径, 不再裁。
  final bool preserve;
}

/// 一个可保存/可打开的工程。
class ChaosProject {
  const ChaosProject({required this.device, this.icons, this.font});

  final DeviceTarget device;
  final IconProject? icons;
  final FontProject? font;
}

/// 工程容器读写: zip + project.json 清单 + 素材。
///
/// 口径与 Kotlin 版 ProjectCodec 完全一致(同一份 .chaosproj 两边都能开):
/// 格式名 `chaos-studio-project`, 当前版本 2(版本 1 也读), 素材按 sha256 校验,
/// 展开总量与条目数都有上限。刻意不做的事: 不执行 Lua、不求值任何表达式。
abstract final class ProjectCodec {
  static const String extension = 'chaosproj';
  static const String format = 'chaos-studio-project';
  static const int version = 2;
  static const int maxBytes = 32000000;
  static const int _maxEntries = 258;
  static const int _maxManifest = 131072;

  static final RegExp _keyRe = RegExp(r'^[A-Za-z0-9_]{1,60}$');
  static final RegExp _imagePath = RegExp(r'^images/[A-Za-z0-9_]{1,60}\.bin$');

  static String hash(Uint8List bytes) => sha256.convert(bytes).toString();

  static void _checkText(String text) {
    if (text.length > 256 || text.codeUnits.any((int c) => c < 32)) {
      throw ProjectError('工程文本过长或包含控制字符');
    }
  }

  static Map<String, Object?> _info(PackInfo info) {
    for (final String s in <String>[info.short, info.display, info.title, info.pkg]) {
      _checkText(s);
    }
    return <String, Object?>{
      'short': info.short,
      'display': info.display,
      'title': info.title,
      'pkg': info.pkg,
    };
  }

  /// 打包成 .chaosproj 字节。
  static Uint8List write(ChaosProject project) {
    if (project.icons == null && project.font == null) {
      throw ProjectError('工程没有素材');
    }
    final Map<String, Uint8List> files = <String, Uint8List>{};
    final Map<String, Object?> manifest = <String, Object?>{
      'format': format,
      'version': version,
      'device': project.device.id,
    };

    final IconProject? icons = project.icons;
    if (icons != null) {
      if (icons.images.length > 256) throw ProjectError('工程图标素材超过 256 个文件');
      AnimatedIcons.validateProject(icons.images);
      final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
      final List<String> keys = icons.images.keys.toList()..sort();
      for (final String stem in keys) {
        if (!_keyRe.hasMatch(stem)) throw ProjectError('素材名不合法：$stem');
        final Uint8List bytes = icons.images[stem]!;
        final String path = 'images/$stem.bin';
        files[path] = bytes;
        rows.add(<String, Object?>{
          'key': stem,
          'path': path,
          'sha256': hash(bytes),
        });
      }
      manifest['icons'] = <String, Object?>{
        'info': _info(icons.info),
        'images': rows,
      };
    }

    final FontProject? font = project.font;
    if (font != null) {
      Sfnt(font.source);
      _checkText(font.sourceName);
      if (font.charset != 'SIMPLIFIED' && font.charset != 'WITH_TRADITIONAL') {
        throw ProjectError('工程字集不支持');
      }
      files['font/source.ttf'] = font.source;
      manifest['font'] = <String, Object?>{
        'info': _info(font.info),
        'name': font.sourceName,
        'charset': font.charset,
        'normalize': font.normalize,
        'preserve': font.preserve,
        'path': 'font/source.ttf',
        'sha256': hash(font.source),
      };
    }

    final Uint8List manifestBytes =
        Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
    if (manifestBytes.length > _maxManifest) throw ProjectError('工程清单过大');
    files['project.json'] = manifestBytes;

    int total = 0;
    for (final Uint8List b in files.values) {
      total += b.length;
    }
    if (files.length > _maxEntries || total > maxBytes) {
      throw ProjectError('工程超过 32 MB');
    }

    // 时间戳固定为 1980-01-01(zip 纪元起点): 同样的输入必须打出同样的字节,
    // 否则"两份工程逐字节相同"这种断言就没法测。
    final Archive archive = Archive();
    final List<String> names = files.keys.toList()..sort();
    for (final String name in names) {
      final Uint8List data = files[name]!;
      final ArchiveFile entry = ArchiveFile(name, data.length, data);
      entry.lastModTime = 0;
      archive.addFile(entry);
    }
    final List<int>? out = ZipEncoder().encode(archive);
    if (out == null) throw ProjectError('工程打包失败');
    final Uint8List bytes = Uint8List.fromList(out);
    if (bytes.length > maxBytes) throw ProjectError('工程超过 32 MB');
    return bytes;
  }

  /// 读回工程。[write] 的逆运算, 校验同样严格。
  static ChaosProject read(Uint8List bytes) {
    if (bytes.length < 4 ||
        bytes.length > maxBytes ||
        bytes[0] != 0x50 ||
        bytes[1] != 0x4b) {
      throw ProjectError('不是 Chaos 工程文件');
    }
    final Map<String, Uint8List> files = <String, Uint8List>{};
    int total = 0;
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    for (final ArchiveFile entry in archive.files) {
      final String name = entry.name;
      if (!entry.isFile ||
          files.length >= _maxEntries ||
          files.containsKey(name)) {
        throw ProjectError('工程条目重复或过多');
      }
      if (!(name == 'project.json' ||
          name == 'font/source.ttf' ||
          _imagePath.hasMatch(name))) {
        throw ProjectError('工程路径不合法');
      }
      final Uint8List data =
          entry.content is Uint8List ? entry.content as Uint8List : Uint8List.fromList(entry.content as List<int>);
      total += data.length;
      if (total > maxBytes ||
          (name == 'project.json' && data.length > _maxManifest)) {
        throw ProjectError('工程展开后超过容量限制');
      }
      files[name] = data;
    }

    final Uint8List? raw = files.remove('project.json');
    if (raw == null) throw ProjectError('缺少工程清单');
    final Object? decoded = jsonDecode(utf8.decode(raw));
    if (decoded is! Map<String, Object?>) throw ProjectError('工程清单不是对象');
    final Object? fmt = decoded['format'];
    final Object? ver = decoded['version'];
    if (fmt != format || ver is! int || ver < 1 || ver > version) {
      throw ProjectError('工程格式或版本不支持');
    }
    final DeviceTarget device = DeviceTarget.fromId(decoded['device'] as String);

    Uint8List payload(Map<String, Object?> row) {
      final String path = row['path'] as String;
      final Uint8List? data = files.remove(path);
      if (data == null) throw ProjectError('缺少素材或重复引用：$path');
      if (hash(data) != row['sha256']) throw ProjectError('素材校验失败：$path');
      return data;
    }

    PackInfo readInfo(Map<String, Object?> row) => PackInfo(
          short: row['short'] as String,
          display: row['display'] as String,
          title: row['title'] as String,
          pkg: row['pkg'] as String,
        );

    IconProject? icons;
    final Object? iconsRow = decoded['icons'];
    if (iconsRow is Map<String, Object?>) {
      final Map<String, Uint8List> images = <String, Uint8List>{};
      final List<Object?> list = iconsRow['images'] as List<Object?>;
      if (list.length > 256) throw ProjectError('工程图标素材超过 256 个文件');
      for (final Object? element in list) {
        final Map<String, Object?> item = element as Map<String, Object?>;
        final String stem = item['key'] as String;
        if (!_keyRe.hasMatch(stem) ||
            images.containsKey(stem) ||
            item['path'] != 'images/$stem.bin') {
          throw ProjectError('图标槽位重复或不合法');
        }
        images[stem] = payload(item);
      }
      AnimatedIcons.validateProject(images);
      icons = IconProject(
        info: readInfo(iconsRow['info'] as Map<String, Object?>),
        images: images,
      );
    }

    FontProject? font;
    final Object? fontRow = decoded['font'];
    if (fontRow is Map<String, Object?>) {
      if (fontRow['path'] != 'font/source.ttf') {
        throw ProjectError('工程路径不合法');
      }
      final Uint8List source = payload(fontRow);
      Sfnt(source);
      final String charset = fontRow['charset'] as String;
      if (charset != 'SIMPLIFIED' && charset != 'WITH_TRADITIONAL') {
        throw ProjectError('工程字集不支持');
      }
      font = FontProject(
        info: readInfo(fontRow['info'] as Map<String, Object?>),
        sourceName: fontRow['name'] as String,
        source: source,
        charset: charset,
        normalize: fontRow['normalize'] as bool,
        preserve: fontRow['preserve'] as bool,
      );
    }

    if (files.isNotEmpty || (icons == null && font == null)) {
      throw ProjectError('工程含有未声明素材或没有内容');
    }
    return ChaosProject(device: device, icons: icons, font: font);
  }
}

/// 工程读写错误。
class ProjectError implements Exception {
  const ProjectError(this.message);

  final String message;

  @override
  String toString() => 'ProjectError: $message';
}
