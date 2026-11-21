import 'dart:io';
import 'dart:typed_data';

import 'package:chaos_bandpack/icon/device_target.dart';
import 'package:chaos_bandpack/project/chaos_project.dart';
import 'package:chaos_bandpack/project/pack_import.dart';
import 'package:test/test.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

/// 合成一个最小但结构合法的 TrueType 文件(head + maxp 两张表)。
///
/// 工程容器只校验 sfnt 结构(魔数 + 表目录不越界), 不解析字形, 所以测试里
/// 没必要拖一个几 MB 的真字体进来。
Uint8List _tinyTtf() {
  const List<String> tags = <String>['head', 'maxp'];
  const int headLen = 54;
  const int maxpLen = 6;
  final int headerLen = 12 + tags.length * 16;
  final int total = headerLen + headLen + maxpLen;
  final ByteData out = ByteData(total);
  out.setUint32(0, 0x00010000); // 版本
  out.setUint16(4, tags.length);
  out.setUint16(6, 16);
  out.setUint16(8, 0);
  out.setUint16(10, 0);
  int off = headerLen;
  for (int i = 0; i < tags.length; i++) {
    final int len = i == 0 ? headLen : maxpLen;
    final int p = 12 + i * 16;
    for (int k = 0; k < 4; k++) {
      out.setUint8(p + k, tags[i].codeUnitAt(k));
    }
    out.setUint32(p + 4, 0); // checksum: 容器不校验
    out.setUint32(p + 8, off);
    out.setUint32(p + 12, len);
    off += len;
  }
  // head 的 unitsPerEm(index 18) 与 indexToLocFormat(index 50)
  out.setUint16(headerLen + 18, 1000);
  out.setInt16(headerLen + 50, 1);
  // maxp 的 numGlyphs(index 4)
  out.setUint16(headerLen + headLen + 4, 3);
  return out.buffer.asUint8List();
}

void main() {
  group('工程容器', () {
    test('图标工程往返: 字节相同, 素材逐字节一致', () {
      final project = ChaosProject(
        device: DeviceTarget.tenPro,
        icons: IconProject(
          info: const PackInfo(
            short: 'chaos',
            display: 'Chaos 图标包',
            title: '图标投递 chaos',
          ),
          images: <String, Uint8List>{
            'alarm': _fixture('cover96.bin'),
          },
        ),
      );
      final Uint8List bytes = ProjectCodec.write(project);
      final ChaosProject back = ProjectCodec.read(bytes);
      expect(back.device, DeviceTarget.tenPro);
      expect(back.icons!.info.short, 'chaos');
      expect(back.icons!.info.display, 'Chaos 图标包');
      expect(back.icons!.images.keys, <String>['alarm']);
      expect(back.icons!.images['alarm'], _fixture('cover96.bin'));
      expect(back.font, isNull);
      // 同样的输入必须打出同样的字节: 时间戳固定, 条目按名字排序
      expect(ProjectCodec.write(back), bytes);
    });

    test('字体工程往返保留子集化选项', () {
      final project = ChaosProject(
        device: DeviceTarget.tenPro,
        font: FontProject(
          info: const PackInfo(short: '文楷', display: 'Chaos 字体', title: '字体投递 文楷'),
          sourceName: '文楷.ttf',
          source: _tinyTtf(),
          charset: 'WITH_TRADITIONAL',
          normalize: false,
          preserve: true,
        ),
      );
      final ChaosProject back = ProjectCodec.read(ProjectCodec.write(project));
      expect(back.font!.charset, 'WITH_TRADITIONAL');
      expect(back.font!.normalize, isFalse);
      expect(back.font!.preserve, isTrue);
      expect(back.font!.sourceName, '文楷.ttf');
      expect(back.font!.source, _tinyTtf());
    });

    test('不是 zip 的字节被拒', () {
      expect(
        () => ProjectCodec.read(Uint8List.fromList(<int>[1, 2, 3, 4, 5])),
        throwsA(isA<ProjectError>()),
      );
    });

    test('空工程写不出来', () {
      expect(
        () => ProjectCodec.write(const ChaosProject(device: DeviceTarget.tenPro)),
        throwsA(isA<ProjectError>()),
      );
    });

    test('导入真实图标投递包, 素材与工程一致', () {
      final ChaosProject project =
          PackImport.read(_fixture('animated-pack.bin'));
      expect(project.device, DeviceTarget.tenPro);
      expect(project.icons!.info.pkg, isNotEmpty);
      expect(project.icons!.info.display, isNotEmpty);
      // 索引文件不是素材槽, 必须被丢掉; 静态图标要原样留下
      expect(project.icons!.images.containsKey('animations'), isFalse);
      expect(project.icons!.images.keys, contains('alarm'));
      for (final MapEntry<String, Uint8List> e in project.icons!.images.entries) {
        expect(e.value, isNotEmpty, reason: e.key);
      }
      // 反推出来的工程必须能原样存盘再读回
      final ChaosProject back = ProjectCodec.read(
        ProjectCodec.write(project),
      );
      expect(back.icons!.images.keys.toSet(),
          project.icons!.images.keys.toSet());
    });

    test('素材名不合法被拒', () {
      expect(
        () => ProjectCodec.write(ChaosProject(
          device: DeviceTarget.tenPro,
          icons: IconProject(
            info: const PackInfo(short: 'a', display: 'b', title: 'c'),
            images: <String, Uint8List>{
              '../evil': _fixture('cover96.bin'),
            },
          ),
        )),
        throwsA(isA<ProjectError>()),
      );
    });
  });
}
