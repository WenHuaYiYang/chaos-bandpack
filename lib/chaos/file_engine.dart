import 'dart:async';
import 'dart:typed_data';

import '../protocol/cc_client.dart';
import '../protocol/ccn1.dart';
import '../protocol/ops.dart';
import '../protocol/crc32.dart';

/// 设备侧 `ccf_parse_path` 要的是 **u16 长度 + 原始字节**, 不是 C 字符串。
/// 路径最长 254(再长设备直接判 BAD), 且不能含 NUL。
Uint8List encodePath(String path) {
  final bytes = Uint8List.fromList(path.codeUnits.map((c) => c & 0xFF).toList());
  if (bytes.isEmpty || bytes.length >= 255) {
    throw ArgumentError('路径长度必须在 1..254 之间: $path');
  }
  if (bytes.contains(0)) throw ArgumentError('路径里不能有 NUL: $path');
  final out = Uint8List(2 + bytes.length);
  ByteData.view(out.buffer).setUint16(0, bytes.length, Endian.little);
  out.setRange(2, out.length, bytes);
  return out;
}

/// 一条目录项。
class CcEntry {
  CcEntry(this.name, this.isDir, this.size, this.mtime);
  final String name;
  final bool isDir;
  final int size;
  final int mtime;

  @override
  String toString() => 'CcEntry($name, dir: $isDir, size: $size, mtime: $mtime)';
}

/// 一页目录。设备按 offset/limit 分页, [total] 是整目录项数。
class CcListing {
  CcListing(this.total, this.offset, this.entries);
  final int total;
  final int offset;
  final List<CcEntry> entries;
}

/// STAT 的结果。
class CcStat {
  CcStat(this.isDir, this.size, this.mtime);
  final bool isDir;
  final int size;
  final int mtime;
}

/// HELLO 协商出来的会话能力。
class CcHello {
  CcHello({
    required this.version,
    required this.chunk,
    required this.caps,
    required this.devMode,
    required this.maxPath,
    required this.window,
  });

  final int version;
  final int chunk;
  final int caps;
  final bool devMode;
  final int maxPath;
  final int window;

  /// 能力位 0x20: 能收资源投递包(0x60..0x66)
  bool get hasDelivery => (caps & CcCap.delivery) != 0;

  /// 能力位 0x10 在 HELLO 里是"这一端是 Android 载波"(设备按物理载波置位)
  bool get androidCarrier => (caps & 0x10) != 0;
  bool get hasRmdir => (caps & CcCap.rmdir) != 0;
  bool get hasNsH => (caps & 0x10) != 0;

  @override
  String toString() =>
      'CcHello(v$version, chunk: $chunk, caps: 0x${caps.toRadixString(16)}, window: $window)';
}

/// 一次传输的进度回调(已处理字节, 总字节)。
typedef UploadProgress = void Function(int done, int total);

/// GET_ACCESS 的快照。
class CcAccess {
  CcAccess({
    required this.android,
    required this.policy,
    required this.authState,
    required this.mask,
    required this.token,
    required this.granted,
  });

  final bool android;
  final int policy;
  final int authState;
  final int mask;
  final int token;
  final bool granted;

  bool allows(int bit) => (mask & bit) == bit;

  String get authName => switch (authState) {
        0 => '无待确认',
        1 => '等待手环确认',
        2 => '已允许',
        3 => '已拒绝',
        4 => '确认超时',
        _ => '未知($authState)',
      };

  @override
  String toString() =>
      'CcAccess(android: $android, mask: 0x${mask.toRadixString(16)}, granted: $granted, $authName)';
}

/// PING 的快照。
class CcPing {
  CcPing({
    required this.connected,
    required this.devMode,
    required this.policy,
    required this.authState,
    required this.token,
  });

  final bool connected;
  final bool devMode;
  final int policy;
  final int authState;
  final int token;
}

/// ChaosConnect 的文件引擎: 把 CCN1 的操作码包成可 await 的方法。
///
/// 所有路径都是设备侧的绝对路径(如 `/data/chaos/icons/`), 由设备自己做归一化
/// 与权限检查; 这里只负责拼载荷。**不要**在客户端做路径合法性判断,
/// 设备侧 `ccf_normalize` + `ccf_write_allowed` 才是唯一权威。
class FileEngine {
  FileEngine(this.client);

  final CcClient client;

  /// 单次 READ/WRITE 的字节数: 设备按 `g_chunk` 再夹一次, 这里跟 HELLO 对齐。
  int chunk = Ccn1.chunk;

  CcHello? hello;

  /// 建会话。Android 载波带 'CCA1'(设备据此判别身份), 插件侧可以传空。
  Future<CcHello> handshake({bool android = true}) async {
    final p = await client.call(CcOp.hello, android ? const [0x43, 0x43, 0x41, 0x31] : const []);
    if (p.length < 11) {
      throw CcException(CcOp.hello, CcStatus.bad, 'HELLO 应答只有 ${p.length} 字节');
    }
    final bd = ByteData.sublistView(p);
    final h = CcHello(
      version: p[0],
      chunk: bd.getUint16(1, Endian.little),
      caps: p[3],
      devMode: p[4] != 0,
      maxPath: bd.getUint16(5, Endian.little),
      window: bd.getUint32(7, Endian.little),
    );
    hello = h;
    if (h.chunk > 0 && h.chunk <= Ccn1.chunk) chunk = h.chunk;
    return h;
  }

  /// 0x42: 客户端权限快照。握手前也能问。
  Future<CcAccess> access() async {
    final p = await client.call(CcOp.getAccess);
    if (p.length < 13) {
      throw CcException(CcOp.getAccess, CcStatus.bad, 'GET_ACCESS 应答只有 ${p.length} 字节');
    }
    final bd = ByteData.sublistView(p);
    return CcAccess(
      android: p[1] != 0,
      policy: p[2],
      authState: p[3],
      mask: bd.getUint32(4, Endian.little),
      token: bd.getUint32(8, Endian.little),
      granted: p[12] != 0,
    );
  }

  /// 0x30: 心跳。设备用它判断对面还活着, 也顺手带回开发者模式状态。
  Future<CcPing> ping({Duration timeout = CcClient.defaultTimeout}) async {
    final p = await client.call(CcOp.ping, const [], timeout);
    if (p.length < 8) throw CcException(CcOp.ping, CcStatus.bad, 'PING 应答只有 ${p.length} 字节');
    return CcPing(
      connected: p[0] != 0,
      devMode: p[1] != 0,
      policy: p[2],
      authState: p[3],
      token: ByteData.sublistView(p).getUint32(4, Endian.little),
    );
  }

  /// 0x31: 让设备把这段字节原样回显, 用来量真实链路速度。
  Future<Uint8List> echo(List<int> data) => client.call(CcOp.echo, data);

  Future<bool> getDevMode() async => (await client.call(CcOp.getDev))[0] != 0;

  /// 打开开发者模式可能返回 PENDING: 设备给一个授权 token, 等用户在表上点同意。
  Future<int?> setDevMode(bool on) async {
    final f = await client.request(CcOp.setDev, [on ? 1 : 0]);
    if (f.status == CcStatus.ok) return null;
    if (f.status == CcStatus.pending && f.payload.length >= 4) {
      return ByteData.sublistView(f.payload).getUint32(0, Endian.little);
    }
    throw CcException(CcOp.setDev, f.status);
  }

  Future<CcListing> list(String path, {int offset = 0, int limit = 16}) async {
    final ep = encodePath(path);
    final req = Uint8List(ep.length + 5);
    req.setRange(0, ep.length, ep);
    final bd = ByteData.view(req.buffer);
    bd.setUint32(ep.length, offset, Endian.little);
    req[ep.length + 4] = limit <= 0 ? 16 : (limit > 16 ? 16 : limit);
    final p = await client.call(CcOp.list, req);
    if (p.length < 6) throw CcException(CcOp.list, CcStatus.bad, 'LIST 应答只有 ${p.length} 字节');
    final b = ByteData.sublistView(p);
    final total = b.getUint16(0, Endian.little);
    final off = b.getUint16(2, Endian.little);
    final count = b.getUint16(4, Endian.little);
    final entries = <CcEntry>[];
    var i = 6;
    for (var k = 0; k < count; k++) {
      if (i >= p.length) break;
      final nl = p[i++];
      if (i + nl + 9 > p.length) break;
      final name = String.fromCharCodes(p, i, i + nl);
      i += nl;
      final isDir = p[i] != 0;
      i += 1;
      final size = b.getUint32(i, Endian.little);
      i += 4;
      final mtime = b.getUint32(i, Endian.little);
      i += 4;
      entries.add(CcEntry(name, isDir, size, mtime));
    }
    return CcListing(total, off, entries);
  }

  /// 列整个目录(自动翻页)。
  Future<List<CcEntry>> listAll(String path, {int limit = 16}) async {
    final out = <CcEntry>[];
    var offset = 0;
    while (true) {
      final page = await list(path, offset: offset, limit: limit);
      out.addAll(page.entries);
      offset += page.entries.length;
      if (page.entries.isEmpty || offset >= page.total) break;
    }
    return out;
  }

  Future<CcStat> stat(String path) async {
    final p = await client.call(CcOp.stat, encodePath(path));
    if (p.length < 9) throw CcException(CcOp.stat, CcStatus.bad, 'STAT 应答只有 ${p.length} 字节');
    final b = ByteData.sublistView(p);
    return CcStat(p[0] != 0, b.getUint32(1, Endian.little), b.getUint32(5, Endian.little));
  }

  Future<bool> exists(String path) async {
    try {
      await stat(path);
      return true;
    } on CcException catch (e) {
      if (e.status == CcStatus.notFound) return false;
      rethrow;
    }
  }

  Future<void> mkdir(String path) => client.call(CcOp.mkdir, encodePath(path));

  Future<void> remove(String path) => client.call(CcOp.remove, encodePath(path));

  Future<void> rmdir(String path) => client.call(CcOp.rmdir, encodePath(path));

  Future<void> rename(String from, String to) {
    final a = encodePath(from);
    final b = encodePath(to);
    final req = Uint8List(a.length + b.length);
    req.setRange(0, a.length, a);
    req.setRange(a.length, req.length, b);
    return client.call(CcOp.rename, req);
  }

  Future<void> copy(String from, String to, {bool overwrite = false}) {
    final a = encodePath(from);
    final b = encodePath(to);
    final req = Uint8List(a.length + b.length + 1);
    req.setRange(0, a.length, a);
    req.setRange(a.length, a.length + b.length, b);
    req[req.length - 1] = overwrite ? 1 : 0;
    return client.call(CcOp.copy, req);
  }

  /// 读整个文件: OPEN_READ → 若干 READ → CLOSE_READ。
  Future<Uint8List> readFile(String path, {UploadProgress? onProgress}) async {
    final p = await client.call(CcOp.openRead, encodePath(path));
    if (p.length < 4) {
      throw CcException(CcOp.openRead, CcStatus.bad, 'OPEN_READ 应答只有 ${p.length} 字节');
    }
    final size = ByteData.sublistView(p).getUint32(0, Endian.little);
    final out = Uint8List(size);
    final bd = ByteData(6);
    try {
      var off = 0;
      while (off < size) {
        final want = size - off < chunk ? size - off : chunk;
        bd.setUint32(0, off, Endian.little);
        bd.setUint16(4, want, Endian.little);
        final part = await client.call(CcOp.read, bd.buffer.asUint8List());
        if (part.isEmpty) break; // 设备认为到头了
        final n = part.length > size - off ? size - off : part.length;
        out.setRange(off, off + n, part);
        off += n;
        onProgress?.call(off, size);
      }
      if (off != size) {
        throw CcException(CcOp.read, CcStatus.io, '只读到 $off / $size 字节');
      }
      return out;
    } finally {
      // CLOSE_READ 失败不该盖住真正的错误, 但也不能让设备把读句柄挂着
      try {
        await client.call(CcOp.closeRead);
      } catch (_) {}
    }
  }

  /// 写整个文件: OPEN_WRITE(先声明长度) → 顺序 WRITE → COMMIT(整体 CRC32)。
  /// 设备按 `offset == 已写字节` 严格校验顺序, 所以这里必须串行发。
  Future<void> writeFile(
    String path,
    Uint8List data, {
    bool overwrite = true,
    UploadProgress? onProgress,
  }) async {
    final ep = encodePath(path);
    final head = Uint8List(ep.length + 5);
    head.setRange(0, ep.length, ep);
    ByteData.view(head.buffer).setUint32(ep.length, data.length, Endian.little);
    head[ep.length + 4] = overwrite ? 1 : 0;
    await client.call(CcOp.openWrite, head);

    var crc = 0xFFFFFFFF;
    var off = 0;
    final bd = ByteData(4);
    try {
      while (off < data.length) {
        final n = data.length - off < chunk ? data.length - off : chunk;
        bd.setUint32(0, off, Endian.little);
        final frame = Uint8List(4 + n);
        frame.setRange(0, 4, bd.buffer.asUint8List());
        frame.setRange(4, frame.length, data, off);
        await client.call(CcOp.write, frame);
        crc = Crc32.update(crc, data, off, off + n);
        off += n;
        onProgress?.call(off, data.length);
      }
      bd.setUint32(0, Crc32.finalize(crc), Endian.little);
      await client.call(CcOp.commit, bd.buffer.asUint8List());
    } catch (_) {
      // 半截文件不能留在设备上: ABORT 会删掉临时文件
      try {
        await client.call(CcOp.abort);
      } catch (_) {}
      rethrow;
    }
  }
}
