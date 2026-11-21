import 'dart:typed_data';

import 'package:chaos_bandpack/chaos/beauty_sync.dart';
import 'package:chaos_bandpack/chaos/session.dart';
import 'package:chaos_bandpack/chaos/session_scope.dart';
import 'package:chaos_bandpack/icon/device_target.dart';
import 'package:chaos_bandpack/pack/beauty_pack.dart';
import 'package:chaos_bandpack/ui/screen/beauty_pack_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final target in DeviceTarget.values) {
    testWidgets('字体美化包预览：${target.label}', (tester) async {
      final bytes = Uint8List(32);
      final header = ByteData.sublistView(bytes);
      header.setUint32(0, 0x00010000);
      header.setUint16(4, 1);
      header.setUint32(20, 28);
      header.setUint32(24, 4);
      final pack = BeautyPack(
        kind: BeautyKind.font,
        device: target,
        name: '素黑',
        files: {'font.ttf': bytes},
      );
      final session = ChaosSession();
      addTearDown(session.dispose);
      await tester.pumpWidget(MaterialApp(home: Material(child: SessionScope(
        session: session,
        child: BeautyPackScreen(pack: pack, fileName: '素黑.chp'),
      ))));
      await tester.pumpAndSettle();
      expect(find.text('素黑.chp'), findsOneWidget);
      expect(find.text('小米手环 ${target.label} · 字体 · 1 个文件'), findsOneWidget);
      expect(find.text('font.ttf'), findsOneWidget);
      expect(find.textContaining(target == DeviceTarget.tenPro ? '连接手环' : '暂不支持直传'), findsOneWidget);
      final button = find.ancestor(of: find.text('同步到手环'), matching: find.bySubtype<FilledButton>());
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
    });
  }

  test('文件流超过 CHP 最大长度时不会送到解码器', () async {
    final oversized = Uint8List(BeautyPack.maxBytes + 1);
    await expectLater(BeautySync.readBounded(Stream.value(oversized)), throwsA(isA<BeautyPackError>()));
  });
}
