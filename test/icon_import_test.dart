import 'dart:io';
import 'dart:typed_data';

import 'package:chaos_bandpack/icon/animated_icons.dart';
import 'package:chaos_bandpack/icon/device_target.dart';
import 'package:chaos_bandpack/icon/dgf1.dart';
import 'package:chaos_bandpack/icon/icon_input_names.dart';
import 'package:chaos_bandpack/make/icon_import.dart';
import 'package:chaos_bandpack/make/icon_make.dart';
import 'package:test/test.dart';

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

/// 用一组文件名走一遍「认名字 -> 分组 -> 换算」, 与界面上批量导入同一条路。
(Map<String, Uint8List>, int) importGroup(
  List<String> names, {
  DeviceTarget device = DeviceTarget.tenPro,
  Map<String, Uint8List> overrides = const <String, Uint8List>{},
  Uint8List? existingCover,
}) {
  final IconInputPlan plan = IconInputNames.plan(names, device);
  expect(plan.groups.length, 1, reason: '这一组应该只落在一个槽位上');
  final IconInputGroup group = plan.groups.single;
  expect(group.error, isNull);
  final List<Uint8List?> inputs = <Uint8List?>[
    for (final String n in names) overrides[n] ?? fixture(n),
  ];
  return IconImport.group(
    group: group,
    inputs: inputs,
    names: names,
    device: device,
    existingCover: existingCover,
  );
}

void main() {
  group('批量导入的一个槽位', () {
    test('一张 GIF 同时给出封面与 DGF1 动画', () {
      // 命名层只认 stem; 现成 fixture 里没有 activities.gif, 借一份合法 GIF 字节。
      final (Map<String, Uint8List> made, int frames) = importGroup(
        <String>['activities.gif'],
        overrides: <String, Uint8List>{
          'activities.gif': fixture('loop-once.gif'),
        },
      );
      expect(made.keys, contains('activities'));
      expect(made.keys, contains(AnimatedIcons.key('activities')));
      expect(frames, greaterThan(0));
      expect(Dgf1.isAnimation(made[AnimatedIcons.key('activities')]!), isTrue);
      expect(Dgf1.parse(made[AnimatedIcons.key('activities')]!).frames.length, frames);
      // 封面必须是 96 x 96 的 p67 原生 BIN, 不然手环读不了。
      expect(made['activities']!.length, 12 + 96 * 96 * 4);
    });

    test('GIF 配同名 _anim.bin 时整组失败, 不覆盖原选择', () {
      final IconInputPlan plan = IconInputNames.plan(
        <String>['activities.gif', 'activities_anim.bin'],
        DeviceTarget.tenPro,
      );
      final IconInputGroup group = plan.groups.single;
      expect(group.error, contains('多个动画'));
    });

    test('只有 _anim.bin 但没有封面时报错, 而不是留半张图', () {
      final IconInputPlan plan = IconInputNames.plan(
        <String>['activities_anim.bin'],
        DeviceTarget.tenPro,
      );
      final IconInputGroup group = plan.groups.single;
      expect(group.error, isNull);
      expect(
        () => IconImport.group(
          group: group,
          inputs: <Uint8List?>[fixture('valid.dgf')],
          names: <String>['activities_anim.bin'],
          device: DeviceTarget.tenPro,
        ),
        throwsA(isA<IconMakeError>()),
      );
    });

    test('9 Pro 不吃 GIF: 动画只属于 10 Pro 桌面', () {
      // 9 Pro 认 heartrate 这个 stem; 用合法 GIF 字节让转换层去拒绝。
      expect(
        () => importGroup(<String>['heartrate.gif'],
            device: DeviceTarget.ninePro,
            overrides: <String, Uint8List>{
              'heartrate.gif': fixture('loop-once.gif'),
            }),
        throwsA(isA<IconMakeError>()),
      );
    });

    test('BIN 通道里塞进动画会被拒', () {
      expect(
        () => importGroup(
          <String>['activities.bin'],
          overrides: <String, Uint8List>{'activities.bin': fixture('valid.dgf')},
        ),
        throwsA(isA<IconMakeError>()),
      );
    });
  });

  group('动画帧数读数', () {
    test('valid.dgf 的帧数与解析结果一致', () {
      expect(IconImport.frames(fixture('valid.dgf')), Dgf1.parse(fixture('valid.dgf')).frames.length);
    });

    test('不是动画的字节返回 0, 不抛异常', () {
      expect(IconImport.frames(fixture('cover96.bin')), 0);
    });
  });
}
