import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../protocol/cc_client.dart';
import '../protocol/ccn1.dart';
import '../protocol/crc32.dart';
import '../protocol/ops.dart';

/// 投递包的状态, 数值与设备侧 `pack_state` 一致。
abstract final class DeliveryState {
  static const int idle = 0;
  static const int awaitingConsent = 1; // 用户还没在表上点同意
  static const int allowed = 2;
  static const int denied = 3;
  static const int consentTimeout = 4;
  static const int transferring = 5;
  static const int done = 6;
  static const int failed = 7;

  static String name(int s) => switch (s) {
        idle => '空闲',
        awaitingConsent => '等待手环确认',
        allowed => '已允许',
        denied => '已拒绝',
        consentTimeout => '确认超时',
        transferring => '传输中',
        done => '已完成',
        failed => '失败',
        _ => '未知($s)',
      };

  static bool terminal(int s) => s == done || s == failed || s == denied || s == consentTimeout;
}

/// 投递包的种类: 设备只认这两种, 并且落在固定目录里。
abstract final class DeliveryKind {
  static const int font = 1;
  static const int icon = 2;
}

/// 设备对 BEGIN 的应答: token + 状态 + 已收字节 + 总字节。
class DeliveryTicket {
  DeliveryTicket(this.token, this.state, this.done, this.total);
  final int token;
  final int state;
  final int done;
  final int total;

  @override
  String toString() =>
      'DeliveryTicket(token: 0x${token.toRadixString(16)}, ${DeliveryState.name(state)}, $done/$total)';
}

/// 投递包客户端(0x60..0x66)。
///
/// 这条通道**只给 Android 载波用**: 设备侧还要求能力位 0x20 与独立的
/// `connect-install.cfg` 策略。它不写任意路径 —— 字体包落到 `/data/chaos/font`
/// 的第 1..8 号槽, 图标包落到 `/data/chaos/icons` 的空槽, 由设备自己挑。
class DeliveryClient {
  DeliveryClient(this.client);

  final CcClient client;

  static const _deviceConsentWindow = Duration(seconds: 60);
  // 一个 CCN1 会话只有一份设备侧投递状态，不能被另一个客户端抢占。
  static final _busy = Expando<bool>();

  /// 单次 WRITE 的数据上限, 由 HELLO 的 chunk 决定(默认 2048)。
  int chunk = 2048;

  int? _token;

  /// 当前的投递 token；COMMIT 结果不明时保留，供手动 STATUS 核实。
  int? get token => _token;

  /// 0x60 开始。[totalBytes] 是文件长度之和，[totalCrc] 覆盖 BEGIN 的 CRC
  /// 字段之前的字节，以及每个文件的 OPEN_FILE 描述符(不含 token)和内容。
  /// [name] 是 1..12 字节的 UTF-8 短名，图标包仅允许不含空格的可见 ASCII。
  Future<DeliveryTicket> begin({
    required int kind,
    required String name,
    required int fileCount,
    required int totalBytes,
    required int totalCrc,
  }) async {
    _requireIdle(CcOp.deliveryBegin);
    final req = _beginPayload(kind, name, fileCount, totalBytes);
    ByteData.sublistView(req).setUint32(req.length - 4, totalCrc, Endian.little);
    _busy[client] = true;
    try {
      return await _begin(req);
    } finally {
      _busy[client] = null;
    }
  }

  /// 0x61 查询进度(也用于轮询用户确认)。
  Future<DeliveryTicket> status() async =>
      _withToken(CcOp.deliveryStatus, _requireToken());

  /// 0x62 开一个文件。文件名和资源格式由固件校验。
  Future<DeliveryTicket> openFile({
    required String fileName,
    required int length,
    required int crc,
  }) async {
    _requireIdle(CcOp.deliveryOpenFile);
    return _withToken(
      CcOp.deliveryOpenFile,
      _requireToken(),
      _fileDescriptor(fileName, length, crc),
    );
  }

  /// 0x63 写一块。[offset] 必须等于该文件已写字节数(设备严格按序)。
  Future<DeliveryTicket> writeChunk(int offset, Uint8List data) async {
    _requireIdle(CcOp.deliveryWrite);
    if (data.length > chunk) {
      throw ArgumentError('单块 ${data.length} 超过上限 $chunk');
    }
    return _writeChunk(_requireToken(), offset, data);
  }

  /// 0x64 结束当前文件。设备校验长度、CRC 及资源头。
  Future<DeliveryTicket> endFile() async {
    _requireIdle(CcOp.deliveryEndFile);
    return _withToken(CcOp.deliveryEndFile, _requireToken());
  }

  /// 0x65 发布。设备以 index.txt 为唯一发布点。
  Future<DeliveryTicket> commit() async {
    _requireIdle(CcOp.deliveryCommit);
    final t = await _withToken(CcOp.deliveryCommit, _requireToken());
    if (_token == t.token) _token = null;
    return t;
  }

  /// 0x66 放弃手动投递，删除暂存目录。
  Future<DeliveryTicket> abort() async {
    _requireIdle(CcOp.deliveryAbort);
    final token = _requireToken();
    final t = await _withToken(CcOp.deliveryAbort, token);
    if (_token == token) _token = null;
    return t;
  }

  /// 整包投递资源。调用结束前不要修改 [files] 中的字节。
  /// [onState] 收到首个票据和之后每次状态变化，[onProgress] 收到已确认写入的字节数。
  /// [consentTimeout] 可以缩短本地等待，但不能延长设备的 60 秒确认窗口。
  Future<DeliveryTicket> upload({
    required int kind,
    required String name,
    required Map<String, Uint8List> files,
    void Function(int done, int total)? onProgress,
    void Function(DeliveryTicket)? onState,
    Duration pollInterval = const Duration(milliseconds: 300),
    Duration consentTimeout = _deviceConsentWindow,
  }) async {
    _requireIdle(CcOp.deliveryBegin);
    if (files.isEmpty) throw ArgumentError('投递包不能是空的');
    if (pollInterval.isNegative) throw ArgumentError.value(pollInterval, 'pollInterval');
    if (consentTimeout <= Duration.zero || consentTimeout > _deviceConsentWindow) {
      throw ArgumentError.value(consentTimeout, 'consentTimeout', '必须在 (0, 60s] 内');
    }
    final chunkSize = chunk;
    if (chunkSize <= 0) throw StateError('投递的单块上限必须为正数');

    final order = files.keys.toList()..sort();
    final entries = <({Uint8List data, Uint8List descriptor})>[];
    var total = 0;
    for (final key in order) {
      final data = files[key]!;
      total += data.length;
      entries.add((
        data: data,
        descriptor: _fileDescriptor(key, data.length, Crc32.of(data)),
      ));
    }
    final beginReq = _beginPayload(kind, name, entries.length, total);
    // ccp_dispatch：BEGIN 头 + 每个描述符与其原始内容，不含 token 或 offset。
    final crcOffset = beginReq.length - 4;
    var crc = Crc32.update(0xFFFFFFFF, beginReq, 0, crcOffset);
    for (final entry in entries) {
      crc = Crc32.update(crc, entry.descriptor);
      crc = Crc32.update(crc, entry.data);
    }
    ByteData.sublistView(beginReq).setUint32(crcOffset, Crc32.finalize(crc), Endian.little);

    _busy[client] = true;
    int? ownedToken;
    var commitAttempted = false;
    int? lastState;
    void notify(DeliveryTicket t) {
      if (lastState == t.state) return;
      lastState = t.state;
      onState?.call(t);
    }

    try {
      // 从发起 BEGIN 起计，包含设备开始提示后应答在链路上的耗时。
      final clock = Stopwatch()..start();
      var t = await _begin(beginReq);
      final token = t.token;
      ownedToken = token;
      notify(t);
      var op = CcOp.deliveryBegin;
      if (t.state == DeliveryState.awaitingConsent) {
        op = CcOp.deliveryStatus;
        t = await _pollStatus(
          token,
          clock,
          consentTimeout,
          pollInterval,
          (t) => t.state != DeliveryState.awaitingConsent,
          '等待手环确认超时',
        );
        notify(t);
      }
      if (t.state == DeliveryState.consentTimeout) {
        throw TimeoutException('手环确认超时', consentTimeout);
      }
      _requireState(op, t, DeliveryState.allowed);

      void checkTransfer(int op, DeliveryTicket t) {
        notify(t);
        _requireState(op, t, DeliveryState.transferring);
      }

      var done = 0;
      for (final entry in entries) {
        checkTransfer(
          CcOp.deliveryOpenFile,
          await _withToken(CcOp.deliveryOpenFile, token, entry.descriptor),
        );
        final data = entry.data;
        for (var offset = 0; offset < data.length;) {
          final remaining = data.length - offset;
          final n = remaining < chunkSize ? remaining : chunkSize;
          checkTransfer(
            CcOp.deliveryWrite,
            await _writeChunk(token, offset, Uint8List.sublistView(data, offset, offset + n)),
          );
          offset += n;
          done += n;
          onProgress?.call(done, total);
        }
        checkTransfer(CcOp.deliveryEndFile, await _withToken(CcOp.deliveryEndFile, token));
      }

      // 即使没有收到应答，设备也可能已经发布，绝不自动重试或 ABORT。
      commitAttempted = true;
      t = await _withToken(CcOp.deliveryCommit, token);
      if (t.state == DeliveryState.done) _token = null;
      notify(t);
      _requireState(CcOp.deliveryCommit, t, DeliveryState.done);
      return t;
    } catch (_) {
      final token = ownedToken;
      if (token != null && !commitAttempted) {
        try {
          await _withToken(CcOp.deliveryAbort, token).timeout(const Duration(seconds: 2));
        } catch (_) {
          // 保留原始失败。ABORT 只能清理本次 BEGIN 取得的 token。
        } finally {
          if (_token == token) _token = null;
        }
      }
      rethrow;
    } finally {
      _busy[client] = null;
    }
  }

  /// 轮询到终态(或超时)。
  Future<DeliveryTicket> waitForSettled({
    Duration timeout = const Duration(seconds: 90),
    Duration interval = const Duration(milliseconds: 500),
  }) async => _pollStatus(
    _requireToken(),
    Stopwatch()..start(),
    timeout,
    interval,
    (t) => DeliveryState.terminal(t.state),
    '投递包一直没进入终态',
  );

  Future<DeliveryTicket> _pollStatus(
    int token,
    Stopwatch clock,
    Duration timeout,
    Duration interval,
    bool Function(DeliveryTicket) until,
    String timeoutMessage,
  ) async {
    Duration remaining() {
      final left = timeout - clock.elapsed;
      if (left <= Duration.zero) throw TimeoutException(timeoutMessage, timeout);
      return left;
    }

    while (true) {
      final budget = remaining();
      final t = await _withToken(CcOp.deliveryStatus, token).timeout(
        budget,
        onTimeout: () => throw TimeoutException(timeoutMessage, timeout),
      );
      final left = remaining();
      if (until(t)) return t;
      await Future<void>.delayed(interval < left ? interval : left);
    }
  }

  void _requireIdle(int op) {
    if (_busy[client] == true) throw CcException(op, CcStatus.busy, '本连接正在投递');
  }

  int _requireToken() {
    final t = _token;
    if (t == null) throw StateError('还没有 BEGIN 过, 没有投递 token');
    return t;
  }

  static void _requireState(int op, DeliveryTicket ticket, int expected) {
    if (ticket.state == expected) return;
    final state = DeliveryState.name(ticket.state);
    if (ticket.state == DeliveryState.denied) {
      throw CcException(op, CcStatus.access, '手环拒绝了投递');
    }
    if (ticket.state == DeliveryState.failed) {
      throw CcException(op, CcStatus.io, '手环报告投递失败');
    }
    final phase = op == CcOp.deliveryCommit ? '未能确认投递发布结果' : '投递状态不符';
    throw CcException(op, CcStatus.bad, '$phase：$state，预期 ${DeliveryState.name(expected)}');
  }

  static Uint8List _beginPayload(int kind, String name, int count, int total) {
    final bytes = utf8.encode(name);
    if (bytes.isEmpty || bytes.length > 12) {
      throw ArgumentError('投递名长度必须在 1..12 个 UTF-8 字节: $name');
    }
    final req = Uint8List(12 + bytes.length);
    req[0] = kind;
    req[1] = bytes.length;
    final n = 2 + bytes.length;
    req.setRange(2, n, bytes);
    ByteData.sublistView(req)
      ..setUint16(n, count, Endian.little)
      ..setUint32(n + 2, total, Endian.little);
    return req;
  }

  static Uint8List _fileDescriptor(String name, int length, int crc) {
    final bytes = utf8.encode(name);
    if (bytes.isEmpty || bytes.length > 64) {
      throw ArgumentError('文件名长度必须在 1..64 个 UTF-8 字节: $name');
    }
    final descriptor = Uint8List(10 + bytes.length);
    final n = 2 + bytes.length;
    descriptor.setRange(2, n, bytes);
    ByteData.sublistView(descriptor)
      ..setUint16(0, bytes.length, Endian.little)
      ..setUint32(n, length, Endian.little)
      ..setUint32(n + 4, crc, Endian.little);
    return descriptor;
  }

  Future<DeliveryTicket> _begin(Uint8List req) async {
    final t = await _requestTicket(CcOp.deliveryBegin, req);
    if (t.token == 0) throw CcException(CcOp.deliveryBegin, CcStatus.bad, '应答缺少投递 token');
    _token = t.token;
    return t;
  }

  Future<DeliveryTicket> _writeChunk(int token, int offset, Uint8List data) {
    final req = Uint8List(8 + data.length);
    ByteData.sublistView(req)
      ..setUint32(0, token, Endian.little)
      ..setUint32(4, offset, Endian.little);
    req.setRange(8, req.length, data);
    return _requestTicket(CcOp.deliveryWrite, req, token);
  }

  Future<DeliveryTicket> _withToken(int op, int token, [List<int> rest = const []]) {
    final req = Uint8List(4 + rest.length);
    ByteData.sublistView(req).setUint32(0, token, Endian.little);
    req.setRange(4, req.length, rest);
    // 固件 ABORT 会先清除 token 再回 idle 票据。
    return _requestTicket(op, req, op == CcOp.deliveryAbort ? 0 : token);
  }

  Future<DeliveryTicket> _requestTicket(int op, Uint8List req, [int? replyToken]) async {
    const uncertain = '未能确认投递发布结果，请先核实手环上的资源';
    final CcFrame f;
    try {
      f = await client.request(op, req);
    } catch (error) {
      if (op != CcOp.deliveryCommit) rethrow;
      throw CcException(op, CcStatus.bad, '$uncertain：$error');
    }
    if (f.status != CcStatus.ok) throw CcException(op, f.status);
    try {
      final t = _parseTicket(f.payload, op);
      if (replyToken != null && t.token != replyToken) {
        throw CcException(op, CcStatus.bad, '应答的投递 token 不匹配');
      }
      return t;
    } on CcException catch (error) {
      if (op != CcOp.deliveryCommit) rethrow;
      throw CcException(op, error.status, '$uncertain：${error.detail}');
    }
  }

  DeliveryTicket _parseTicket(Uint8List p, int op) {
    if (p.length != 13) throw CcException(op, CcStatus.bad, '投递应答长度应为 13 字节，收到 ${p.length} 字节');
    final b = ByteData.sublistView(p);
    return DeliveryTicket(
      b.getUint32(0, Endian.little),
      p[4],
      b.getUint32(5, Endian.little),
      b.getUint32(9, Endian.little),
    );
  }
}

/// NSH 后端状态, 数值与 `chaos_connect_terminal_state` 一致。
abstract final class NshState {
  static const int idle = 0;
  static const int starting = 1;
  static const int running = 2;
  static const int exited = 3;
  static const int failed = 4;
  static const int stopping = 5;

  static String name(int s) => switch (s) {
        idle => '空闲',
        starting => '启动中',
        running => '运行中',
        exited => '已退出',
        failed => '失败',
        stopping => '停止中',
        _ => '未知($s)',
      };
}

/// NSH 终端会话(0x50..0x53)。
///
/// 设备侧 NuttX 有一个独立 PTY, 一条 lease 只能被一个持有者用; lease 过期后
/// 再写会用 SEQUENCE 拒掉, 不会误伤别人的 shell。
class NshClient {
  NshClient(this.client);

  final CcClient client;

  int? _lease;

  int? get lease => _lease;

  /// 0x50: 开(或续用)会话。应答是 lease:u32 + state:u8 + error:i32。
  Future<NshStatus> open() async {
    final f = await client.request(CcOp.nshOpen);
    if (f.status != CcStatus.ok) throw CcException(CcOp.nshOpen, f.status);
    final s = NshStatus.parse(f.payload, CcOp.nshOpen);
    _lease = s.lease;
    return s;
  }

  /// 0x51: 敲字(命令 + 换行)。设备侧输入容量也是 chunk。
  ///
  /// 必须按 UTF-8 编码: 早先按 codeUnit 截低字节, 中文命令会变成乱码字节。
  Future<void> write(String text) async {
    final bytes = Uint8List.fromList(utf8.encode(text));
    final lease = _requireLease();
    final req = Uint8List(4 + bytes.length);
    ByteData.view(req.buffer).setUint32(0, lease, Endian.little);
    req.setRange(4, req.length, bytes);
    await client.call(CcOp.nshWrite, req);
  }

  /// 0x52: 取输出。应答前 9 字节是状态头, 后面才是原始字节。
  Future<NshRead> read({int capacity = 2048}) async {
    final lease = _requireLease();
    final req = Uint8List(6);
    final b = ByteData.view(req.buffer);
    b.setUint32(0, lease, Endian.little);
    b.setUint16(4, capacity, Endian.little);
    final p = await client.call(CcOp.nshRead, req);
    if (p.length < 9) throw CcException(CcOp.nshRead, CcStatus.bad, 'NSH READ 应答只有 ${p.length} 字节');
    return NshRead(NshStatus.parse(p, CcOp.nshRead), Uint8List.sublistView(p, 9));
  }

  /// 0x52: 只取状态头(容量 1)。设备要求 capacity 非零, 所以不能传 0。
  Future<NshStatus> state() async => (await read(capacity: 1)).status;

  /// 0x53: 关会话。设备会连 PTY 一起回收。
  ///
  /// 先把请求发出去再丢本地 lease: 反过来的话, 请求失败就再也关不掉设备那边,
  /// 下一个 OPEN 会一直等到 PTY 自己退出(表现为"一直繁忙")。
  Future<void> close() async {
    final lease = _lease;
    if (lease == null) return;
    final req = Uint8List(4);
    ByteData.view(req.buffer).setUint32(0, lease, Endian.little);
    try {
      await client.call(CcOp.nshClose, req);
    } finally {
      if (_lease == lease) _lease = null;
    }
  }

  int _requireLease() {
    final l = _lease;
    if (l == null) throw StateError('NSH 会话还没开');
    return l;
  }
}

/// NSH 状态头。
class NshStatus {
  NshStatus(this.lease, this.state, this.error);
  final int lease;
  final int state;
  final int error;

  bool get running => state == NshState.running;
  bool get exited => state == NshState.exited || state == NshState.failed;

  static NshStatus parse(Uint8List p, int op) {
    if (p.length < 9) throw CcException(op, CcStatus.bad, '状态头只有 ${p.length} 字节');
    final b = ByteData.sublistView(p);
    return NshStatus(b.getUint32(0, Endian.little), p[4], b.getInt32(5, Endian.little));
  }

  @override
  String toString() => 'NshStatus(lease: 0x${lease.toRadixString(16)}, ${NshState.name(state)}, err: $error)';
}

/// 一次 NSH 读取的结果。
class NshRead {
  NshRead(this.status, this.output);
  final NshStatus status;
  final Uint8List output;

  /// 输出是原始字节流, 可能是半个 UTF-8 序列; 用允许残缺的解码, 不要抛。
  String get text => utf8.decode(output, allowMalformed: true);
}
