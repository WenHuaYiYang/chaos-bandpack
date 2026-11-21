import 'dart:typed_data';

import 'package:chaos_bandpack/chaos/session.dart';
import 'package:chaos_bandpack/chaos/session_scope.dart';
import 'package:chaos_bandpack/chaos/spp_transport.dart';
import 'package:chaos_bandpack/ui/screen/device_screen.dart';
import 'package:chaos_bandpack/ui/theme/paper_palette.dart';
import 'package:chaos_bandpack/ui/theme/tone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSpp implements SppPlatform {
  _FakeSpp({this.found = const <SppPeer>[], this.bonded = const <({String address, String name})>[]});

  List<SppPeer> found;
  List<({String address, String name})> bonded;
  int discoverCalls = 0;
  Object? pairError;

  @override
  Future<String> adapterState() async => 'on';

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<List<({String address, String name})>> bondedDevices() async => bonded;

  @override
  Future<List<SppPeer>> discover({Duration timeout = const Duration(seconds: 12)}) async {
    discoverCalls++;
    return found;
  }

  @override
  Future<bool> pair(String address) async {
    final error = pairError;
    if (error != null) throw error;
    return true;
  }

  @override
  Future<void> connect(String address, String uuid) async {}

  @override
  Future<void> send(Uint8List bytes) async {}

  @override
  Future<void> close() async {}

  @override
  void setHandlers({
    required void Function(Uint8List chunk) onChunk,
    required void Function(String reason) onClosed,
  }) {}
}

void main() {
  Future<ChaosSession> boot(WidgetTester tester, _FakeSpp fake) async {
    tester.view.physicalSize = const Size(960, 1920);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final ChaosSession session = ChaosSession(platform: fake);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: PaperPalette.theme(Brightness.light),
        home: SessionScope(
          session: session,
          child: ToneScope(
            tone: TonePalette.device(tester.element(find.byType(Container).first)),
            child: const DeviceScreen(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    return session;
  }

  testWidgets('设备页有搜索入口, 搜到的未配对设备可以就地配对', (WidgetTester tester) async {
    final fake = _FakeSpp(
      bonded: <({String address, String name})>[(address: 'AA:BB:CC:DD:EE:01', name: '旧手环')],
      found: <SppPeer>[
        const SppPeer(address: 'AA:BB:CC:DD:EE:02', name: '新手环', paired: false),
        const SppPeer(address: 'AA:BB:CC:DD:EE:01', name: '旧手环', paired: true),
      ],
    );
    final ChaosSession session = await boot(tester, fake);
    await session.scan();
    await tester.pump();

    expect(find.text('搜索附近设备'), findsOneWidget);

    await tester.tap(find.text('搜索附近设备'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(fake.discoverCalls, 1);
    // 新搜到的未配对设备列出来, 已配对的那台不该重复出现。
    expect(find.text('新手环'), findsOneWidget);
    expect(find.text('旧手环'), findsOneWidget);
    expect(find.text('配对'), findsOneWidget);
  });

  testWidgets('配对失败在未连接时可见，设备不会移到已配对', (WidgetTester tester) async {
    const message = 'Windows 没有确认已配对。请在手环重新点「发起蓝牙配对」，再试一次';
    final fake = _FakeSpp(found: const <SppPeer>[
      SppPeer(address: 'AA:BB:CC:DD:EE:02', name: '新手环', paired: false),
    ])..pairError = StateError(message);
    final session = await boot(tester, fake);
    await session.scan();
    await tester.pumpAndSettle();

    await tester.tap(find.text('搜索附近设备'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('配对'));
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(find.text('配对'), findsOneWidget);
    expect(session.devices, isEmpty);
    expect(session.isReady, isFalse);

    await tester.ensureVisible(find.text('再搜一次'));
    await tester.tap(find.text('再搜一次'));
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);
  });

  testWidgets('搜完什么都没有时给出人话, 不是空白', (WidgetTester tester) async {
    final fake = _FakeSpp();
    final ChaosSession session = await boot(tester, fake);
    await session.scan();
    await tester.pump();

    await tester.tap(find.text('搜索附近设备'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('附近没有搜到新设备'), findsOneWidget);
    expect(find.text('再搜一次'), findsOneWidget);
  });
}
