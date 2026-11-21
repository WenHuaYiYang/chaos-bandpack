import 'dart:async';
import 'dart:typed_data';

import 'package:chaos_bandpack/chaos/session.dart';
import 'package:chaos_bandpack/chaos/spp_transport.dart';
import 'package:chaos_bandpack/protocol/cc_client.dart';
import 'package:chaos_bandpack/protocol/ccn1.dart';
import 'package:chaos_bandpack/protocol/frame_link.dart';
import 'package:chaos_bandpack/protocol/ops.dart';
import 'package:chaos_bandpack/protocol/wear_packet.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const band = BandDevice(address: '2C:0D:CF:6E:63:B6', name: '测试手环');

class _Platform implements SppPlatform {
  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<List<({String address, String name})>> bondedDevices() async => [];

  @override
  Future<List<SppPeer>> discover({Duration timeout = const Duration(seconds: 12)}) async => [];

  @override
  Future<bool> pair(String address) async => false;

  final dialed = Completer<void>();
  final opened = Completer<void>();
  final sentHello = Completer<void>();
  late void Function(Uint8List) _onChunk;
  late void Function(String) drop;
  int connections = 0;
  int closes = 0;
  bool answer = false;

  @override
  Future<String> adapterState() async => 'on';

  @override
  void setHandlers({
    required void Function(Uint8List) onChunk,
    required void Function(String) onClosed,
  }) {
    _onChunk = onChunk;
    drop = onClosed;
  }

  @override
  Future<void> connect(String address, String uuid) {
    expect(address, band.address);
    expect(uuid, ChaosSpp.uuid);
    connections++;
    if (!dialed.isCompleted) dialed.complete();
    return opened.future;
  }

  @override
  Future<void> send(Uint8List bytes) async {
    final p = PbEnvelope.split(Uint8List.sublistView(bytes, 4));
    final frame = ccDecode(p.frame);
    if (frame.op != CcOp.hello) return;
    expect(frame.req, p.id & 0xffff);
    if (!sentHello.isCompleted) sentHello.complete();
    if (answer) {
      _onChunk(FrameLink.pack(PbEnvelope.wrap(ccEncode(
        flags: Ccn1.flagResponse,
        op: CcOp.hello,
        status: CcStatus.ok,
        req: frame.req,
        payload: [1, 0, 8, 63, 0, 255, 0, 8, 0, 0, 0],
      ), p.id)));
    }
  }

  @override
  Future<void> close() async {
    closes++;
    if (!opened.isCompleted) {
      opened.completeError(PlatformException(code: 'canceled'));
    }
  }
}

// 模拟固件：空闲 15 秒后只认 HELLO，但不发送底层 closed。
class _LeasePlatform extends _Platform {
  _LeasePlatform(this.now);

  final DateTime Function() now;
  final requests = <int>[];
  DateTime? _lastRequest;
  bool mute = false;
  bool dropList = false;
  int droppedPings = 0;
  Completer<void>? holdClose;

  @override
  Future<void> send(Uint8List bytes) async {
    final packet = PbEnvelope.split(Uint8List.sublistView(bytes, 4));
    final frame = ccDecode(packet.frame);
    expect(frame.req, packet.id & 0xffff);
    requests.add(frame.op);
    if (mute) return;
    final time = now();
    final last = _lastRequest;
    if (frame.op != CcOp.hello &&
        (last == null || time.difference(last) >= const Duration(seconds: 15))) return;
    _lastRequest = time;
    if (dropList && frame.op == CcOp.list) return;
    if (frame.op == CcOp.ping && droppedPings > 0) {
      droppedPings--;
      return;
    }
    final payload = switch (frame.op) {
      CcOp.hello => [1, 0, 8, 63, 0, 255, 0, 8, 0, 0, 0],
      CcOp.getAccess => [1, 1, 0, 2, 63, 0, 0, 0, 0, 0, 0, 0, 1],
      CcOp.ping => [1, 0, 0, 0, 0, 0, 0, 0],
      CcOp.list => [0, 0, 0, 0, 0, 0],
      _ => <int>[],
    };
    _onChunk(FrameLink.pack(PbEnvelope.wrap(ccEncode(
      flags: Ccn1.flagResponse,
      op: frame.op,
      status: frame.op == CcOp.nshOpen ? CcStatus.busy : CcStatus.ok,
      req: frame.req,
      payload: payload,
    ), packet.id)));
  }

  @override
  Future<void> close() async {
    closes++;
    await holdClose?.future;
  }
}

Future<void> _connectLease(ChaosSession session, _LeasePlatform platform) async {
  if (!platform.opened.isCompleted) platform.opened.complete();
  await session.connect(band);
  expect(session.isReady, isTrue, reason: session.error);
}

Future<void> _timedTest(Future<void> Function(FakeAsync) scenario) async {
  var completed = false;
  Object? error;
  StackTrace? trace;
  final time = fakeAsync((time) {
    unawaited(scenario(time).then<void>((_) => completed = true,
        onError: (Object e, StackTrace stack) {
      error = e;
      trace = stack;
    }));
    return time;
  });
  // Stream cancellation can return a shared Future created outside the fake
  // zone. Give the real microtask queue a turn without advancing fake time.
  for (var turn = 0; turn < 10 && error == null && !completed; turn++) {
    time.flushMicrotasks();
    await Future<void>.delayed(Duration.zero);
  }
  time.flushMicrotasks();
  if (error != null) Error.throwWithStackTrace(error!, trace!);
  expect(completed, isTrue, reason: 'elapsed=${time.elapsed}, timers=${time.pendingTimersDebugString}');
  expect(time.pendingTimers, isEmpty);
}

void main() {
  test('心跳跨过手环的 15 秒租期，终端 BUSY 不让连接失效', () => _timedTest((time) async {
    final platform = _LeasePlatform(() => DateTime.utc(2026).add(time.elapsed));
    final session = ChaosSession(platform: platform);
    await _connectLease(session, platform);
    time.elapse(const Duration(seconds: 32));
    expect(platform.requests.where((op) => op == CcOp.ping).length, greaterThan(5));
    expect(session.isReady, isTrue);
    await expectLater(session.nsh!.open(), throwsA(isA<CcException>()
        .having((e) => e.op, '操作', CcOp.nshOpen)
        .having((e) => e.status, '状态', CcStatus.busy)));
    expect(await session.engine!.listAll('/data'), isEmpty);
    expect(session.isReady, isTrue);
    await session.disconnect();
    final count = platform.requests.length;
    time.elapse(const Duration(seconds: 30));
    expect(platform.requests, hasLength(count));
    session.dispose();
  }));

  test('掉一帧心跳先补探测，不断开仍在回应的手环', () => _timedTest((time) async {
    final platform = _LeasePlatform(() => DateTime.utc(2026).add(time.elapsed));
    final session = ChaosSession(platform: platform);
    await _connectLease(session, platform);
    platform.droppedPings = 1;
    time.elapse(const Duration(seconds: 10));
    expect(platform.requests.where((op) => op == CcOp.ping), hasLength(2));
    expect(session.isReady, isTrue);
    expect(platform.closes, 0);
    await session.disconnect();
    session.dispose();
  }));

  test('单次目录应答丢失，但心跳正常，不断开会话', () => _timedTest((time) async {
    final platform = _LeasePlatform(() => DateTime.utc(2026).add(time.elapsed));
    final session = ChaosSession(platform: platform);
    await _connectLease(session, platform);
    platform.dropList = true;
    final pending = expectLater(session.engine!.listAll('/data'), throwsA(isA<CcRequestTimeout>()
        .having((e) => e.op, '操作', CcOp.list)));
    time.elapse(const Duration(seconds: 15));
    await pending;
    expect(session.isReady, isTrue);
    expect(platform.closes, 0);
    platform.dropList = false;
    expect(await session.engine!.listAll('/data'), isEmpty);
    await session.disconnect();
    session.dispose();
  }));

  test('串口未通知断开，心跳仍能释放旧连接并直接重连', () => _timedTest((time) async {
    final platform = _LeasePlatform(() => DateTime.utc(2026).add(time.elapsed));
    final session = ChaosSession(platform: platform);
    await _connectLease(session, platform);
    time.elapse(const Duration(seconds: 6));
    platform.mute = true;
    platform.holdClose = Completer<void>();
    final pending = expectLater(session.engine!.listAll('/data'), throwsA(isA<CcException>()));
    time.elapse(const Duration(seconds: 7));
    expect(session.isReady, isTrue); // 第一帧没回，第二帧仍在等。
    time.elapse(const Duration(seconds: 4));
    await pending;
    expect(session.state, LinkState.failed);
    expect(session.error, contains('没有回复心跳'));
    expect(session.reconnectDevice, band);
    expect(session.engine, isNull);
    expect(session.releasing, isTrue);
    expect(platform.closes, 1);
    await session.connect(band);
    expect(platform.connections, 1); // 原生还没关完，不会抢占旧串口。
    platform.holdClose!.complete();
    await session.disconnect(silent: true); // 等待同一份关闭任务，不改变失败状态。
    expect(session.releasing, isFalse);
    platform.mute = false;
    await _connectLease(session, platform);
    expect(platform.connections, 2);
    expect(platform.requests.where((op) => op == CcOp.hello), hasLength(2));
    expect(platform.requests.where((op) => op == CcOp.list), hasLength(1)); // 不偷偷重放。
    await session.disconnect();
    session.dispose();
  }));
  test('平台还没打开串口时可取消，第二次 connect 不会抢占', () async {
    final platform = _Platform();
    final session = ChaosSession(platform: platform);
    addTearDown(session.dispose);
    final connecting = session.connect(band);
    await platform.dialed.future;
    expect(session.state, LinkState.connecting);
    await session.connect(band);
    expect(platform.connections, 1);
    await session.disconnect();
    await connecting;
    expect(platform.closes, 1);
    expect(platform.sentHello.isCompleted, isFalse);
    expect(session.state, LinkState.idle);
    expect(session.error, isNull);
  });

  test('取消 HELLO 会立即结束等回复的请求', () async {
    final platform = _Platform();
    final session = ChaosSession(platform: platform);
    addTearDown(session.dispose);
    final connecting = session.connect(band);
    await platform.dialed.future;
    platform.opened.complete();
    await platform.sentHello.future;
    expect(session.state, LinkState.handshaking);
    final observed = <(LinkState, bool)>[];
    session.addListener(() => observed.add((session.state, session.releasing)));
    await session.disconnect().timeout(const Duration(seconds: 1));
    await connecting;
    expect(observed.last, (LinkState.idle, false));
    expect(platform.closes, 1);
    expect(session.state, LinkState.idle);
    expect(session.error, isNull);
  });

  test('在 connect 回复前断开不丢失原因，也不发出 HELLO', () async {
    final platform = _Platform();
    final session = ChaosSession(platform: platform);
    addTearDown(session.dispose);
    final connecting = session.connect(band);
    await platform.dialed.future;
    platform.opened.complete();
    platform.drop('手环刚打开就关闭了串口');
    await connecting;
    expect(platform.closes, 1);
    expect(platform.sentHello.isCompleted, isFalse);
    expect(session.state, LinkState.failed);
    expect(session.error, '手环刚打开就关闭了串口');
  });

  test('HELLO 期间断开和底层无法连接显示不同阶段', () async {
    final platform = _Platform();
    final session = ChaosSession(platform: platform);
    addTearDown(session.dispose);
    final connecting = session.connect(band);
    await platform.dialed.future;
    platform.opened.complete();
    await platform.sentHello.future;
    platform.drop('对端关闭串口');
    await connecting;
    expect(session.state, LinkState.failed);
    expect(session.error, '蓝牙串口已打开，但握手没完成：对端关闭串口');
  });

  test('成功只在实际收到匹配的 HELLO 后发布', () async {
    final platform = _Platform()..answer = true;
    final session = ChaosSession(platform: platform);
    addTearDown(session.dispose);
    final connecting = session.connect(band);
    await platform.dialed.future;
    expect(session.isReady, isFalse);
    platform.opened.complete();
    await connecting;
    expect(session.isReady, isTrue);
    expect(session.connected, band);
    expect(session.hello?.chunk, 2048);
    await session.disconnect();
  });
}
