import 'dart:io';
import 'dart:typed_data';

import 'package:chaos_bandpack/icon/device_target.dart';
import 'package:chaos_bandpack/project/chaos_project.dart';
import 'package:chaos_bandpack/project/project_actions.dart';
import 'package:test/test.dart';

void main() {
  group('工程与投递包的打开分派', () {
    test('zip 头走工程解码, 容器头走投递包反推', () {
      final ChaosProject project = ChaosProject(
        device: DeviceTarget.tenPro,
        font: FontProject(
          info: const PackInfo(short: '文楷', display: '字:文楷', title: '字体投递 文楷'),
          sourceName: 'wenkai.ttf',
          source: _tinyTtf(),
        ),
      );
      final Uint8List saved = ProjectCodec.write(project);

      final (ChaosProject back, bool isProject) = ProjectActions.read(saved);
      expect(isProject, isTrue);
      expect(back.font!.info.short, '文楷');

      // 真实投递包: 头不是 PK, 必须落到 PackImport。
      final Uint8List pack = File('test/fixtures/animated-pack.bin').readAsBytesSync();
      final (ChaosProject fromPack, bool isProjectPack) = ProjectActions.read(pack);
      expect(isProjectPack, isFalse);
      expect(fromPack.icons, isNotNull);
      expect(fromPack.icons!.images, isNotEmpty);
    });

    test('太小的文件与超大文件都被拒', () {
      expect(
        () => ProjectActions.read(Uint8List.fromList(<int>[0x50, 0x4b])),
        throwsA(isA<ProjectError>()),
      );
      expect(
        () => ProjectActions.read(Uint8List(ProjectCodec.maxBytes + 1)),
        throwsA(isA<ProjectError>()),
      );
    });

    test('既不是 zip 也不是容器的字节抛 ProjectError', () {
      final Uint8List junk = Uint8List.fromList(List<int>.filled(64, 0x41));
      expect(() => ProjectActions.read(junk), throwsA(isA<ProjectError>()));
    });
  });
}

/// 最小合法 TrueType(与 project_test.dart 同款): 只要求 sfnt 结构与表不越界。
Uint8List _tinyTtf() {
  const int headLen = 54;
  const int maxpLen = 6;
  final int total = 12 + 2 * 16 + headLen + maxpLen;
  final ByteData d = ByteData(total);
  d.setUint32(0, 0x00010000);
  d.setUint16(4, 2);
  d.setUint32(12 + 0, 0x68656164);
  d.setUint32(12 + 8, 12 + 32);
  d.setUint32(12 + 12, headLen);
  d.setUint32(12 + 16, 0x6D617870);
  d.setUint32(12 + 24, 12 + 32 + headLen);
  d.setUint32(12 + 28, maxpLen);
  final int head = 12 + 32;
  d.setUint16(head + 18, 1000);
  d.setInt16(head + 50, 1);
  d.setUint16(head + headLen + 4, 3);
  return d.buffer.asUint8List();
}
