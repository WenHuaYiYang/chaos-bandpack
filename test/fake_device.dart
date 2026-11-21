import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chaos_bandpack/chaos/delivery.dart';
import 'package:chaos_bandpack/protocol/ccn1.dart';
import 'package:chaos_bandpack/protocol/crc32.dart';
import 'package:chaos_bandpack/protocol/frame_link.dart';
import 'package:chaos_bandpack/protocol/ops.dart';
import 'package:chaos_bandpack/protocol/wear_packet.dart';

/// 假设备端: 按 supervisor/bridge 里的语义应答。
///
/// 价值在于把客户端每个字节布局钉在设备行为上 —— 请求怎么拼、应答怎么解、
/// 出错怎么抛, 全程走真实的 CCN1 编码与 WearPacket 包裹。
class FakeDevice {
  FakeDevice(this._transport) {
    _sub = _transport.incoming.listen((Uint8List packet) {
      _queue = _queue.then((_) => _handle(packet));
    });
  }

  final LoopbackTransport _transport;
  late final StreamSubscription<Uint8List> _sub;
  Future<void> _queue = Future<void>.value();

  final Map<String, Uint8List> files = <String, Uint8List>{};
  final Set<String> dirs = <String>{'/', '/data', '/data/chaos', '/data/chaos/icons'};
  int devMode = 0;
  int mask = 0x3F;
  int chunk = 2048;
  bool androidSeen = false;
  bool denyWrite = false;

  /// 客户端发来的操作码, 按顺序记录。
  final List<int> ops = <int>[];

  Uint8List? _readHandle;

  Uint8List? _writeBuf;
  String? _writePath;
  int _writeAt = 0;
  int _writeCrc = 0xFFFFFFFF;

  int deliveryPolicy = CcPolicy.ask;
  List<int> deliveryConsentStates = const [DeliveryState.awaitingConsent, DeliveryState.allowed];
  bool truncateDeliveryCommitReply = false;
  int? deliveryCommitReplyState;
  final List<CcFrame> deliveryRequests = <CcFrame>[];
  final List<String> delivered = <String>[];

  int _nextToken = 0xC0FFEE01;
  int? _token;
  int _consentPoll = 0;
  int _packKind = 0;
  int _packFiles = 0;
  int _packTotal = 0;
  int _packExpectedCrc = 0;
  int _packCrc = 0xFFFFFFFF;
  int _packDone = 0;
  int _packFilesDone = 0;
  int _packState = DeliveryState.idle;
  final _packNames = <String>{};
  String? _openName;
  int _openLen = 0;
  int _openExpectedCrc = 0;
  int _openAt = 0;
  int _openCrc = 0xFFFFFFFF;
  BytesBuilder _openData = BytesBuilder();

  int? _lease;
  BytesBuilder _nshOut = BytesBuilder();

  Future<void> _handle(Uint8List packet) async {
    final PbPacket pkt = PbEnvelope.split(packet);
    final CcFrame f = ccDecode(pkt.frame);
    ops.add(f.op);
    var status = CcStatus.ok;
    Uint8List out = Uint8List(0);
    switch (f.op) {
      case CcOp.hello:
        androidSeen = f.payload.length == 4 &&
            f.payload[0] == 0x43 && f.payload[1] == 0x43 &&
            f.payload[2] == 0x41 && f.payload[3] == 0x31;
        out = Uint8List(11);
        out[0] = Ccn1.version;
        ByteData.view(out.buffer).setUint16(1, chunk, Endian.little);
        out[3] = 0x02 | 0x10 | 0x20;
        out[4] = devMode;
        ByteData.view(out.buffer).setUint16(5, 255, Endian.little);
        ByteData.view(out.buffer).setUint32(7, Ccn1.window, Endian.little);
      case CcOp.getAccess:
        out = Uint8List(16);
        out[0] = 1;
        out[1] = androidSeen ? 1 : 0;
        out[2] = CcPolicy.allow;
        out[3] = 2;
        ByteData.view(out.buffer).setUint32(4, mask, Endian.little);
        ByteData.view(out.buffer).setUint32(8, 0xA1B2C3D4, Endian.little);
        out[12] = 1;
      case CcOp.ping:
        out = Uint8List(8);
        out[0] = 1;
        out[1] = devMode;
        out[2] = CcPolicy.allow;
        out[3] = 2;
        ByteData.view(out.buffer).setUint32(4, 0x11223344, Endian.little);
      case CcOp.echo:
        out = Uint8List.fromList(f.payload);
      case CcOp.getDev:
        out = Uint8List.fromList(<int>[devMode]);
      case CcOp.setDev:
        if (f.payload.isNotEmpty && f.payload[0] != 0 && denyWrite) {
          status = CcStatus.access;
        } else {
          devMode = (f.payload.isNotEmpty && f.payload[0] != 0) ? 1 : 0;
        }
      case CcOp.list:
        final r = _list(f.payload);
        status = r.$1;
        out = r.$2;
      case CcOp.stat:
        final r = _stat(f.payload);
        status = r.$1;
        out = r.$2;
      case CcOp.openRead:
        final data = files[_pathOf(f.payload)];
        if (data == null) {
          status = CcStatus.notFound;
        } else {
          _readHandle = data;
          out = Uint8List(4);
          ByteData.view(out.buffer).setUint32(0, data.length, Endian.little);
        }
      case CcOp.read:
        final h = _readHandle;
        if (h == null) {
          status = CcStatus.sequence;
        } else {
          final b = ByteData.sublistView(f.payload);
          final off = b.getUint32(0, Endian.little);
          final want = b.getUint16(4, Endian.little);
          if (off < h.length) {
            final end = (off + want) > h.length ? h.length : off + want;
            out = Uint8List.fromList(h.sublist(off, end));
          }
        }
      case CcOp.closeRead:
        _readHandle = null;
      case CcOp.openWrite:
        final path = _pathOf(f.payload);
        final n = _pathLen(f.payload) + 2;
        final b = ByteData.sublistView(f.payload);
        final want = b.getUint32(n, Endian.little);
        _writeBuf = Uint8List(want);
        _writePath = path;
        _writeAt = 0;
        _writeCrc = 0xFFFFFFFF;
      case CcOp.write:
        final w = _writeBuf;
        if (w == null) {
          status = CcStatus.sequence;
        } else {
          final b = ByteData.sublistView(f.payload);
          final off = b.getUint32(0, Endian.little);
          final body = Uint8List.sublistView(f.payload, 4);
          if (off != _writeAt) {
            status = CcStatus.sequence;
          } else if (_writeAt + body.length > w.length) {
            status = CcStatus.tooLarge;
          } else {
            w.setRange(_writeAt, _writeAt + body.length, body);
            _writeCrc = Crc32.update(_writeCrc, body);
            _writeAt += body.length;
            out = Uint8List(8);
            ByteData.view(out.buffer).setUint32(0, _writeAt, Endian.little);
            ByteData.view(out.buffer)
                .setUint32(4, Crc32.finalize(_writeCrc), Endian.little);
          }
        }
      case CcOp.commit:
        final w = _writeBuf;
        if (w == null || _writeAt != w.length) {
          status = CcStatus.io;
        } else if (ByteData.sublistView(f.payload).getUint32(0, Endian.little) !=
            Crc32.finalize(_writeCrc)) {
          status = CcStatus.crc;
          _writeBuf = null;
        } else {
          files[_writePath!] = w;
          _writeBuf = null;
        }
      case CcOp.abort:
        _writeBuf = null;
      case CcOp.deliveryBegin:
      case CcOp.deliveryStatus:
      case CcOp.deliveryOpenFile:
      case CcOp.deliveryWrite:
      case CcOp.deliveryEndFile:
      case CcOp.deliveryCommit:
      case CcOp.deliveryAbort:
        deliveryRequests.add(f);
        status = _dispatchDelivery(f.op, f.payload);
        if (status == CcStatus.ok) {
          out = _ticket();
          if (f.op == CcOp.deliveryCommit) {
            if (deliveryCommitReplyState != null) out[4] = deliveryCommitReplyState!;
            if (truncateDeliveryCommitReply) out = Uint8List.sublistView(out, 0, 4);
          }
        }
      case CcOp.nshOpen:
        _lease = 0x5EED0001;
        out = _nshStatus(NshState.running);
      case CcOp.nshWrite:
        if (ByteData.sublistView(f.payload).getUint32(0, Endian.little) != _lease) {
          status = CcStatus.sequence;
        } else {
          final line = String.fromCharCodes(f.payload, 4).trim();
          _nshOut.add(Uint8List.fromList(
              Uint8List.fromList('chaos:/ \$ '.codeUnits).toList() +
                  Uint8List.fromList(line.codeUnits).toList() +
                  Uint8List.fromList('\r\nok\r\n'.codeUnits).toList()));
        }
      case CcOp.nshRead:
        if (ByteData.sublistView(f.payload).getUint32(0, Endian.little) != _lease) {
          status = CcStatus.sequence;
        } else {
          final cap = ByteData.sublistView(f.payload).getUint16(4, Endian.little);
          final all = _nshOut.takeBytes();
          _nshOut = BytesBuilder();
          final n = all.length > cap ? cap : all.length;
          out = Uint8List(9 + n);
          ByteData.view(out.buffer).setUint32(0, _lease!, Endian.little);
          out[4] = NshState.running;
          out.setRange(9, 9 + n, all);
        }
      case CcOp.nshClose:
        _lease = null;
        out = _nshStatus(NshState.exited);
      default:
        status = CcStatus.unsupported;
    }
    final Uint8List reply = ccEncode(
      flags: Ccn1.flagResponse,
      op: f.op,
      status: status,
      req: f.req,
      payload: out,
    );
    _transport.send(PbEnvelope.wrap(reply, pkt.id));
  }

  int _dispatchDelivery(int op, Uint8List payload) {
    if (!androidSeen) return CcStatus.access;
    if (op == CcOp.deliveryBegin) return _begin(payload);
    if (payload.length < 4 || _token == null ||
        ByteData.sublistView(payload).getUint32(0, Endian.little) != _token) {
      return CcStatus.sequence;
    }
    if (op == CcOp.deliveryAbort) {
      if (payload.length != 4) return CcStatus.bad;
      _token = null;
      _packState = DeliveryState.idle;
      _packDone = _packTotal = 0;
      _openName = null;
      _openData.clear();
      return CcStatus.ok;
    }
    if (op == CcOp.deliveryStatus) {
      if (payload.length != 4) return CcStatus.bad;
      if (_packState == DeliveryState.awaitingConsent &&
          _consentPoll < deliveryConsentStates.length) {
        _packState = deliveryConsentStates[_consentPoll++];
      }
      return CcStatus.ok;
    }
    final status = _packState == DeliveryState.allowed || _packState == DeliveryState.transferring
        ? switch (op) {
            CcOp.deliveryOpenFile => _open(payload),
            CcOp.deliveryWrite => _write(payload),
            CcOp.deliveryEndFile => _endFile(payload),
            CcOp.deliveryCommit => _commitPack(payload),
            _ => CcStatus.unsupported,
          }
        : CcStatus.access;
    if (status != CcStatus.ok) {
      _packState = DeliveryState.failed;
      _openName = null;
      _openData.clear();
    }
    return status;
  }

  int _begin(Uint8List payload) {
    if (_packState == DeliveryState.awaitingConsent ||
        _packState == DeliveryState.allowed ||
        _packState == DeliveryState.transferring) {
      return CcStatus.busy;
    }
    if (payload.length < 12) return CcStatus.bad;
    final kind = payload[0];
    final n = payload[1];
    if ((kind != DeliveryKind.font && kind != DeliveryKind.icon) ||
        n < 1 || n > 12 || payload.length != 12 + n || payload[1 + n] == 32) {
      return CcStatus.bad;
    }
    final nameBytes = Uint8List.sublistView(payload, 2, 2 + n);
    if (nameBytes.any((x) => x < 32 || x == 127 || (kind == DeliveryKind.icon && (x <= 32 || x >= 127)))) {
      return CcStatus.bad;
    }
    final String name;
    try {
      name = utf8.decode(nameBytes);
    } on FormatException {
      return CcStatus.bad;
    }
    if (name.runes.any((c) => (c >= 127 && c <= 159) ||
        (c >= 0x202a && c <= 0x202e) || (c >= 0x2066 && c <= 0x2069))) {
      return CcStatus.bad;
    }
    final b = ByteData.sublistView(payload);
    final count = b.getUint16(2 + n, Endian.little);
    final total = b.getUint32(4 + n, Endian.little);
    if (count < 1 || count > 256 || (kind == DeliveryKind.font && count != 1) ||
        total < 1 || total > 32 * 1024 * 1024) {
      return CcStatus.tooLarge;
    }
    if (deliveryPolicy == CcPolicy.deny) return CcStatus.access;
    _packKind = kind;
    _packFiles = count;
    _packTotal = total;
    _packExpectedCrc = b.getUint32(8 + n, Endian.little);
    _packCrc = Crc32.update(0xFFFFFFFF, payload, 0, payload.length - 4);
    _packDone = 0;
    _packFilesDone = 0;
    _packNames.clear();
    _openName = null;
    _openData.clear();
    _consentPoll = 0;
    _token = _nextToken++;
    _packState = deliveryPolicy == CcPolicy.ask ? DeliveryState.awaitingConsent : DeliveryState.allowed;
    delivered.add('BEGIN kind=$_packKind name=$name files=$_packFiles total=$_packTotal');
    return CcStatus.ok;
  }

  Uint8List _ticket() {
    final out = Uint8List(13);
    final b = ByteData.view(out.buffer);
    b.setUint32(0, _token ?? 0, Endian.little);
    out[4] = _packState;
    b.setUint32(5, _packDone, Endian.little);
    b.setUint32(9, _packTotal, Endian.little);
    return out;
  }

  int _open(Uint8List payload) {
    if (_openName != null || _packFilesDone >= _packFiles || payload.length < 14) {
      return CcStatus.bad;
    }
    final b = ByteData.sublistView(payload);
    final n = b.getUint16(4, Endian.little);
    if (n < 1 || n > 64 || payload.length != 14 + n) return CcStatus.bad;
    final String name;
    try {
      name = ascii.decode(Uint8List.sublistView(payload, 6, 6 + n));
    } on FormatException {
      return CcStatus.bad;
    }
    if (_packKind == DeliveryKind.font ? name != 'font.ttf' : !_iconFileName.hasMatch(name)) {
      return CcStatus.bad;
    }
    if (!_packNames.add(name)) return CcStatus.exist;
    final length = b.getUint32(6 + n, Endian.little);
    final max = _packKind == DeliveryKind.font ? 0xffffff : 0x100000;
    if (length < 1 || length > max || _packDone + length > _packTotal) {
      return CcStatus.tooLarge;
    }
    _openName = name;
    _openLen = length;
    _openExpectedCrc = b.getUint32(10 + n, Endian.little);
    _openAt = 0;
    _openCrc = 0xFFFFFFFF;
    _openData.clear();
    _packCrc = Crc32.update(_packCrc, payload, 4);
    _packState = DeliveryState.transferring;
    return CcStatus.ok;
  }

  static final _iconFileName = RegExp(r'^[a-zA-Z0-9_]+[.]bin$');

  int _write(Uint8List payload) {
    final length = payload.length - 8;
    if (_openName == null || length <= 0 || length > chunk || length > _openLen - _openAt ||
        ByteData.sublistView(payload).getUint32(4, Endian.little) != _openAt) {
      return CcStatus.sequence;
    }
    final body = Uint8List.sublistView(payload, 8);
    _openData.add(body);
    _openCrc = Crc32.update(_openCrc, body);
    _packCrc = Crc32.update(_packCrc, body);
    _openAt += body.length;
    _packDone += body.length;
    return CcStatus.ok;
  }

  int _endFile(Uint8List payload) {
    final name = _openName;
    if (payload.length != 4 || name == null || _openAt != _openLen) return CcStatus.sequence;
    if (Crc32.finalize(_openCrc) != _openExpectedCrc) return CcStatus.crc;
    final data = _openData.takeBytes();
    if (!_resourceOk(name, data)) return CcStatus.bad;
    delivered.add('FILE $name bytes=${data.length}');
    _openName = null;
    _packFilesDone++;
    return CcStatus.ok;
  }

  bool _resourceOk(String name, Uint8List data) {
    if (_packKind == DeliveryKind.icon) {
      if (name == 'animations.bin') return data.length == 20 && _hasMagic(data, 'CIA1');
      if (name.endsWith('_anim.bin')) return _hasMagic(data, 'DGF1');
      return data.length >= 12 && data[0] == 0x19;
    }
    if (data.length < 12) return false;
    final b = ByteData.sublistView(data);
    final magic = b.getUint32(0);
    if (magic != 0x00010000 && magic != 0x4f54544f && magic != 0x74727565) return false;
    final count = b.getUint16(4);
    if (count == 0 || count > 256 || 12 + count * 16 > data.length) return false;
    for (var i = 0; i < count; i++) {
      final offset = b.getUint32(20 + i * 16);
      final length = b.getUint32(24 + i * 16);
      if (offset > data.length || length > data.length - offset) return false;
    }
    return true;
  }

  static bool _hasMagic(Uint8List data, String magic) =>
      data.length >= magic.length && String.fromCharCodes(data, 0, magic.length) == magic;

  int _commitPack(Uint8List payload) {
    if (payload.length != 4 || _openName != null || _packFilesDone != _packFiles || _packDone != _packTotal) {
      return CcStatus.sequence;
    }
    if (Crc32.finalize(_packCrc) != _packExpectedCrc) return CcStatus.crc;
    _packState = DeliveryState.done;
    delivered.add('COMMIT files=$_packFiles total=$_packTotal');
    return CcStatus.ok;
  }

  Uint8List _nshStatus(int state) {
    final out = Uint8List(9);
    ByteData.view(out.buffer).setUint32(0, _lease ?? 0, Endian.little);
    out[4] = state;
    return out;
  }

  (int, Uint8List) _list(Uint8List payload) {
    final dir = _pathOf(payload);
    final n = _pathLen(payload) + 2;
    final b = ByteData.sublistView(payload);
    final off = b.getUint32(n, Endian.little);
    final limit = payload[n + 4];
    if (!dirs.contains(dir)) return (CcStatus.notFound, Uint8List(0));
    final prefix = dir.endsWith('/') ? dir : '$dir/';
    final names = <String>[
      for (final d in dirs)
        if (d != dir && d.startsWith(prefix) && !d.substring(prefix.length).contains('/'))
          d.substring(prefix.length),
      for (final k in files.keys)
        if (k.startsWith(prefix) && !k.substring(prefix.length).contains('/'))
          k.substring(prefix.length),
    ]..sort();
    final page = names.skip(off).take(limit).toList();
    final body = BytesBuilder();
    final head = Uint8List(6);
    final hb = ByteData.view(head.buffer);
    hb.setUint16(0, names.length, Endian.little);
    hb.setUint16(2, off, Endian.little);
    hb.setUint16(4, page.length, Endian.little);
    body.add(head);
    for (final name in page) {
      final full = '$prefix$name';
      final isDir = dirs.contains(full);
      final size = isDir ? 0 : files[full]!.length;
      final nb = Uint8List.fromList(name.codeUnits);
      final rec = Uint8List(1 + nb.length + 9);
      rec[0] = nb.length;
      rec.setRange(1, 1 + nb.length, nb);
      rec[1 + nb.length] = isDir ? 1 : 0;
      final rb = ByteData.view(rec.buffer);
      rb.setUint32(2 + nb.length, size, Endian.little);
      rb.setUint32(6 + nb.length, 1700000000, Endian.little);
      body.add(rec);
    }
    return (CcStatus.ok, body.takeBytes());
  }

  (int, Uint8List) _stat(Uint8List payload) {
    final path = _pathOf(payload);
    final isDir = dirs.contains(path);
    final data = files[path];
    if (!isDir && data == null) return (CcStatus.notFound, Uint8List(0));
    final out = Uint8List(9);
    out[0] = isDir ? 1 : 0;
    final b = ByteData.view(out.buffer);
    b.setUint32(1, data?.length ?? 0, Endian.little);
    b.setUint32(5, 1700000000, Endian.little);
    return (CcStatus.ok, out);
  }

  static int _pathLen(Uint8List payload) =>
      ByteData.sublistView(payload).getUint16(0, Endian.little);

  static String _pathOf(Uint8List payload) {
    final n = _pathLen(payload);
    return String.fromCharCodes(payload, 2, 2 + n);
  }

  Future<void> dispose() async {
    await _sub.cancel();
    await _queue;
  }
}
