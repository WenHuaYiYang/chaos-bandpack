import 'dart:typed_data';

import 'package:chaos_bandpack/chaos/session.dart';
import 'package:chaos_bandpack/chaos/spp_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一个只回答"设备有哪些"的假平台。真平台要蓝牙硬件, 这里要测的是会话层
/// 怎么把搜索结果并进状态 —— 那部分与硬件无关。
class _FakeSpp implements SppPlatform {
  _FakeSpp({this.found = const <SppPeer>[], this.bonded = const <({String address, String name})>[]});

  List<SppPeer> found;
  List<({String address, String name})> bonded;
  int discoverCalls = 0;
  int bondCalls = 0;
  Object? discoverError;
  bool pairResult = true;

  @override
  Future<String> adapterState() async => 'on';

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<List<({String address, String name})>> bondedDevices() async => bonded;

  @override
  Future<List<SppPeer>> discover({Duration timeout = const Duration(seconds: 12)}) async {
    discoverCalls++;
    if (discoverError != null) throw discoverError!;
    return found;
  }

  @override
  Future<bool> pair(String address) async {
    bondCalls++;
    return pairResult;
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
  test('搜索把附近的设备单独存一份, 不动已配对列表', () async {
    final fake = _FakeSpp(
      bonded: <({String address, String name})>[(address: 'AA:BB:CC:DD:EE:01', name: '手环')],
      found: <SppPeer>[
        const SppPeer(address: 'AA:BB:CC:DD:EE:02', name: '新设备', paired: false),
      ],
    );
    final ChaosSession session = ChaosSession(platform: fake);
    await session.scan();
    expect(session.devices.length, 1);

    await session.search();
    expect(fake.discoverCalls, 1);
    expect(session.peers.single.address, 'AA:BB:CC:DD:EE:02');
    // 已配对列表还是原来那一台: 搜到未配对的设备不代表它已经能连。
    expect(session.devices.single.address, 'AA:BB:CC:DD:EE:01');
    expect(session.searching, isFalse);
    expect(session.error, isNull);
  });

  test('搜索期间 searching 为真, 结束后复位', () async {
    final fake = _FakeSpp();
    final ChaosSession session = ChaosSession(platform: fake);
    final Future<void> job = session.search();
    expect(session.searching, isTrue);
    await job;
    expect(session.searching, isFalse);
  });

  test('搜索失败时清空上一次结果并给出原因', () async {
    final fake = _FakeSpp(found: <SppPeer>[const SppPeer(address: 'AA:BB:CC:DD:EE:03', name: '旧', paired: false)]);
    final ChaosSession session = ChaosSession(platform: fake);
    await session.search();
    expect(session.peers, isNotEmpty);

    fake.discoverError = StateError('蓝牙未开启');
    await session.search();
    expect(session.peers, isEmpty);
    expect(session.error, contains('蓝牙未开启'));
    expect(session.searching, isFalse);
  });

  test('配对成功后重读已配对列表', () async {
    final fake = _FakeSpp(
      found: <SppPeer>[const SppPeer(address: 'AA:BB:CC:DD:EE:04', name: '手环', paired: false)],
    );
    final ChaosSession session = ChaosSession(platform: fake);
    await session.search();
    fake.bonded = <({String address, String name})>[(address: 'AA:BB:CC:DD:EE:04', name: '手环')];

    final bool ok = await session.pair(session.peers.single);
    expect(ok, isTrue);
    expect(fake.bondCalls, 1);
    expect(session.devices.single.address, 'AA:BB:CC:DD:EE:04');
  });
}
