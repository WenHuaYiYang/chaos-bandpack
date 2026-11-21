import 'dart:io';
import 'dart:typed_data';

import 'package:chaos_bandpack/pack/cipk.dart';
import 'package:chaos_bandpack/pack/shell_builder.dart';
import 'package:test/test.dart';

/// 用 bandpack 仓库里的金标准素材对拍 —— 这些文件是 PC 侧脚本产出的真货,
/// 移植只要能和它们逐字节/逐字段对上, 就不需要真机也能证明打包链是对的。
Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

void main() {
  group('CIPK', () {
    test('解析 PC 侧的 animated-pack.cipk', () {
      final raw = fixture('animated-pack.cipk');
      final icons = Cipk.parse(raw);
      expect(raw.length, 97708);
      expect(icons.length, greaterThanOrEqualTo(1));
      // 名字全部合 ^[A-Za-z0-9_]+\.bin$, 且顺序与文件里一致
      for (final i in icons) {
        expect(i.fileName, matches(RegExp(r'^[A-Za-z0-9_]+\.bin$')));
      }
    });

    test('重新打包与 PC 侧逐字节一致', () {
      final raw = fixture('animated-pack.cipk');
      final icons = Cipk.parse(raw);
      expect(Cipk.build(icons), raw);
    });
  });

  group('ShellBuilder', () {
    test('解析 PC 侧的 animated-pack.bin', () {
      final raw = fixture('animated-pack.bin');
      final p = ShellBuilder.parse(raw);
      expect(p.files.length, 2);
      expect(p.files[0].key, '_lua/xiaomi-band-10-pro/main.lua');
      expect(p.files[1].key, '_lua/xiaomi-band-10-pro/pack.bin');
      expect(p.pkg.length, 12);
      expect(p.displayName.isNotEmpty, true);
      // 第 2 槽的内容就是同目录那份 CIPK
      expect(p.files[1].value, fixture('animated-pack.cipk'));
    });

    test('重新打包与 PC 侧逐字节一致', () {
      final raw = fixture('animated-pack.bin');
      final p = ShellBuilder.parse(raw);
      final rebuilt = ShellBuilder.build(
        files: [for (final f in p.files) ShellEntry(f.key, f.value)],
        device: p.device,
        pkgName: p.pkg,
        displayName: p.displayName,
        preview: p.preview,
        themeName: p.themeName,
      );
      expect(rebuilt.length, raw.length);
      expect(rebuilt, raw);
    });
  });
}
