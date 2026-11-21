import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:chaos_bandpack/protocol/cc_client.dart';
import 'package:chaos_bandpack/protocol/ccn1.dart';
import 'package:chaos_bandpack/protocol/frame_link.dart';
import 'package:chaos_bandpack/protocol/crc32.dart';
import 'package:chaos_bandpack/protocol/ops.dart';
import 'package:chaos_bandpack/protocol/wear_packet.dart';

Uint8List hex(String s) {
  final clean = s.replaceAll(RegExp(r'\s+'), '');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String toHex(List<int> b) =>
    b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('CRC-32 与固件同多项式', () {
    test('已知向量', () {
      expect(Crc32.of('123456789'.codeUnits), 0xCBF43926);
      expect(Crc32.of(<int>[]), 0);
    });

    test('分段累加等于一次算完', () {
      final data = hex('43434e310100010034120000');
      final whole = Crc32.of(data);
      final split = Crc32.finalize(
        Crc32.update(Crc32.update(0xFFFFFFFF, data, 0, 4), data, 4),
      );
      expect(split, whole);
    });
  });

  group('金标准向量 (docs/CHAOSCONNECT-V1.hex)', () {
    // HELLO 请求, request_id = 0x1234, 空 payload
    const helloWire = '43434e310100010034120000d0f4a6ad';
    // 同一帧裹进 WearPacket, packet_id = 0x12341234
    const helloPb =
        '080010b4a4d09101b201264a240a100a0c4368616f73436f6e6e65637412001210'
        '43434e310100010034120000d0f4a6ad';

    test('编码出与固件逐字节相同的 CCN1 帧', () {
      final got = ccEncode(
        flags: Ccn1.flagRequest,
        op: CcOp.hello,
        status: CcStatus.ok,
        req: 0x1234,
      );
      expect(toHex(got), helloWire);
    });

    test('解回来字段都对', () {
      final f = ccDecode(hex(helloWire));
      expect(f.flags, Ccn1.flagRequest);
      expect(f.op, CcOp.hello);
      expect(f.status, CcStatus.ok);
      expect(f.req, 0x1234);
      expect(f.len, 0);
    });

    test('裹成 WearPacket 与固件逐字节相同', () {
      final got = PbEnvelope.wrap(hex(helloWire), 0x12341234);
      expect(toHex(got), helloPb);
    });

    test('拆信封拿回原帧与 id', () {
      final p = PbEnvelope.split(hex(helloPb));
      expect(p.id, 0x12341234);
      expect(toHex(p.frame), helloWire);
    });

    test('非 ChaosConnect 命名空间的包被拒', () {
      final bad = Uint8List.fromList(hex(helloPb));
      // 把 "ChaosConnect" 的首字母 C 改成 X
      final at = toHex(bad).indexOf('4368616f73436f6e6e656374');
      bad[at ~/ 2] = 0x58;
      expect(() => PbEnvelope.split(bad), throwsA(isA<PbFormatError>()));
    });

    test('CRC 被改坏就解不出来', () {
      final bad = hex(helloWire);
      bad[15] = bad[15] ^ 0xFF;
      expect(() => ccDecode(bad), throwsA(isA<CcFormatError>()));
    });
  });

  group('帧边界', () {
    test('payload 超上限拒绝', () {
      expect(
        () => ccEncode(
          flags: 0,
          op: 0x11,
          status: 0,
          req: 1,
          payload: List.filled(Ccn1.maxPayload + 1, 0),
        ),
        throwsA(isA<CcFormatError>()),
      );
    });

    test('最大帧可往返', () {
      final payload = List<int>.generate(Ccn1.maxPayload, (i) => i & 0xFF);
      final wire = ccEncode(flags: 0, op: 0x11, status: 0, req: 7, payload: payload);
      final f = ccDecode(wire);
      expect(f.len, Ccn1.maxPayload);
      expect(f.payload.first, 0);
      expect(f.payload.last, (Ccn1.maxPayload - 1) & 0xFF);
    });
  });

  group('请求号与 packet id', () {
    // 金标准向量就是活证据: 帧里 req = 0x1234, 信封里 packet id = 0x12341234,
    // 低 16 位完全相同。固件核对的是这个对应关系, 对不上整帧丢弃。
    test('金标准向量里 req 就是 packet id 的低 16 位', () {
      const helloPb =
          '080010b4a4d09101b201264a240a100a0c4368616f73436f6e6e65637412001210'
          '43434e310100010034120000d0f4a6ad';
      final p = PbEnvelope.split(hex(helloPb));
      expect(p.id & 0xFFFF, ccDecode(p.frame).req);
    });

    test('客户端发出去的每一帧都满足这个对应关系', () async {
      final sent = <Uint8List>[];
      final transport = _RecordingTransport(sent);
      final client = CcClient(transport, packetIdSeed: 0x1000);
      // 不等应答: 只看发出去的字节, 所以用一个不会回包的载波。
      for (var i = 0; i < 5; i++) {
        client.fireAndForget(CcOp.ping);
      }
      expect(sent, hasLength(5));
      for (final packet in sent) {
        final split = PbEnvelope.split(packet);
        expect(ccDecode(split.frame).req, split.id & 0xFFFF,
            reason: 'req 必须等于 packet id 的低 16 位, 否则固件直接丢帧');
      }
      await client.close();
    });

    test('请求号回绕不改变握手时确定的高 16 位', () async {
      final sent = <Uint8List>[];
      final client = CcClient(_RecordingTransport(sent), packetIdSeed: 0x1234fffe);
      for (int i = 0; i < 3; i++) {
        client.fireAndForget(CcOp.ping);
      }
      final packets = sent.map(PbEnvelope.split).toList();
      expect(packets.map((p) => p.id), [0x1234ffff, 0x12340001, 0x12340002]);
      expect(packets.map((p) => ccDecode(p.frame).req), [0xffff, 1, 2]);
      await client.close();
    });

    test('只有匹配请求的应答算有效活动，BUSY 也算', () async {
      final transport = _RecordingTransport([]);
      final client = CcClient(transport);
      final response = client.request(CcOp.nshOpen);
      final p = PbEnvelope.split(transport.sent.single);
      final req = ccDecode(p.frame).req;
      void emit(int flags, int op) {
        transport._in.add(PbEnvelope.wrap(ccEncode(
          flags: flags, op: op, req: req, status: CcStatus.busy, payload: const [],
        ), p.id));
      }
      emit(Ccn1.flagRequest, CcOp.nshOpen);
      emit(Ccn1.flagResponse, CcOp.ping);
      await Future<void>.delayed(Duration.zero);
      expect(client.responsesReceived, 0);
      emit(Ccn1.flagResponse, CcOp.nshOpen);
      expect((await response).status, CcStatus.busy);
      expect(client.responsesReceived, 1);
      await client.close();
    });
  });
}

/// 只记下发出去的字节, 不回任何包。
class _RecordingTransport implements CcTransport {
  _RecordingTransport(this.sent);

  final List<Uint8List> sent;
  final _in = StreamController<Uint8List>.broadcast();
  final _closed = Completer<void>();

  @override
  Stream<Uint8List> get incoming => _in.stream;

  @override
  void send(Uint8List packet) => sent.add(packet);

  @override
  Future<void> close() async {
    if (!_closed.isCompleted) _closed.complete();
    await _in.close();
  }

  @override
  Future<void> get closed => _closed.future;
}
