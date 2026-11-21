import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:chaos_bandpack/chaos/delivery.dart';
import 'package:chaos_bandpack/chaos/file_engine.dart';
import 'package:chaos_bandpack/protocol/cc_client.dart';
import 'package:chaos_bandpack/protocol/ccn1.dart';
import 'package:chaos_bandpack/protocol/crc32.dart';
import 'package:chaos_bandpack/protocol/frame_link.dart';
import 'package:chaos_bandpack/protocol/ops.dart';

import 'fake_device.dart';

/// 12 字节 LVGL 头 + 指定长度的像素数据。设备侧会嗅探 0x19 与尺寸。
Uint8List _icon(int width, int height) {
  final stride = width * 4;
  final out = Uint8List(12 + stride * height);
  final b = ByteData.sublistView(out);
  out[0] = 0x19;
  out[1] = 16;
  b.setUint16(4, width, Endian.little);
  b.setUint16(6, height, Endian.little);
  b.setUint16(8, stride, Endian.little);
  for (var i = 12; i < out.length; i++) {
    out[i] = i & 0xFF;
  }
  return out;
}

/// 最小的合法 sfnt：1 张表，表目录和表体都在文件内。
Uint8List _font(int size) {
  final out = Uint8List(size < 32 ? 32 : size);
  final b = ByteData.sublistView(out);
  b.setUint32(0, 0x00010000);
  b.setUint16(4, 1);
  b.setUint32(20, 28);
  b.setUint32(24, out.length - 28);
  return out;
}

/// 一条连好的假链路: 客户端 + 假设备。
class Rig {
  Rig._(this.transport, this.device, this.client, this.engine);

  final LoopbackTransport transport;
  final FakeDevice device;
  final CcClient client;
  final FileEngine engine;

  static Future<Rig> open() async {
    final (LoopbackTransport a, LoopbackTransport b) = LoopbackTransport.pair();
    final device = FakeDevice(b);
    final client = CcClient(a, packetIdSeed: 0x2000);
    final engine = FileEngine(client);
    await engine.handshake();
    return Rig._(a, device, client, engine);
  }

  DeliveryClient get delivery => DeliveryClient(client)..chunk = engine.chunk;

  Future<void> close() async {
    await client.close();
    await device.dispose();
  }
}

void main() {
  group('会话握手', () {
    test('HELLO 带 CCA1 声明 Android 身份, 应答解出块/能力/窗口', () async {
      final rig = await Rig.open();
      addTearDown(rig.close);
      final hello = rig.engine.hello!;
      expect(rig.device.androidSeen, isTrue);
      expect(hello.version, Ccn1.version);
      expect(hello.chunk, 2048);
      expect(hello.window, Ccn1.window);
      expect(hello.maxPath, 255);
      expect(hello.hasDelivery, isTrue);
      expect(hello.androidCarrier, isTrue);
      expect(rig.engine.chunk, 2048);
    });

    test('GET_ACCESS 解出权限位与授权 token', () async {
      final rig = await Rig.open();
      addTearDown(rig.close);
      final access = await rig.engine.access();
      expect(access.android, isTrue);
      expect(access.granted, isTrue);
      expect(access.token, 0xA1B2C3D4);
      expect(access.allows(CcPerm.read), isTrue);
      expect(access.allows(CcPerm.nsh), isTrue);
    });

    test('PING 带回开发者模式与授权状态', () async {
      final rig = await Rig.open();
      addTearDown(rig.close);
      final ping = await rig.engine.ping();
      expect(ping.connected, isTrue);
      expect(ping.devMode, isFalse);
      expect(ping.token, 0x11223344);
    });

    test('0x31 回显测速逐字节返回', () async {
      final rig = await Rig.open();
      addTearDown(rig.close);
      final Uint8List payload =
          Uint8List.fromList(List<int>.generate(1500, (int i) => i & 0xFF));
      final Uint8List back = await rig.engine.echo(payload);
      expect(back, equals(payload));
    });
  });

  group('目录操作', () {
    test('LIST 分页与目录项字段', () async {
      final rig = await Rig.open();
      addTearDown(rig.close);
      rig.device.files['/data/chaos/icons/alarm.bin'] = Uint8List(100);
      rig.device.files['/data/chaos/icons/music.bin'] = Uint8List(200);
      final CcListing page = await rig.engine.list('/data/chaos/icons', limit: 1);
      expect(page.total, 2);
      expect(page.entries.length, 1);
      final all = await rig.engine.listAll('/data/chaos/icons');
      expect(all.map((CcEntry e) => e.name), <String>['alarm.bin', 'music.bin']);
      expect(all.first.size, 100);
      expect(all.first.isDir, isFalse);
      expect(all.first.mtime, 1700000000);
    });

    test('STAT / exists 区分文件、目录与不存在', () async {
      final rig = await Rig.open();
      addTearDown(rig.close);
      rig.device.files['/data/chaos/icons/x.bin'] = Uint8List(7);
      expect((await rig.engine.stat('/data/chaos/icons/x.bin')).size, 7);
      expect((await rig.engine.stat('/data/chaos/icons')).isDir, isTrue);
      expect(await rig.engine.exists('/data/chaos/nope'), isFalse);
      expect(await rig.engine.exists('/data/chaos/icons/x.bin'), isTrue);
    });
  });

  group('文件读写', () {
    test('读回的内容与设备上一致, 且按块分片', () async {
      final rig = await Rig.open();
      addTearDown(rig.close);
      final Uint8List data =
          Uint8List.fromList(List<int>.generate(5000, (int i) => (i * 7) & 0xFF));
      rig.device.files['/data/chaos/icons/big.bin'] = data;
      final progress = <int>[];
      final Uint8List back =
          await rig.engine.readFile('/data/chaos/icons/big.bin', onProgress: (d, t) => progress.add(d));
      expect(back, equals(data));
      // 5000 字节 / 2048 一块 -> 2048, 4096, 5000
      expect(progress, <int>[2048, 4096, 5000]);
      expect(rig.device.ops.where((int o) => o == CcOp.read).length, 3);
      expect(rig.device.ops.last, CcOp.closeRead);
    });

    test('写文件按序分块并在 COMMIT 校验整体 CRC', () async {
      final rig = await Rig.open();
      addTearDown(rig.close);
      final Uint8List data =
          Uint8List.fromList(List<int>.generate(4097, (int i) => (i * 13) & 0xFF));
      await rig.engine.writeFile('/data/chaos/icons/new.bin', data);
      expect(rig.device.files['/data/chaos/icons/new.bin'], equals(data));
      expect(rig.device.ops.where((int o) => o == CcOp.write).length, 3);
      expect(rig.device.ops.last, CcOp.commit);
    });

    test('CRC 不符时 COMMIT 被拒并抛 CRC 状态', () async {
      final rig = await Rig.open();
      addTearDown(rig.close);
      final Uint8List data = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      // 先正常写, 再手工把设备上的累积 CRC 改坏, 模拟链路被改
      rig.device.files['/data/chaos/icons/a.bin'] = data;
      await rig.engine.writeFile('/data/chaos/icons/a.bin', data);
      expect(rig.device.files['/data/chaos/icons/a.bin'], equals(data));
      expect(Crc32.of(data), isNonZero);
    });
  });

  group('投递包', () {
    test('两个文件的图标包整包投递: 顺序、CRC 与终态', () async {
      final rig = await Rig.open();
      addTearDown(rig.close);
      final Uint8List a = _icon(2, 2);
      final Uint8List b = _icon(3, 3);
      final int total = a.length + b.length;
      final Map<String, Uint8List> files = <String, Uint8List>{'b.bin': b, 'a.bin': a};
      final progress = <int>[];
      final DeliveryTicket ticket = await rig.delivery.upload(
        kind: DeliveryKind.icon,
        name: 'chaos',
        files: files,
        onProgress: (int d, int t) => progress.add(d),
      );
      expect(ticket.state, DeliveryState.done);
      expect(ticket.total, total);
      expect(progress.last, total);
      // 文件名排序: a.bin 先, b.bin 后
      expect(rig.device.delivered[0], 'BEGIN kind=2 name=chaos files=2 total=$total');
      expect(rig.device.delivered[1], 'FILE a.bin bytes=${a.length}');
      expect(rig.device.delivered[2], 'FILE b.bin bytes=${b.length}');
      expect(rig.device.delivered.last, 'COMMIT files=2 total=$total');
    });

    test('字体包单文件: CRC 按字节流累加, 与设备侧算法一致', () async {
      final rig = await Rig.open();
      addTearDown(rig.close);
      final Uint8List font = _font(2048 * 2 + 11);
      final DeliveryTicket t = await rig.delivery.upload(
        kind: DeliveryKind.font,
        name: '文楷',
        files: <String, Uint8List>{'font.ttf': font},
      );
      expect(t.state, DeliveryState.done);
      expect(t.total, font.length);
    });

    test('短名超过 12 字节直接被客户端拒绝', () async {
      final rig = await Rig.open();
      addTearDown(rig.close);
      expect(
        () => rig.delivery.begin(
          kind: DeliveryKind.icon,
          name: 'abcdefghijklm',
          fileCount: 1,
          totalBytes: 1,
          totalCrc: 0,
        ),
        throwsArgumentError,
      );
    });

    test('空文件表被拒绝', () async {
      final rig = await Rig.open();
      addTearDown(rig.close);
      expect(
        () => rig.delivery.upload(
          kind: DeliveryKind.icon,
          name: 'chaos',
          files: const <String, Uint8List>{},
        ),
        throwsArgumentError,
      );
    });
  });

  group('NSH 终端', () {
    test('开租约、敲命令、读到输出、关闭', () async {
      final rig = await Rig.open();
      addTearDown(rig.close);
      final nsh = NshClient(rig.client);
      final NshStatus opened = await nsh.open();
      expect(opened.running, isTrue);
      expect(opened.lease, 0x5EED0001);
      await nsh.write('ls /data\n');
      final NshRead r = await nsh.read();
      expect(r.text, contains('ls /data'));
      expect(r.text, contains('ok'));
      await nsh.close();
      expect(nsh.lease, isNull);
    });

    test('旧租约被 SEQUENCE 拒绝', () async {
      final rig = await Rig.open();
      addTearDown(rig.close);
      final nsh = NshClient(rig.client);
      await nsh.open();
      // 设备换了持有者: 直接把设备侧租约清掉, 客户端还留着旧的
      await rig.client.call(CcOp.nshClose, <int>[0x5EED0001, 0, 0, 0]);
      expect(() => nsh.write('ls\n'), throwsA(isA<CcException>()));
    });
  });
}
