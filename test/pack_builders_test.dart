import 'dart:convert';
import 'dart:typed_data';

import 'package:chaos_bandpack/pack/cipk.dart';
import 'package:chaos_bandpack/pack/pack_builders.dart';
import 'package:chaos_bandpack/pack/shell_builder.dart';
import 'package:chaos_bandpack/pack/shell_writer.dart';
import 'package:test/test.dart';

/// 与 PackWriterTest 同口径的合成素材: 只要形状对, 内容无所谓。
PackAssets fakeAssets() {
  const fontLua = 'local FONT_NAME = "__FONT_NAME__"\n'
      'local PACK_LABEL = "__PACK_LABEL__"\n'
      'local PACK_TITLE = "__PACK_TITLE__"\n'
      'return true\n';
  const iconLua = 'local PACK_NAME = "__PACK_NAME__"\n'
      'local PACK_TITLE = "__PACK_TITLE__"\n'
      'return true\n';
  return PackAssets(
    ko: Uint8List.fromList(List.generate(64, (i) => i)),
    iconBin: Uint8List.fromList(List.generate(48, (i) => i * 3 % 256)),
    fontLua: fontLua,
    iconLua: iconLua,
  );
}

/// 12 字节头的假预览块(标签 0x410, 尺寸 336x480)。
Uint8List fakePreview(int payload) {
  final out = Uint8List(12 + payload);
  ShellWriter.writeU32To(out, 0, ShellBuilder.previewTag);
  out[4] = 0x10;
  out[5] = 0x04;
  out[6] = 0;
  out[7] = 0;
  out[8] = payload & 0xFF;
  out[9] = (payload >> 8) & 0xFF;
  out[10] = (payload >> 16) & 0xFF;
  out[11] = 0;
  for (var i = 0; i < payload; i++) {
    out[12 + i] = 0x50 + i % 3;
  }
  return out;
}

void main() {
  group('字体包', () {
    test('四槽结构与包名按字体内容推导', () {
      final assets = fakeAssets();
      final font = Uint8List.fromList(List.generate(256, (i) => (i * 7) % 256));
      final preview = fakePreview(32);
      final r = FontPackBuilder.build(
        assets: assets,
        inputs: FontPackInputs(
          label: '文楷',
          packName: '字:文楷',
          title: '字体投递 文楷',
          font: font,
        ),
        preview: preview,
      );

      expect(r.pkgName, ShellWriter.pkgFor(font));
      expect(r.pkgName.length, 12);
      final p = ShellBuilder.parse(r.bytes);
      expect(p.displayName, '字:文楷');
      expect(p.pkg, r.pkgName);
      expect(p.files.map((e) => e.key).toList(), [
        '_lua/fontpack/main.lua',
        '_lua/fontpack/chaos_sup.ko',
        '_lua/fontpack/chaos_icon.bin',
        '_lua/fontpack/font.ttf',
      ]);
      expect(p.files[1].value, assets.ko);
      expect(p.files[2].value, assets.iconBin);
      expect(p.files[3].value, font);
      final lua = utf8.decode(p.files[0].value);
      expect(lua.contains('local FONT_NAME = "文楷"'), isTrue);
      expect(lua.contains('local PACK_TITLE = "字体投递 文楷"'), isTrue);
      expect(lua.contains('__'), isFalse);
    });

    test('短名超 12 字节被拒', () {
      expect(
        () => FontPackBuilder.build(
          assets: fakeAssets(),
          inputs: FontPackInputs(
            label: '一二三四五六七八九十一二',
            packName: 'x',
            title: 't',
            font: Uint8List(4),
          ),
          preview: fakePreview(8),
        ),
        throwsA(isA<PackError>()),
      );
    });

    test('撞主包号被拒', () {
      expect(
        () => FontPackBuilder.build(
          assets: fakeAssets(),
          inputs: FontPackInputs(
            label: 'a',
            packName: 'x',
            title: 't',
            font: Uint8List(4),
            pkgName: ShellWriter.mainPkg,
          ),
          preview: fakePreview(8),
        ),
        throwsA(isA<PackError>()),
      );
    });
  });

  group('图标包', () {
    test('两槽结构与 p67 容器版本', () {
      final assets = fakeAssets();
      final icons = [
        Cipk.icon('alarm', Uint8List.fromList([19, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])),
        Cipk.icon('music', Uint8List.fromList([19, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])),
      ];
      final r = IconPackBuilder.build(
        template: assets.iconLua,
        inputs: IconPackInputs(
          short: 'Pure',
          packName: 'Pure 图标',
          title: '图标投递 Pure',
          files: icons,
        ),
        preview: fakePreview(32),
      );

      expect(r.iconCount, 2);
      final p = ShellBuilder.parse(r.bytes);
      expect(p.device, IconPackBuilder.containerVersion);
      expect(p.files.map((e) => e.key).toList(), [
        '_lua/xiaomi-band-10-pro/main.lua',
        '_lua/xiaomi-band-10-pro/pack.bin',
      ]);
      expect(r.pkgName, ShellWriter.pkgFor(p.files[1].value));
      final back = Cipk.parse(p.files[1].value);
      expect(back.map((e) => e.stem).toList(), ['alarm', 'music']);
    });

    test('非法短名被拒', () {
      expect(IconPackBuilder.validShort('Pure'), isTrue);
      expect(IconPackBuilder.validShort('纯图标'), isFalse);
      expect(IconPackBuilder.validShort(''), isFalse);
      expect(IconPackBuilder.validShort('a' * 13), isFalse);
    });
  });

  group('patchLua', () {
    test('CRLF 归一成 LF', () {
      final out = patchLua('a __X__ b\r\nc\r\n', {'__X__': '1'});
      expect(out, 'a 1 b\nc\n');
    });

    test('占位符必须恰好一次', () {
      expect(() => patchLua('__X__ __X__', {'__X__': '1'}), throwsA(isA<PackError>()));
      expect(() => patchLua('nope', {'__X__': '1'}), throwsA(isA<PackError>()));
    });

    test('引号与反斜杠转义', () {
      expect(luaQuote('a"b\\c'), 'a\\"b\\\\c');
      expect(luaQuote('a\u0007b'), 'a\\007b');
    });
  });

  group('TitleText', () {
    test('宽度按全角算 2', () {
      expect(TitleText.width('字体投递 花朝粗'), 15);
      expect(TitleText.validate('字体投递 花朝粗'), isNull);
      // 8 个汉字正好 16 半角, 是上限内
      expect(TitleText.width('字体投递花朝粗体'), 16);
      expect(TitleText.validate('字体投递花朝粗体'), isNull);
      // 9 个汉字 18 半角, 超宽
      expect(TitleText.validate('字体投递花朝粗体呀'), isNotNull);
      expect(TitleText.validate('Font Deluxe'), isNull);
      expect(TitleText.width('Font Deluxe'), 11);
      expect(TitleText.validate('   '), '标题不能为空');
    });
  });
}