import 'dart:typed_data';

/// WearPacket / ThirdpartyApp.MessageContent 信封。对应固件 `cc_pb_wrap` / `cc_pb_unwrap`。
///
/// 这是**设备侧已存在的**协议形状, 不是我们发明的扩展:
/// ```
/// MessageContent {
///   1: uint32 type        // 必须是 WearPacket.Type.OTHER = 0
///   2: uint64 id          // packet id, 我们拿来复用高 16 位做事件号
///   22: ThirdpartyApp {
///     9: bytes message_content {
///       1: BasicInfo { 1: string package_name = "ChaosConnect", 2: bytes fingerprint = "" }
///       2: bytes payload   // 完整的 CCN1 帧
///     }
///   }
/// }
/// ```
class PbEnvelope {
  static const int fieldType = 1;
  static const int fieldId = 2;
  static const int fieldApp = 22;
  static const int fieldMessage = 9;
  static const int fieldBasicInfo = 1;
  static const int fieldBody = 2;
  static const int fieldPackage = 1;
  static const int fieldFingerprint = 2;

  /// 命名空间标识。设备侧只认这一串, 改它等于换协议。
  static const String packageName = 'ChaosConnect';

  /// 抓出来的一个信封。
  static PbPacket split(Uint8List data) {
    final r = _Reader(data);
    var type = -1;
    var id = 0;
    Uint8List? app;
    while (!r.done) {
      final tag = r.varint();
      final field = tag >> 3;
      final wire = tag & 7;
      if (field == fieldType && wire == 0) {
        type = r.varint();
      } else if (field == fieldId && wire == 0) {
        id = r.varint();
      } else if (field == fieldApp && wire == 2) {
        app = r.bytes();
      } else {
        r.skip(wire, field);
      }
    }
    if (type != 0) throw PbFormatError('type 不是 WearPacket.Type.OTHER: $type');
    if (app == null) throw PbFormatError('没有 ThirdpartyApp 字段');
    final ra = _Reader(app);
    Uint8List? msg;
    while (!ra.done) {
      final tag = ra.varint();
      final field = tag >> 3;
      final wire = tag & 7;
      if (field == fieldMessage && wire == 2) {
        msg = ra.bytes();
      } else {
        ra.skip(wire, field);
      }
    }
    if (msg == null) throw PbFormatError('没有 message_content 字段');
    final rm = _Reader(msg);
    Uint8List? basic;
    Uint8List? body;
    while (!rm.done) {
      final tag = rm.varint();
      final field = tag >> 3;
      final wire = tag & 7;
      if (field == fieldBasicInfo && wire == 2) {
        basic = rm.bytes();
      } else if (field == fieldBody && wire == 2) {
        body = rm.bytes();
      } else {
        rm.skip(wire, field);
      }
    }
    if (basic == null) throw PbFormatError('没有 BasicInfo 字段');
    if (body == null) throw PbFormatError('没有载荷字段');
    final rb = _Reader(basic);
    String? name;
    Uint8List? fp;
    while (!rb.done) {
      final tag = rb.varint();
      final field = tag >> 3;
      final wire = tag & 7;
      if (field == fieldPackage && wire == 2) {
        name = String.fromCharCodes(rb.bytes());
      } else if (field == fieldFingerprint && wire == 2) {
        fp = rb.bytes();
      } else {
        rb.skip(wire, field);
      }
    }
    if (name != packageName) throw PbFormatError('包名不是 $packageName: $name');
    if (fp != null && fp.isNotEmpty) throw PbFormatError('fingerprint 必须为空');
    return PbPacket(id: id, frame: body);
  }

  /// 把一个 CCN1 帧裹成 WearPacket 字节。
  static Uint8List wrap(Uint8List frame, int id) {
    final pn = packageName.codeUnits;
    // 长度前缀必须是 varint: 一个 1500 字节的 READ 应答如果按单字节写长度,
    // 0xDC0 会被截成 0xC0, 对端直接解出"长度越界"。金标准向量都是小帧, 只有
    // 真跑大数据才暴露。
    // BasicInfo: 字段1 包名 + 字段2 空 fingerprint
    final basic = <int>[
      0x0A, ..._varint(pn.length), ...pn,
      0x12, 0x00,
    ];
    // message_content: 字段1 BasicInfo + 字段2 帧
    final msg = <int>[
      0x0A, ..._varint(basic.length), ...basic,
      0x12, ..._varint(frame.length), ...frame,
    ];
    // ThirdpartyApp: 字段9 message_content
    final app = <int>[0x4A, ..._varint(msg.length), ...msg];
    // MessageContent: 字段1 type + 字段2 id + 字段22 app
    final out = <int>[
      0x08, 0x00,
      0x10, ..._varint(id),
      0xB2, 0x01, ..._varint(app.length), ...app,
    ];
    return Uint8List.fromList(out);
  }
}

class PbPacket {
  PbPacket({required this.id, required this.frame});
  final int id;
  final Uint8List frame;
}

class PbFormatError implements Exception {
  PbFormatError(this.message);
  final String message;
  @override
  String toString() => 'PbFormatError: $message';
}

List<int> _varint(int v) {
  final out = <int>[];
  var x = v;
  while (x >= 0x80) {
    out.add((x & 0x7F) | 0x80);
    x >>= 7;
  }
  out.add(x);
  return out;
}

class _Reader {
  _Reader(this.d);
  final Uint8List d;
  int i = 0;
  bool get done => i >= d.length;

  int varint() {
    var shift = 0;
    var out = 0;
    while (true) {
      if (i >= d.length) throw PbFormatError('varint 越界');
      final b = d[i++];
      out |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) return out;
      shift += 7;
      if (shift > 63) throw PbFormatError('varint 溢出');
    }
  }

  Uint8List bytes() {
    final n = varint();
    if (n < 0 || i + n > d.length) throw PbFormatError('长度越界');
    final out = Uint8List.sublistView(d, i, i + n);
    i += n;
    return out;
  }

  void skip(int wire, int field) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        if (i + 8 > d.length) throw PbFormatError('fixed64 越界');
        i += 8;
      case 2:
        bytes();
      case 5:
        if (i + 4 > d.length) throw PbFormatError('fixed32 越界');
        i += 4;
      default:
        throw PbFormatError('不认识的 wire type $wire (字段 $field)');
    }
  }
}
