import 'dart:convert';
import 'dart:typed_data';

import 'package:chaos_bandpack/icon/animated_icons.dart';
import 'package:chaos_bandpack/icon/device_target.dart';
import 'package:chaos_bandpack/icon/dgf1.dart';
import 'package:chaos_bandpack/icon/lvgl_icon_codec.dart';
import 'package:chaos_bandpack/pack/beauty_pack.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

const _goldenManifest = '{"version":1,"kind":"icon","device":"p67",'
    '"name":"Blue","files":[{"name":"alarm.bin","size":16,"sha256":'
    '"727b1ed56f6df11c185f0cf89d1f2c800e67c92c2c71e1a07217e9e9b6b11422"}]}';
final _goldenPixel = Uint8List.fromList([
  0x19,
  0x10,
  0,
  0,
  1,
  0,
  1,
  0,
  4,
  0,
  0,
  0,
  0x33,
  0x22,
  0x11,
  0xff,
]);
final _throwsPackError = throwsA(
  isA<BeautyPackError>().having((e) => e.message, 'message', isNotEmpty),
);

Uint8List _wrap(List<int> manifest, [List<int> payload = const []]) {
  final out = Uint8List(8 + manifest.length + payload.length);
  out.setAll(0, const [0x43, 0x48, 0x50, 0x31]);
  ByteData.sublistView(out).setUint32(4, manifest.length, Endian.little);
  out.setAll(8, manifest);
  out.setAll(8 + manifest.length, payload);
  return out;
}

Map<String, Object> _entry(String name, Uint8List bytes) => {
      'name': name,
      'size': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
    };

Uint8List _wire(List<MapEntry<String, Uint8List>> entries,
        {String kind = 'icon', String device = 'p67'}) =>
    _wrap(
      utf8.encode(jsonEncode({
        'version': 1,
        'kind': kind,
        'device': device,
        'name': 'Blue',
        'files': [for (final e in entries) _entry(e.key, e.value)],
      })),
      [for (final e in entries) ...e.value],
    );

Uint8List _font([int signature = 0x00010000]) {
  final data = Uint8List(32);
  ByteData.sublistView(data)
    ..setUint32(0, signature)
    ..setUint16(4, 1) // One table directory record.
    ..setUint32(12, 0x74657374) // Synthetic 'test' table tag.
    ..setUint32(20, 28)
    ..setUint32(24, 4);
  return data;
}

BeautyPack _icons(Map<String, Uint8List> files,
        {DeviceTarget device = DeviceTarget.tenPro, String name = 'Blue'}) =>
    BeautyPack(kind: BeautyKind.icon, device: device, name: name, files: files);

void main() {
  test('golden wire format, LE length and name-independent sniffing', () {
    final wire = Uint8List.fromList([
      0x43,
      0x48,
      0x50,
      0x31,
      0xad,
      0,
      0,
      0,
      ...utf8.encode(_goldenManifest),
      ..._goldenPixel,
    ]);
    expect(BeautyPack.extension, 'chp');
    expect(BeautyPack.maxBytes, 33619976);
    expect(BeautyPack.recognizes(wire), isTrue);
    expect(BeautyPack.recognizes(wire.sublist(0, 3)), isFalse);
    expect(BeautyPack.recognizes(wire.sublist(0, 4)), isTrue);
    expect(
        BeautyPack.recognizes(Uint8List.fromList('CHP2'.codeUnits)), isFalse);
    expect(_icons({'alarm.bin': _goldenPixel}).encode(), wire);
    final padded = Uint8List(wire.length + 3)..setAll(3, wire);
    final decoded = BeautyPack.decode(Uint8List.sublistView(padded, 3));
    expect(decoded.kind, BeautyKind.icon);
    expect(decoded.device, DeviceTarget.tenPro);
    expect(decoded.name, 'Blue');
    expect(decoded.files, {'alarm.bin': _goldenPixel});
    expect(decoded.encode(), wire);
  });

  test('font round trips for both devices including UTF-8 label', () {
    for (final device in DeviceTarget.values) {
      final font = _font();
      final original = BeautyPack(
        kind: BeautyKind.font,
        device: device,
        name: '新 字体',
        files: {'font.ttf': font},
      );
      final decoded = BeautyPack.decode(original.encode());
      expect(decoded.kind, BeautyKind.font);
      expect(decoded.device, device);
      expect(decoded.name, '新 字体');
      expect(decoded.files, {'font.ttf': font});
    }
  });

  test('static icons are deterministic and detached from inputs', () {
    final a = Uint8List.fromList(_goldenPixel);
    final b = LvglIconCodec.indexedRle([0xff998877], 1, 1);
    final source = {'weather.bin': b, 'alarm.bin': a};
    final pack = _icons(source, name: r'Blue\"');
    final wire = pack.encode();
    expect(_icons({'alarm.bin': a, 'weather.bin': b}, name: pack.name).encode(),
        wire);
    expect(pack.files.keys, ['alarm.bin', 'weather.bin']);
    a[0] = 0;
    source.clear();
    expect(pack.encode(), wire);
    final decoded = BeautyPack.decode(wire);
    wire.fillRange(0, wire.length, 0);
    expect(decoded.name, pack.name);
    expect(decoded.files['alarm.bin'], _goldenPixel);
    expect(() => decoded.files['other.bin'] = b, throwsUnsupportedError);
    expect(() => decoded.files['alarm.bin']![0] = 0, throwsUnsupportedError);
  });

  test('9 Pro accepts PackMake-style packed BGRA, not p67 LVGL', () {
    final nine =
        LvglIconCodec.bgra8(List<int>.filled(10000, 0xff556677), 100, 100);
    final ninePack = _icons({'sports.bin': nine}, device: DeviceTarget.ninePro);
    expect(BeautyPack.decode(ninePack.encode()).files['sports.bin'], nine);
    expect(() => _icons({'sports.bin': nine}), _throwsPackError);
    expect(
        () =>
            _icons({'sports.bin': _goldenPixel}, device: DeviceTarget.ninePro),
        _throwsPackError);
    expect(
        () => _icons({'sports.bin': nine.sublist(0, nine.length - 1)},
            device: DeviceTarget.ninePro),
        _throwsPackError);
  });

  test('p67 generated DGF1, CIA1 and cover round-trip as a set', () {
    final pixels = List<int>.filled(Dgf1.pixels, 0xff336699);
    final anim = Dgf1.encode([Frame(pixels, 100)], 0, Uint8List(0));
    final cover = LvglIconCodec.bgra(pixels, 96, 96);
    final index = AnimatedIcons.index({'wxpay'}); // Exercise mask bit 37.
    final files = {
      'wxpay.bin': cover,
      'wxpay_anim.bin': anim,
      'animations.bin': index
    };
    expect(BeautyPack.decode(_icons(files).encode()).files, files);
    expect(() => _icons({'wxpay_anim.bin': anim, 'animations.bin': index}),
        _throwsPackError);
    expect(() => _icons({'wxpay_anim.bin': anim, 'wxpay.bin': cover}),
        _throwsPackError);
    expect(
        () => _icons({
              'wxpay_anim.bin': anim,
              'wxpay.bin': cover,
              'animations.bin': AnimatedIcons.index({'alarm'})
            }),
        _throwsPackError);
    expect(() => _icons(files, device: DeviceTarget.ninePro), _throwsPackError);
  });

  test('rejects invalid labels, resource paths, duplicates and mixed kinds',
      () {
    for (final text in ['', 'foo bar', '中文', 'abcdefghijklm', 'A\u0000']) {
      expect(() => _icons({'alarm.bin': _goldenPixel}, name: text),
          _throwsPackError);
    }
    for (final text in [
      '字体字体字',
      'A ',
      'A\u007f',
      'A\u009f',
      'A\u202e',
      'A\u2066',
      String.fromCharCode(0xd800)
    ]) {
      expect(
          () => BeautyPack(
              kind: BeautyKind.font,
              device: DeviceTarget.tenPro,
              name: text,
              files: {'font.ttf': _font()}),
          _throwsPackError);
    }
    for (final leaf in [
      '../alarm.bin',
      r'other\alarm.bin',
      '/alarm.bin',
      'alarm.bin\n',
      'alarm.BIN',
      '.bin',
      'A.B.bin',
      'font.ttf',
      'main.lua'
    ]) {
      expect(() => BeautyPack.decode(_wire([MapEntry(leaf, _goldenPixel)])),
          _throwsPackError,
          reason: leaf);
    }
    expect(() => _icons({'Alarm.bin': _goldenPixel, 'alarm.bin': _goldenPixel}),
        _throwsPackError);
    expect(
        () => BeautyPack.decode(_wire([
              MapEntry('alarm.bin', _goldenPixel),
              MapEntry('alarm.bin', _goldenPixel),
            ])),
        _throwsPackError);
    expect(
        () => BeautyPack.decode(_wire([
              MapEntry('alarm.bin', _goldenPixel),
              MapEntry('font.ttf', _font()),
            ], kind: 'font')),
        _throwsPackError);
  });

  test('rejects sizes, counts, versions and non-canonical or invalid JSON', () {
    for (final manifest in [
      _goldenManifest.replaceFirst('"version":1', '"version":2'),
      _goldenManifest.replaceFirst('"version":1', '"version":1.0'),
      _goldenManifest.replaceFirst('"device":"p67"', '"device":"n99"'),
      _goldenManifest.replaceFirst('"kind":"icon"', '"kind":"unknown"'),
      _goldenManifest.replaceFirst(
          '"name":"Blue"', '"name":"Red","name":"Blue"'),
      _goldenManifest.replaceFirst('"name":"Blue"', '"name": [[[[0]]]]'),
      _goldenManifest.replaceFirst('"size":16', '"size":0'),
      _goldenManifest.replaceFirst('"size":16', '"size":-1'),
      _goldenManifest.replaceFirst('"size":16', '"size":1048577'),
      _goldenManifest.replaceFirst('"size":16', '"size":17'),
      _goldenManifest.replaceFirst('"size":16', '"length":16'),
      _goldenManifest.replaceFirst('727b', '727B'),
      '$_goldenManifest ',
      '{',
    ]) {
      expect(
          () => BeautyPack.decode(_wrap(utf8.encode(manifest), _goldenPixel)),
          _throwsPackError,
          reason: manifest);
    }
    expect(
        () => BeautyPack.decode(_wrap([0x7b, 0xff, 0x7d])), _throwsPackError);
    expect(() => BeautyPack.decode(_wrap(Uint8List(65537))), _throwsPackError);
    expect(() => BeautyPack.decode(_wrap([])), _throwsPackError);
    expect(() => BeautyPack.decode(_wire([])), _throwsPackError);
    expect(
        () => BeautyPack.decode(_wire([
              for (var i = 0; i < 257; i++) MapEntry('i$i.bin', _goldenPixel),
            ])),
        _throwsPackError);
    expect(
        () => BeautyPack.decode(_wire([
              MapEntry('weather.bin', _goldenPixel),
              MapEntry('alarm.bin', _goldenPixel),
            ])),
        _throwsPackError);
    final nearMiB = Uint8List(12 + 2048 * 511)
      ..setAll(0, LvglIconCodec.header(512, 511, 16, 0, 2048));
    expect(() => _icons({for (var i = 0; i < 33; i++) 'i$i.bin': nearMiB}),
        _throwsPackError);
  });

  test('rejects corrupt digest, all shorter prefixes and trailing bytes', () {
    final wire = _icons({'alarm.bin': _goldenPixel}).encode();
    for (var length = 0; length < wire.length; length++) {
      expect(() => BeautyPack.decode(Uint8List.sublistView(wire, 0, length)),
          _throwsPackError,
          reason: 'prefix length $length');
    }
    expect(() => BeautyPack.decode(Uint8List.fromList([...wire, 0])),
        _throwsPackError);
    wire[wire.length - 1] ^= 1;
    expect(() => BeautyPack.decode(wire), _throwsPackError);
  });

  test('checks resource headers even when digests match', () {
    final wrongFont = _font();
    ByteData.sublistView(wrongFont).setUint32(20, 0xffffffff);
    expect(
        () => BeautyPack.decode(
            _wire([MapEntry('font.ttf', wrongFont)], kind: 'font')),
        _throwsPackError);
    final otto = _font(0x4f54544f);
    expect(
        BeautyPack.decode(_wire([MapEntry('font.ttf', otto)], kind: 'font'))
            .kind,
        BeautyKind.font);
    expect(
        () => BeautyPack.decode(
            _wire([MapEntry('font.ttf', otto)], kind: 'font', device: 'n67')),
        _throwsPackError);
    final wrongIcon = Uint8List.fromList(_goldenPixel)..[8] = 1;
    expect(() => BeautyPack.decode(_wire([MapEntry('alarm.bin', wrongIcon)])),
        _throwsPackError);
  });
}
