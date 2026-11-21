import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../icon/animated_icons.dart';
import '../icon/device_target.dart';
import '../icon/dgf1.dart';

/// A CHP V1 file contains either one font or a set of icons, never both.
enum BeautyKind { font, icon }

final class BeautyPackError implements Exception {
  const BeautyPackError(this.message);

  final String message;

  @override
  String toString() => 'BeautyPackError: $message';
}

/// Resource-only .chp V1. No I/O, archive extraction, or executable content.
final class BeautyPack {
  factory BeautyPack({
    required BeautyKind kind,
    required DeviceTarget device,
    required String name,
    required Map<String, Uint8List> files,
  }) {
    _validateName(kind, name);
    _validateCount(kind, files.length);
    final names = files.keys.toList()..sort();
    final views = <String, Uint8List>{};
    final seen = <String>{};
    var total = 0;
    for (final leaf in names) {
      final data = files[leaf]!;
      _validateEntry(kind, device, leaf, data.length, seen);
      total += data.length;
      if (total > _maxPayloadBytes) {
        throw const BeautyPackError('美化包素材总长度超过 32 MiB');
      }
      _validateResource(kind, device, leaf, data);
      views[leaf] = data;
    }
    _validateAnimationSet(views);
    return BeautyPack._(kind, device, name, _snapshot(views));
  }

  BeautyPack._(this.kind, this.device, this.name, this.files);

  final BeautyKind kind;
  final DeviceTarget device;
  final String name;

  /// Sorted resource IDs, with an immutable snapshot of each payload.
  final Map<String, Uint8List> files;

  static const extension = 'chp';

  /// Maximum size of the complete encoded file, including its manifest.
  static const maxBytes = _headerBytes + _maxManifestBytes + _maxPayloadBytes;

  static const _magic = <int>[0x43, 0x48, 0x50, 0x31]; // CHP1
  static const _headerBytes = 8;
  static const _maxManifestBytes = 64 * 1024;
  static const _maxPayloadBytes = 32 * 1024 * 1024;
  static const _indexName = 'animations.bin';
  static const _animationSuffix = '_anim.bin';
  static final _iconLeaf = RegExp(r'[A-Za-z0-9_]{1,60}\.bin');
  static final _digest = RegExp(r'[a-f0-9]{64}');

  /// Tests only the four magic bytes, not the validity of the contents.
  static bool recognizes(Uint8List bytes) =>
      bytes.length >= _magic.length &&
      bytes[0] == _magic[0] &&
      bytes[1] == _magic[1] &&
      bytes[2] == _magic[2] &&
      bytes[3] == _magic[3];

  Uint8List encode() {
    final manifest = utf8.encode(_manifest(kind, device, name, [
      for (final entry in files.entries)
        (name: entry.key, size: entry.value.length, digest: _hash(entry.value)),
    ]));
    final length = files.values.fold(0, (sum, file) => sum + file.length);
    final result = Uint8List(_headerBytes + manifest.length + length);
    result.setAll(0, _magic);
    ByteData.sublistView(result).setUint32(4, manifest.length, Endian.little);
    result.setAll(_headerBytes, manifest);
    var at = _headerBytes + manifest.length;
    for (final data in files.values) {
      result.setAll(at, data);
      at += data.length;
    }
    return result;
  }

  static BeautyPack decode(Uint8List bytes) {
    if (!recognizes(bytes) || bytes.length < _headerBytes) {
      throw const BeautyPackError('不是完整的 CHP V1 美化包');
    }
    if (bytes.length > maxBytes) {
      throw const BeautyPackError('美化包超过文件大小上限');
    }
    final manifestSize =
        ByteData.sublistView(bytes).getUint32(4, Endian.little);
    final payloadAt = _headerBytes + manifestSize;
    if (manifestSize == 0 ||
        manifestSize > _maxManifestBytes ||
        payloadAt > bytes.length ||
        bytes[_headerBytes] != 0x7b) {
      throw const BeautyPackError('美化包清单长度或起始字节无效');
    }
    final payloadLength = bytes.length - payloadAt;
    if (payloadLength > _maxPayloadBytes) {
      throw const BeautyPackError('美化包素材总长度超过 32 MiB');
    }

    final String text;
    final Object? manifest;
    try {
      text = utf8.decode(Uint8List.sublistView(bytes, _headerBytes, payloadAt));
      _checkJsonDepth(text);
      manifest = jsonDecode(text);
    } on FormatException {
      throw const BeautyPackError('美化包清单不是有效的 UTF-8 JSON');
    }
    if (manifest is! Map<String, dynamic> ||
        manifest.length != 5 ||
        manifest['version'] is! int ||
        manifest['version'] != 1) {
      throw const BeautyPackError('美化包清单格式或版本不支持');
    }
    final kind = switch (manifest['kind']) {
      'font' => BeautyKind.font,
      'icon' => BeautyKind.icon,
      _ => throw const BeautyPackError('美化包素材类型不支持'),
    };
    final device = switch (manifest['device']) {
      'p67' => DeviceTarget.tenPro,
      'n67' => DeviceTarget.ninePro,
      _ => throw const BeautyPackError('美化包目标设备不支持'),
    };
    final name = manifest['name'];
    final entries = manifest['files'];
    if (name is! String || entries is! List) {
      throw const BeautyPackError('美化包名称或文件清单无效');
    }
    _validateName(kind, name);
    _validateCount(kind, entries.length);

    final records = <_Entry>[];
    final seen = <String>{};
    var remaining = payloadLength;
    String? previous;
    for (final entry in entries) {
      if (entry is! Map<String, dynamic> || entry.length != 3) {
        throw const BeautyPackError('美化包素材条目无效');
      }
      final leaf = entry['name'];
      final size = entry['size'];
      final hash = entry['sha256'];
      if (leaf is! String ||
          size is! int ||
          hash is! String ||
          hash.length != 64 ||
          !_matches(_digest, hash)) {
        throw const BeautyPackError('美化包素材条目字段无效');
      }
      _validateEntry(kind, device, leaf, size, seen);
      if (previous != null && previous.compareTo(leaf) >= 0) {
        throw const BeautyPackError('美化包素材未按文件名排序');
      }
      if (size > remaining) {
        throw const BeautyPackError('美化包素材被截断');
      }
      remaining -= size;
      previous = leaf;
      records.add((name: leaf, size: size, digest: hash));
    }
    if (remaining != 0) {
      throw const BeautyPackError('美化包尾部有多余字节');
    }
    // jsonDecode would silently collapse duplicate keys. Compare with the
    // canonical manifest built only from fields already validated above.
    if (_manifest(kind, device, name, records) != text) {
      throw const BeautyPackError('美化包清单不规范或包含重复字段');
    }

    final views = <String, Uint8List>{};
    var at = payloadAt;
    for (final entry in records) {
      final data = Uint8List.sublistView(bytes, at, at + entry.size);
      if (_hash(data) != entry.digest) {
        throw BeautyPackError('素材 SHA-256 校验失败：${entry.name}');
      }
      _validateResource(kind, device, entry.name, data);
      views[entry.name] = data;
      at += entry.size;
    }
    _validateAnimationSet(views);
    return BeautyPack._(kind, device, name, _snapshot(views));
  }

  static Map<String, Uint8List> _snapshot(Map<String, Uint8List> views) =>
      Map<String, Uint8List>.unmodifiable({
        for (final e in views.entries)
          e.key: Uint8List.fromList(e.value).asUnmodifiableView(),
      });

  static String _manifest(BeautyKind kind, DeviceTarget device, String name,
          List<_Entry> entries) =>
      jsonEncode({
        'version': 1,
        'kind': kind.name,
        'device': device.id,
        'name': name,
        'files': [
          for (final e in entries)
            {'name': e.name, 'size': e.size, 'sha256': e.digest},
        ],
      });

  static String _hash(Uint8List data) => sha256.convert(data).toString();

  static bool _matches(RegExp pattern, String value) =>
      pattern.matchAsPrefix(value)?.end == value.length;

  // This schema is just object → array → object. Keep the general-purpose
  // JSON reader from seeing attacker-chosen nesting depth.
  static void _checkJsonDepth(String text) {
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == 0x5c) {
          escaped = true;
        } else if (c == 0x22) {
          quoted = false;
        }
      } else if (c == 0x22) {
        quoted = true;
      } else if (c == 0x7b || c == 0x5b) {
        if (++depth > 3) throw const FormatException('JSON nesting');
      } else if (c == 0x7d || c == 0x5d) {
        if (--depth < 0) throw const FormatException('JSON nesting');
      }
    }
  }

  static void _validateName(BeautyKind kind, String name) {
    if (name.isEmpty || name.length > 12 || name.endsWith(' ')) {
      throw const BeautyPackError('素材短名须为 1–12 个 UTF-8 字节且末尾不能是空格');
    }
    final bytes = utf8.encode(name);
    if (bytes.length > 12 || utf8.decode(bytes) != name) {
      throw const BeautyPackError('素材短名须为 1–12 个有效 UTF-8 字节');
    }
    for (final c in name.runes) {
      if ((kind == BeautyKind.icon && (c <= 32 || c >= 127)) ||
          c < 32 ||
          (c >= 127 && c <= 159) ||
          (c >= 0x202a && c <= 0x202e) ||
          (c >= 0x2066 && c <= 0x2069)) {
        throw const BeautyPackError('素材短名包含不支持的字符');
      }
    }
  }

  static void _validateCount(BeautyKind kind, int count) {
    if (count < 1 || count > 256 || (kind == BeautyKind.font && count != 1)) {
      throw const BeautyPackError('美化包须包含一个字体文件或 1–256 个图标文件');
    }
  }

  static void _validateEntry(BeautyKind kind, DeviceTarget device, String leaf,
      int size, Set<String> seen) {
    final isFont = kind == BeautyKind.font;
    if (isFont ? leaf != 'font.ttf' : !_matches(_iconLeaf, leaf)) {
      throw const BeautyPackError('美化包素材文件名不合规');
    }
    if (!seen.add(leaf.toLowerCase())) {
      throw const BeautyPackError('美化包素材文件名重复');
    }
    final limit = isFont
        ? (device == DeviceTarget.ninePro ? 8000000 : 0xffffff)
        : 0x100000;
    if (size < 1 || size > limit) {
      throw BeautyPackError('素材文件长度超出限制：$leaf');
    }
  }

  static void _validateResource(
      BeautyKind kind, DeviceTarget device, String leaf, Uint8List data) {
    final n = data.length;
    final h = ByteData.sublistView(data);
    final bool ok;
    if (kind == BeautyKind.font) {
      ok = _isSfnt(h, device);
    } else if (device == DeviceTarget.ninePro) {
      if (leaf == _indexName || leaf.endsWith(_animationSuffix) || n < 4) {
        ok = false;
      } else {
        final word = h.getUint32(0, Endian.little);
        final w = (word >> 10) & 2047;
        final height = (word >> 21) & 2047;
        ok = (word & 1023) == 5 &&
            _isIconSize(w, height) &&
            n == 4 + 4 * w * height;
      }
    } else if (leaf == _indexName) {
      ok = n == 20 &&
          h.getUint32(0) == 0x43494131 && // CIA1
          h.getUint16(4, Endian.little) == 96 &&
          h.getUint16(6, Endian.little) == 96 &&
          h.getUint16(8, Endian.little) == AnimatedIcons.stems.length &&
          h.getUint16(10, Endian.little) == 0 &&
          (data[16] & 0xc0) == 0 &&
          data[17] == 0 &&
          data[18] == 0 &&
          data[19] == 0;
    } else if (leaf.endsWith(_animationSuffix)) {
      ok = _isAnimation(h, data);
    } else {
      ok = _isP67Image(h);
    }
    if (!ok) throw BeautyPackError('素材格式与目标设备不兼容：$leaf');
  }

  static bool _isSfnt(ByteData h, DeviceTarget device) {
    final n = h.lengthInBytes;
    if (n < 12) return false;
    final signature = h.getUint32(0);
    if (signature != 0x00010000 &&
        (device == DeviceTarget.ninePro ||
            (signature != 0x4f54544f && signature != 0x74727565))) {
      return false;
    }
    final count = h.getUint16(4);
    if (count < 1 || count > 256 || 12 + count * 16 > n) return false;
    for (var i = 0; i < count; i++) {
      final at = 12 + i * 16;
      final offset = h.getUint32(at + 8);
      final length = h.getUint32(at + 12);
      if (offset > n || length > n - offset) return false;
    }
    return true;
  }

  static bool _isIconSize(int w, int h) =>
      w >= 1 && w <= 512 && h >= 1 && h <= 512;

  static bool _isP67Image(ByteData h) {
    final n = h.lengthInBytes;
    if (n < 12 || h.getUint8(0) != 0x19) return false;
    final cf = h.getUint8(1);
    final flags = h.getUint16(2, Endian.little);
    final w = h.getUint16(4, Endian.little);
    final height = h.getUint16(6, Endian.little);
    final stride = h.getUint16(8, Endian.little);
    if (!_isIconSize(w, height)) return false;
    if (cf == 16)
      return flags == 0 && stride >= w * 4 && n == 12 + stride * height;
    if (cf != 10 || stride < w) return false;
    final raw = 1024 + stride * height;
    if (flags == 0) return n == 12 + raw;
    return flags == 8 &&
        stride <= 512 &&
        n > 24 &&
        h.getUint32(12, Endian.little) == 1 &&
        h.getUint32(16, Endian.little) == n - 24 &&
        h.getUint32(20, Endian.little) == raw;
  }

  static bool _isAnimation(ByteData h, Uint8List data) {
    if (data.length < Dgf1.tableOffset + 13 || !Dgf1.isAnimation(data)) {
      return false;
    }
    final count = h.getUint16(8, Endian.little);
    final offset = Dgf1.tableOffset + count * 12;
    return h.getUint16(4, Endian.little) == Dgf1.side &&
        h.getUint16(6, Endian.little) == Dgf1.side &&
        count >= 1 &&
        count <= Dgf1.maxFrames &&
        h.getUint16(10, Endian.little) == 0 &&
        h.getUint32(20, Endian.little) == Dgf1.tableOffset &&
        h.getUint32(24, Endian.little) == offset &&
        offset < data.length;
  }

  static void _validateAnimationSet(Map<String, Uint8List> files) {
    final index = files[_indexName];
    var count = 0;
    for (final leaf in files.keys) {
      if (!leaf.endsWith(_animationSuffix)) continue;
      count++;
      final stem = leaf.substring(0, leaf.length - _animationSuffix.length);
      final i = AnimatedIcons.stems.indexOf(stem);
      final cover = files['$stem.bin'];
      if (i < 0 ||
          index == null ||
          (index[12 + (i ~/ 8)] & (1 << (i % 8))) == 0 ||
          cover == null ||
          ByteData.sublistView(cover).getUint32(4, Endian.little) !=
              0x00600060) {
        throw const BeautyPackError('动态图标、96×96 静态封面与 CIA1 索引不匹配');
      }
    }
    if (index != null) {
      for (var i = 0; i < AnimatedIcons.stems.length; i++) {
        if ((index[12 + (i ~/ 8)] & (1 << (i % 8))) != 0) count--;
      }
      if (count != 0 || files.length == 1) {
        throw const BeautyPackError('CIA1 索引与实际图标文件不匹配');
      }
    }
  }
}

typedef _Entry = ({String name, int size, String digest});
