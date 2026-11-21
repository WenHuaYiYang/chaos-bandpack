import 'dart:convert';
import 'dart:typed_data';

import 'package:chaos_bandpack/icon/lvgl_icon_codec.dart';
import 'package:chaos_bandpack/pack/cipk.dart';
import 'package:chaos_bandpack/pack/nine_pack_builder.dart';
import 'package:chaos_bandpack/pack/nine_shell_builder.dart';
import 'package:chaos_bandpack/pack/pack_builders.dart';
import 'package:chaos_bandpack/pack/shell_writer.dart';
import 'package:test/test.dart';

/// 9 Pro 的清单模板: 只要占位符出现一次就够了, 其余是设备侧 Lua 的无关内容。
const String _template = '-- 9 Pro importer\nlocal M = __N67_MANIFEST__\nreturn M\n';

Uint8List _preview() {
  final ByteData data = ByteData(64);
  data.setUint8(0, 0x10);
  data.setUint8(1, 0x04);
  data.setUint16(4, 336, Endian.little);
  data.setUint16(6, 480, Endian.little);
  data.setUint32(8, 52, Endian.little);
  data.setUint32(12, 0x5AA521E0, Endian.little); // 预览块魔数, 与 PreviewFactory 一致
  return data.buffer.asUint8List();
}

/// 最小可用 TrueType: 只要求前 4 字节是 0x00010000。9 Pro 分支不解析字形。
Uint8List _font(int size) {
  final Uint8List out = Uint8List(size);
  out.setRange(0, 4, <int>[0, 1, 0, 0]);
  for (var i = 4; i < size; i++) {
    out[i] = i & 0xFF;
  }
  return out;
}

Uint8List _icon(int side, int seed) {
  final List<int> pixels = List<int>.filled(side * side, 0);
  for (var i = 0; i < pixels.length; i++) {
    pixels[i] = 0xFF000000 | ((seed + i) & 0x00FFFFFF);
  }
  return LvglIconCodec.bgra8(pixels, side, side);
}

String _lua(NineShellParsed parsed) =>
    utf8.decode(parsed.files.first.value, allowMalformed: true);

void main() {
  group('9 Pro 字体包', () {
    test('按 64000 字节分片, 片名顺序且清单与分片对得上', () {
      final Uint8List font = _font(150000);
      final FontPackResult r = NinePackBuilder.font(
        template: _template,
        inputs: FontPackInputs(
          label: '文楷',
          packName: '字:文楷',
          title: '字体投递 文楷',
          font: font,
        ),
        preview: _preview(),
      );
      final NineShellParsed parsed = NineShellBuilder.parse(r.bytes);
      expect(parsed.displayName, '字:文楷');
      expect(parsed.pkg, r.pkgName);
      // main.lua + 3 片(64000 / 64000 / 22000)
      expect(parsed.files.length, 4);
      expect(parsed.files[0].key, '_lua/_Lua/main.lua');
      expect(parsed.files[1].key, '_lua/_Lua/font-000.dat');
      expect(parsed.files[2].key, '_lua/_Lua/font-001.dat');
      expect(parsed.files[3].key, '_lua/_Lua/font-002.dat');
      expect(parsed.files[1].value.length, 64000);
      expect(parsed.files[3].value.length, 22000);
      final BytesBuilder joined = BytesBuilder(copy: false);
      for (final e in parsed.files.skip(1)) {
        joined.add(e.value);
      }
      expect(joined.takeBytes(), font);

      final String lua = _lua(parsed);
      expect(lua.contains('kind="font"'), isTrue);
      expect(lua.contains('label="文楷"'), isTrue);
      expect(lua.contains('title="字体投递 文楷"'), isTrue);
      expect(lua.contains('pkg="' + r.pkgName + '"'), isTrue);
      // 清单是逐片记账: sum 是这一片自己的逐字节和, 不是整包的。
      final int first = font.take(64000).fold<int>(0, (int a, int b) => a + b);
      expect(lua.contains('src="font-000.dat",bytes=64000,sum=' + first.toString()), isTrue);
    });

    test('超过 8 MB 或不是 TrueType 的字体被拒', () {
      expect(
        () => NinePackBuilder.font(
          template: _template,
          inputs: FontPackInputs(
            label: 'big',
            packName: '字:big',
            title: '字体投递 big',
            font: _font(NinePackBuilder.maxFontBytes + 4),
          ),
          preview: _preview(),
        ),
        throwsA(isA<PackError>()),
      );
      final Uint8List otf = _font(4000);
      otf.setRange(0, 4, <int>[0x4F, 0x54, 0x54, 0x4F]); // OTTO
      expect(
        () => NinePackBuilder.font(
          template: _template,
          inputs: FontPackInputs(
            label: 'otf',
            packName: '字:otf',
            title: '字体投递 otf',
            font: otf,
          ),
          preview: _preview(),
        ),
        throwsA(isA<PackError>()),
      );
    });

    test('短名超过 12 字节或含空格被拒', () {
      for (final String label in <String>['1234567890123', 'ab cd']) {
        expect(
          () => NinePackBuilder.font(
            template: _template,
            inputs: FontPackInputs(
              label: label,
              packName: '字:x',
              title: '字体投递 x',
              font: _font(4000),
            ),
            preview: _preview(),
          ),
          throwsA(isA<PackError>()),
          reason: label,
        );
      }
    });
  });

  group('9 Pro 图标包', () {
    test('每槽一片 dat, 清单带 stem 与尺寸, 全量 stems 供设备清理', () {
      final List<CipkIcon> icons = <CipkIcon>[
        CipkIcon('heartrate', _icon(100, 1)),
        CipkIcon('ctrl_battery', _icon(64, 2)),
      ];
      final IconPackResult r = NinePackBuilder.icons(
        template: _template,
        inputs: IconPackInputs(
          short: 'chaos',
          packName: '图标:chaos',
          title: '图标投递 chaos',
          files: icons,
        ),
        preview: _preview(),
      );
      final NineShellParsed parsed = NineShellBuilder.parse(r.bytes);
      expect(r.iconCount, 2);
      expect(parsed.files.length, 3);
      expect(parsed.files[1].key, '_lua/_Lua/ctrl_battery.dat');
      expect(parsed.files[2].key, '_lua/_Lua/heartrate.dat');
      expect(parsed.files[2].value, icons[0].data);
      final String lua = _lua(parsed);
      expect(lua.contains('kind="icons"'), isTrue);
      expect(
        lua.contains('src="heartrate.dat",bytes=40004,sum='),
        isTrue,
      );
      expect(lua.contains('stem="heartrate",width=100,height=100'), isTrue);
      expect(lua.contains('stem="ctrl_battery",width=64,height=64'), isTrue);
      // 全量槽位里必须有配对文件, 设备侧靠它清旧图标。
      expect(lua.contains('"ctrl_phone_conn"'), isTrue);
      expect(lua.contains('"ctrl_phone_disconn"'), isTrue);
      expect(lua.contains('"breathing"'), isTrue); // breath 的 fileStem
    });

    test('尺寸不符 / 未知槽位 / 重复槽位被拒', () {
      expect(
        () => NinePackBuilder.icons(
          template: _template,
          inputs: IconPackInputs(
            short: 'bad',
            packName: '图标:bad',
            title: '图标投递 bad',
            files: <CipkIcon>[CipkIcon('heartrate', _icon(64, 3))],
          ),
          preview: _preview(),
        ),
        throwsA(isA<PackError>()),
      );
      expect(
        () => NinePackBuilder.icons(
          template: _template,
          inputs: IconPackInputs(
            short: 'bad',
            packName: '图标:bad',
            title: '图标投递 bad',
            files: <CipkIcon>[CipkIcon('nope', _icon(64, 4))],
          ),
          preview: _preview(),
        ),
        throwsA(isA<PackError>()),
      );
      expect(
        () => NinePackBuilder.icons(
          template: _template,
          inputs: IconPackInputs(
            short: 'bad',
            packName: '图标:bad',
            title: '图标投递 bad',
            files: <CipkIcon>[
              CipkIcon('heartrate', _icon(100, 5)),
              CipkIcon('heartrate', _icon(100, 6)),
            ],
          ),
          preview: _preview(),
        ),
        throwsA(isA<PackError>()),
      );
    });

    test('模板里占位符不是恰好一次就报错', () {
      expect(
        () => NinePackBuilder.icons(
          template: '-- 无占位符\n',
          inputs: IconPackInputs(
            short: 'chaos',
            packName: '图标:chaos',
            title: '图标投递 chaos',
            files: <CipkIcon>[CipkIcon('heartrate', _icon(100, 7))],
          ),
          preview: _preview(),
        ),
        throwsA(isA<PackError>()),
      );
    });
  });
}
