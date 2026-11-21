import 'dart:async';
import 'dart:typed_data';

import 'package:chaos_bandpack/chaos/delivery.dart';
import 'package:chaos_bandpack/chaos/file_engine.dart';
import 'package:chaos_bandpack/chaos/session.dart';
import 'package:chaos_bandpack/chaos/session_scope.dart';
import 'package:chaos_bandpack/protocol/cc_client.dart';
import 'package:chaos_bandpack/protocol/ops.dart';
import 'package:chaos_bandpack/ui/screen/device_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _band = BandDevice(address: '00:01:02:03:04:05', name: '测试手环');
const _root = '/data/chaos';

class _Files extends Fake implements FileEngine {
  final paths = <String>[];
  late Future<List<CcEntry>> Function(String) listResult;

  @override
  int get chunk => 2048;

  @override
  Future<List<CcEntry>> listAll(String path, {int limit = 16}) {
    paths.add(path);
    return listResult(path);
  }
}

class _Terminal extends Fake implements NshClient {
  bool busy = false;
  int opens = 0;
  int reads = 0;
  final writes = <String>[];
  final status = NshStatus(123, NshState.running, 0);

  @override
  Future<NshStatus> open() async {
    opens++;
    if (busy) throw CcException(CcOp.nshOpen, CcStatus.busy);
    return status;
  }

  @override
  Future<void> write(String text) async => writes.add(text);

  @override
  Future<NshRead> read({int capacity = 2048}) async {
    reads++;
    return NshRead(status, Uint8List.fromList('old terminal output'.codeUnits));
  }
}

class _Session extends ChaosSession {
  _Session(this._files, this._terminal);

  _Files _files;
  _Terminal _terminal;
  final replacementFiles = _Files();
  final replacementTerminal = _Terminal();
  final attempts = <BandDevice>[];
  bool _lost = false;
  bool _releasing = false;

  @override
  LinkState get state => _lost ? LinkState.failed : LinkState.ready;

  @override
  bool get isReady => !_lost;

  @override
  bool get releasing => _releasing;

  @override
  BandDevice? get reconnectDevice => _band;

  @override
  BandDevice? get connected => _lost ? null : _band;

  @override
  String? get error => _lost ? '手环连接已断开' : null;

  @override
  String? get adapter => 'on';

  @override
  List<BandDevice> get devices => [_band];

  @override
  FileEngine? get engine => _lost ? null : _files;

  @override
  NshClient? get nsh => _lost ? null : _terminal;

  @override
  CcAccess? get access => _lost
      ? null
      : CcAccess(
          android: true,
          policy: CcPolicy.allow,
          authState: 0,
          mask: CcPerm.read | CcPerm.nsh,
          token: 0,
          granted: true,
        );

  void loseLink() {
    _lost = true;
    _releasing = true;
    notifyListeners();
  }

  void finishRelease() {
    _releasing = false;
    notifyListeners();
  }

  @override
  Future<void> connect(BandDevice device) async {
    attempts.add(device);
    _files = replacementFiles;
    _terminal = replacementTerminal;
    _lost = false;
    notifyListeners();
  }
}

Future<void> _boot(WidgetTester tester, _Session session) async {
  tester.view.physicalSize = const Size(480, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: SessionScope(session: session, child: const DeviceScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('release gates one-tap reconnect without replaying stale operations', (tester) async {
    final session = _Session(_Files(), _Terminal());
    await _boot(tester, session);
    expect(find.text('打开文件管理'), findsOneWidget);
    expect(find.text('打开终端'), findsOneWidget);

    session.loseLink();
    await tester.pump();
    final reconnect = find.ancestor(of: find.text('重连'), matching: find.bySubtype<FilledButton>());
    expect(tester.widget<FilledButton>(reconnect).onPressed, isNull);
    expect(find.text('正在释放旧连接…'), findsOneWidget);
    expect(find.text('手环连接已断开'), findsOneWidget);
    expect(session.attempts, isEmpty);

    session.finishRelease();
    await tester.pump();
    expect(tester.widget<FilledButton>(reconnect).onPressed, isNotNull);
    await tester.tap(find.text('重连'));
    await tester.pumpAndSettle();
    expect(session.attempts, [_band]);
    // 重连后不会自己把旧操作重放一遍。
    expect(session.replacementFiles.paths, isEmpty);
    expect(session.replacementTerminal.opens, 0);
    expect(session.replacementTerminal.writes, isEmpty);
    expect(find.text('打开文件管理'), findsOneWidget);
  });

  testWidgets('设备页把文件与终端拆成两个入口，链路状态不受影响', (tester) async {
    final session = _Session(_Files(), _Terminal());
    await _boot(tester, session);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('NSH 终端'), findsWidgets); // 权限表里也有一行同名
    expect(find.text('安装资源包'), findsOneWidget);
    expect(find.text('重连'), findsNothing);
    expect(session.isReady, isTrue);
    expect(session.attempts, isEmpty);
  });
}

