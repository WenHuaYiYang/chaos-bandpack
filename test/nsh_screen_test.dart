import 'dart:typed_data';

import 'package:chaos_bandpack/chaos/delivery.dart';
import 'package:chaos_bandpack/chaos/session.dart';
import 'package:chaos_bandpack/chaos/session_scope.dart';
import 'package:chaos_bandpack/protocol/cc_client.dart';
import 'package:chaos_bandpack/protocol/ops.dart';
import 'package:chaos_bandpack/ui/screen/nsh_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Terminal extends Fake implements NshClient {
  bool busy = false;
  int opens = 0;
  final writes = <String>[];
  final reads = <int>[];
  String pending = 'chaos:/ \$ ls\r\nfont icons\r\n';
  NshStatus status = NshStatus(7, NshState.running, 0);

  int? _lease;

  @override
  int? get lease => _lease;

  @override
  Future<NshStatus> open() async {
    opens++;
    if (busy) throw CcException(CcOp.nshOpen, CcStatus.busy);
    _lease = status.lease;
    return status;
  }

  @override
  Future<void> write(String text) async => writes.add(text);

  @override
  Future<NshRead> read({int capacity = 2048}) async {
    reads.add(capacity);
    final out = pending;
    pending = '';
    return NshRead(status, Uint8List.fromList(out.codeUnits));
  }

  @override
  Future<void> close() async {
    _lease = null;
    status = NshStatus(0, NshState.exited, 0);
  }
}

class _Session extends ChaosSession {
  _Session(this.terminal);

  final _Terminal terminal;

  @override
  bool get isReady => true;

  @override
  BandDevice? get connected => const BandDevice(address: 'AA', name: '测试手环');

  @override
  NshClient? get nsh => terminal;
}

Future<_Session> _boot(WidgetTester tester, _Terminal terminal) async {
  final session = _Session(terminal);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: SessionScope(session: session, child: const NshScreen()),
      ),
    ),
  );
  await tester.pump();
  return session;
}

void main() {
  testWidgets('终端读取输出并在发送后显示回显', (tester) async {
    final terminal = _Terminal();
    await _boot(tester, terminal);
    await tester.tap(find.text('打开会话'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(terminal.opens, 1);
    expect(find.textContaining('font icons'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'uname -a');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(milliseconds: 200));
    expect(terminal.writes, ['uname -a\n']);
    expect(find.text('uname -a'), findsNothing); // 输入框已清空
  });

  testWidgets('繁忙时给出可执行的下一步，而不是一个状态码', (tester) async {
    final terminal = _Terminal()..busy = true;
    await _boot(tester, terminal);
    await tester.tap(find.text('打开会话'));
    // 打开会话会先做几次有界退避, 全部走完才落到最终提示。
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.textContaining('旧终端还没退出'), findsOneWidget);
    expect(find.textContaining('BUSY'), findsNothing);
    expect(terminal.opens, 5);
  });

  testWidgets('未打开会话时输入框不可用，打开后可用', (tester) async {
    final terminal = _Terminal();
    final session = _Session(terminal);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(child: SessionScope(session: session, child: const NshScreen())),
      ),
    );
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.text('打开会话'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });
}
