import 'dart:typed_data';
import 'crc32.dart';

/// ChaosConnect v1 线格式。逐字段对应 `supervisor/bridge/chaos_connect.h`。
///
/// 帧头 16 字节, 小端:
/// ```
/// 0  'C' 'C' 'N' '1'
/// 4  u8  version (=1)
/// 5  u8  flags   (0 请求, 1 应答, 2 事件)
/// 6  u8  op
/// 7  u8  status
/// 8  u16 req     请求号
/// 10 u16 len     payload 长度
/// 12 u32 crc32(头前 12 字节 + payload)
/// 16 .. payload
/// ```
class Ccn1 {
  static const int version = 1;
  static const int headerBytes = 16;
  static const int chunk = 2048;
  static const int maxPayload = chunk + 256;
  static const int maxFrame = headerBytes + maxPayload;
  static const int maxWire = maxFrame + 96;
  static const int window = 8;

  /// WearPacket.Type.OTHER —— 私有身份在 CCN1 里面, 不在这一层
  static const int pbType = 0;

  static const int flagRequest = 0;
  static const int flagResponse = 1;
  static const int flagEvent = 2;

  static const List<int> magic = [0x43, 0x43, 0x4E, 0x31]; // 'CCN1'
}

/// 一个解出来的帧。payload 是 buffer 的视图, 不复制。
class CcFrame {
  CcFrame({
    required this.flags,
    required this.op,
    required this.status,
    required this.req,
    required this.payload,
  });

  final int flags;
  final int op;
  final int status;
  final int req;
  final Uint8List payload;

  int get len => payload.length;

  @override
  String toString() =>
      'CcFrame(flags: $flags, op: 0x${op.toRadixString(16)}, status: $status, req: $req, len: $len)';
}

class CcFormatError implements Exception {
  CcFormatError(this.message);
  final String message;
  @override
  String toString() => 'CcFormatError: $message';
}

/// 编码一帧。返回长度 = 16 + payload.length 的独立数组。
Uint8List ccEncode({
  required int flags,
  required int op,
  required int status,
  required int req,
  List<int> payload = const [],
}) {
  if (payload.length > Ccn1.maxPayload) {
    throw CcFormatError('payload ${payload.length} 超过上限 ${Ccn1.maxPayload}');
  }
  if (flags > Ccn1.flagEvent) throw CcFormatError('flags $flags 非法');
  final out = Uint8List(Ccn1.headerBytes + payload.length);
  out[0] = 0x43;
  out[1] = 0x43;
  out[2] = 0x4E;
  out[3] = 0x31;
  out[4] = Ccn1.version;
  out[5] = flags;
  out[6] = op;
  out[7] = status;
  final bd = ByteData.view(out.buffer);
  bd.setUint16(8, req & 0xFFFF, Endian.little);
  bd.setUint16(10, payload.length, Endian.little);
  // CRC 覆盖 0..12 与 16.., 中间那 4 字节就是它自己
  var crc = Crc32.update(0xFFFFFFFF, out, 0, 12);
  if (payload.isNotEmpty) {
    out.setRange(Ccn1.headerBytes, Ccn1.headerBytes + payload.length, payload);
    crc = Crc32.update(crc, payload);
  }
  bd.setUint32(12, Crc32.finalize(crc), Endian.little);
  return out;
}

/// 解一帧。任何一处不合规都抛 [CcFormatError] —— 固件那边是返回 0 让上层丢弃,
/// 这里的语义一样: 只返回能完整通过校验的帧。
CcFrame ccDecode(Uint8List data, [int start = 0, int? end]) {
  final n = (end ?? data.length) - start;
  if (n < Ccn1.headerBytes) throw CcFormatError('帧太短: $n');
  if (data[start] != 0x43 ||
      data[start + 1] != 0x43 ||
      data[start + 2] != 0x4E ||
      data[start + 3] != 0x31) {
    throw CcFormatError('魔数不是 CCN1');
  }
  if (data[start + 4] != Ccn1.version) {
    throw CcFormatError('版本 ${data[start + 4]} != ${Ccn1.version}');
  }
  final flags = data[start + 5];
  if (flags > Ccn1.flagEvent) throw CcFormatError('flags $flags 非法');
  final bd = ByteData.view(data.buffer, data.offsetInBytes + start);
  final req = bd.getUint16(8, Endian.little);
  final len = bd.getUint16(10, Endian.little);
  if (len > Ccn1.maxPayload) throw CcFormatError('len $len 超过上限');
  if (n != Ccn1.headerBytes + len) throw CcFormatError('长度不符: 头说 $len, 实际 ${n - Ccn1.headerBytes}');
  final want = bd.getUint32(12, Endian.little);
  var crc = Crc32.update(0xFFFFFFFF, data, start, start + 12);
  if (len > 0) crc = Crc32.update(crc, data, start + Ccn1.headerBytes, start + Ccn1.headerBytes + len);
  final got = Crc32.finalize(crc);
  if (got != want) throw CcFormatError('CRC 不符: 算出 ${got.toRadixString(16)}, 帧里 ${want.toRadixString(16)}');
  return CcFrame(
    flags: flags,
    op: data[start + 6],
    status: data[start + 7],
    req: req,
    payload: Uint8List.sublistView(data, start + Ccn1.headerBytes, start + Ccn1.headerBytes + len),
  );
}
