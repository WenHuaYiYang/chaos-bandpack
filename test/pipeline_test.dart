import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chaos_bandpack/icon/device_target.dart';
import 'package:chaos_bandpack/icon/icon_spec.dart';
import 'package:chaos_bandpack/icon/lvgl_icon_codec.dart';
import 'package:chaos_bandpack/icon/nine_icon_spec.dart';
import 'package:chaos_bandpack/make/font_make.dart';
import 'package:chaos_bandpack/make/pack_make.dart';
import 'package:chaos_bandpack/pack/cipk.dart';
import 'package:chaos_bandpack/pack/nine_shell_builder.dart';
import 'package:chaos_bandpack/pack/pack_builders.dart';
import 'package:chaos_bandpack/pack/shell_builder.dart';
import 'package:chaos_bandpack/pack/shell_writer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 端到端: 素材 -> 子集化 -> 打包 -> 解包回读。
///
/// 单测分在各自文件里, 这里只回答一个问题: 把真素材喂进真链路, 出来的容器能不能
/// 被自己的解析器读回去、内容是否与中间产物逐字节相同。打包素材走 assets/pack/,
/// 所以这组用例只能用 flutter test 跑。
const List<String> _fontCandidates = <String>[
  'C:/Users/YiYang/Downloads/LXGWWenKai-Regular.ttf',
  'C:/Users/YiYang/Documents/xiaomi band 10 pro/scripts/MiSans-Regular.ttf',
  'C:/Users/YiYang/Documents/chaos-bandpack-flutter/assets/fonts/MiSans-Regular.ttf',
  'C:/Windows/Fonts/simhei.ttf',
  'C:/Windows/Fonts/Deng.ttf',
];

Uint8List? _pickFont() {
  for (final String path in _fontCandidates) {
    final File f = File(path);
    if (f.existsSync()) return f.readAsBytesSync();
  }
  return null;
}

Uint8List _fixture(String name) =>
    File('test/fixtures/' + name).readAsBytesSync();

void main() {
  // 打包素材走 rootBundle(assets/pack/), 必须先有绑定才能读。
  TestWidgetsFlutterBinding.ensureInitialized();
  final Uint8List? source = _pickFont();

  group('字体包端到端', () {
    test('10 Pro: 四槽结构与字体字节都对得上', () async {
      if (source == null) return;
      final Made made = FontMake.build(source);
      final FontPackResult out = await PackMake.fontPack(
        label: '文楷',
        packName: '字:文楷',
        title: '字体投递 文楷',
        font: made.font,
      );
      final ShellParsed parsed = ShellBuilder.parse(out.bytes);
      expect(parsed.files.length, 4);
      expect(parsed.displayName, '字:文楷');
      expect(parsed.pkg, out.pkgName);
      // checkPkg 不抛就说明是合规的 12 位表盘 ID。
      ShellWriter.checkPkg(out.pkgName);
      expect(out.pkgName, isNot(ShellWriter.mainPkg));
      final MapEntry<String, Uint8List> font =
          parsed.files.firstWhere((MapEntry<String, Uint8List> e) => e.key == '_lua/fontpack/font.ttf');
      // 打进包里的字体必须就是子集化的那份, 不能是源字体也不能再裁一次。
      expect(font.value.length, made.font.length);
      expect(font.value, orderedEquals(made.font));
      // Lua 是 UTF-8 源码, 中文短名必须按 UTF-8 解, 不能拿 code unit 直接当字符。
      final String lua = utf8.decode(
          parsed.files.firstWhere((MapEntry<String, Uint8List> e) => e.key == '_lua/fontpack/main.lua').value);
      expect(lua.contains('local FONT_NAME = "文楷"'), isTrue);
      expect(lua.contains('__FONT_NAME__'), isFalse);
      expect(lua.contains('__PACK_TITLE__'), isFalse);
    });

    test('9 Pro: 分片拼回等于子集化字体, 清单与容器一致', () async {
      if (source == null) return;
      final Made made = FontMake.build(source);
      final FontPackResult out = await PackMake.fontPack(
        label: 'wenkai',
        packName: '字:wenkai',
        title: '字体投递 wenkai',
        font: made.font,
        device: DeviceTarget.ninePro,
      );
      final NineShellParsed parsed = NineShellBuilder.parse(out.bytes);
      expect(parsed.pkg, out.pkgName);
      final List<Uint8List> chunks = parsed.files
          .where((MapEntry<String, Uint8List> e) => e.key.endsWith('.dat'))
          .map((MapEntry<String, Uint8List> e) => e.value)
          .toList();
      expect(chunks, isNotEmpty);
      final BytesBuilder joined = BytesBuilder();
      for (final Uint8List chunk in chunks) {
        joined.add(chunk);
      }
      expect(joined.takeBytes(), orderedEquals(made.font));
      final String lua = utf8.decode(
          parsed.files.firstWhere((MapEntry<String, Uint8List> e) => e.key == '_lua/_Lua/main.lua').value);
      expect(lua.contains('kind="font"'), isTrue);
      expect(lua.contains('__N67_MANIFEST__'), isFalse);
    });
  });

  group('图标包端到端', () {
    test('10 Pro: CIPK 里的图标与槽位字节相同', () async {
      final Uint8List cover = _fixture('cover96.bin');
      final IconSpecSlot slot = IconSpec.stemOf('alarm')!;
      final IconPackResult out = await PackMake.iconPack(
        short: 'chaos',
        packName: '图标:chaos',
        title: '图标投递 chaos',
        files: <CipkIcon>[CipkIcon(slot.stem, cover)],
      );
      final ShellParsed parsed = ShellBuilder.parse(out.bytes);
      expect(parsed.files.length, 2);
      expect(parsed.device, 0x00010107);
      final Uint8List cipkBytes = parsed.files
          .firstWhere((MapEntry<String, Uint8List> e) => e.key == '_lua/xiaomi-band-10-pro/pack.bin')
          .value;
      final List<CipkIcon> icons = Cipk.parse(cipkBytes);
      expect(icons.length, 1);
      expect(icons.first.stem, 'alarm');
      expect(icons.first.data, orderedEquals(cover));
      expect(out.iconCount, 1);
    });

    test('9 Pro: 每个图标一片 dat, 尺寸按槽位校验', () async {
      final IconSpecSlot slot = NineIconSpec.slots
          .firstWhere((IconSpecSlot s) => s.stem == 'heartrate');
      // 9 Pro 的桌面图标是 100 x 100, 现造一张纯色图, 只为验证容器分片。
      final Uint8List icon = LvglIconCodec.bgra8(
        List<int>.filled(100 * 100, 0xFF33AA55),
        100,
        100,
      );
      final IconPackResult out = await PackMake.iconPack(
        short: 'chaos',
        packName: '图标:chaos',
        title: '图标投递 chaos',
        files: <CipkIcon>[CipkIcon(slot.stem, icon)],
        device: DeviceTarget.ninePro,
      );
      final NineShellParsed parsed = NineShellBuilder.parse(out.bytes);
      final Iterable<String> data = parsed.files
          .map((MapEntry<String, Uint8List> e) => e.key)
          .where((String k) => k.endsWith('.dat'));
      expect(data, isNotEmpty);
    });
  });
}
