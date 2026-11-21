import 'dart:async';
import 'dart:typed_data';

import 'ccn1.dart';
import 'ops.dart';
import 'wear_packet.dart';
import 'frame_link.dart';

/// 上层的失败。设备回了非 OK 状态就抛它, 不要把状态码散到每个调用点。
class CcException implements Exception {
  CcException(this.op, this.status, [this.detail = '']);
  final int op;
  final int status;
  final String detail;

  String get statusName => CcStatus.name(status);

  @override
  String toString() => 'CcException(op: 0x${op.toRadixString(16)}, $statusName)${detail.isEmpty ? '' : ': $detail'}';
}

/// 请求已发出，但在期限内没有收到匹配的应答。
class CcRequestTimeout extends TimeoutException {
  CcRequestTimeout(this.op, this.responsesAtSend, Duration timeout)
      : super('op 0x${op.toRadixString(16)} 等应答超时', timeout);

  final int op;
  final int responsesAtSend;
}

/// ChaosConnect 会话: 请求-应答配对 + 事件广播。
///
/// 固件侧是单线程轮询, 请求号只要**在途唯一**就行; 这里用自增 + 8 路在途
/// (与 CC_WINDOW 一致), 超过窗口就排队等空位, 免得设备侧 RX 队列被打爆。
class CcClient {
  CcClient(this._transport, {this.packetIdSeed = 0x1000, this.onRequestTimeout}) {
    _sub = _transport.incoming.listen(_onPacket, onError: _onError, onDone: _onDone);
  }

  final CcTransport _transport;
  final int packetIdSeed;
  final void Function(CcRequestTimeout)? onRequestTimeout;

  late final StreamSubscription<Uint8List> _sub;
  final _pending = <int, ({int op, Completer<CcFrame> done})>{};
  final _events = StreamController<CcFrame>.broadcast();
  final _closed = Completer<void>();
  final _inFlight = <Completer<void>>[];
  int _nextId = 0;
  int _responsesReceived = 0;
  Object? _error;

  static const int _maxInFlight = Ccn1.window;
  static const Duration defaultTimeout = Duration(seconds: 15);

  /// 设备主动推的事件帧(flags = CC_EVENT)
  Stream<CcFrame> get events => _events.stream;

  /// 会话结束(载波关闭或出错)
  Future<void> get done => _closed.future;

  bool get isClosed => _closed.isCompleted;

  /// 包括 BUSY 等非 OK 应答；能匹配到在途请求就说明会话还在回应。
  int get responsesReceived => _responsesReceived;
  bool get hasWindowSlot => !isClosed && _inFlight.length < _maxInFlight;

  /// 一次分配 packet id 与请求号, 两者是**同一个数**: req 取 id 的低 16 位。
  ///
  /// 固件核对的是 req/prefix —— 拿 CCN1 里的 req 去比 WearPacket 的 packet id,
  /// 对不上就整帧丢掉, 连 HELLO 都不回(手环只对金标准向量应答, 就是这么发现的)。
  /// 所以这两个号不能各自自增, 只能先有 id 再截出 req。
  (int, int) _allocIds() {
    while (true) {
      _nextId = (_nextId + 1) & 0xFFFF;
      final int req = (packetIdSeed + _nextId) & 0xFFFF;
      // 0 留给事件，在途号不能重用。高 16 位固定：固件也用它辨认这次会话。
      if (req == 0 || _pending.containsKey(req)) continue;
      return ((packetIdSeed & 0x7FFF0000) | req, req);
    }
  }

  /// 发一个请求并等应答。[payload] 超过 [Ccn1.maxPayload] 由调用方分块。
  Future<CcFrame> request(int op, [
    List<int> payload = const [],
    Duration timeout = defaultTimeout,
  ]) async {
    if (isClosed) throw CcException(op, CcStatus.bad, _error?.toString() ?? '会话已关闭');
    while (_inFlight.length >= _maxInFlight) {
      await _inFlight.first.future;
      if (isClosed) {
        throw CcException(op, CcStatus.bad, _error?.toString() ?? '会话已关闭');
      }
    }
    final slot = Completer<void>();
    _inFlight.add(slot);
    final (int packetId, int req) = _allocIds();
    final done = Completer<CcFrame>();
    _pending[req] = (op: op, done: done);
    final responsesAtSend = _responsesReceived;
    try {
      final frame = ccEncode(
        flags: Ccn1.flagRequest,
        op: op,
        status: CcStatus.ok,
        req: req,
        payload: payload,
      );
      _transport.send(PbEnvelope.wrap(frame, packetId));
      return await done.future.timeout(timeout, onTimeout: () {
        _pending.remove(req);
        final error = CcRequestTimeout(op, responsesAtSend, timeout);
        onRequestTimeout?.call(error);
        throw error;
      });
    } finally {
      _pending.remove(req);
      _inFlight.remove(slot);
      if (!slot.isCompleted) slot.complete();
    }
  }

  /// 发一个请求, 断言状态是 OK, 返回 payload
  Future<Uint8List> call(int op, [
    List<int> payload = const [],
    Duration timeout = defaultTimeout,
  ]) async {
    final f = await request(op, payload, timeout);
    if (f.status != CcStatus.ok) throw CcException(op, f.status);
    return f.payload;
  }

  /// 不等应答地发一帧(事件/断连通知用)
  void fireAndForget(int op, [List<int> payload = const []]) {
    if (isClosed) return;
    final (int packetId, int req) = _allocIds();
    final frame = ccEncode(flags: Ccn1.flagRequest, op: op, status: CcStatus.ok, req: req, payload: payload);
    _transport.send(PbEnvelope.wrap(frame, packetId));
  }

  Future<void> close() async {
    _finish(null);
    await _sub.cancel();
    await _transport.close();
  }

  void _onPacket(Uint8List packet) {
    final CcFrame frame;
    try {
      frame = ccDecode(PbEnvelope.split(packet).frame);
    } catch (_) {
      return; // 不是我们的包 / 被改坏了: 丢掉, 不打断会话
    }
    if (frame.flags == Ccn1.flagEvent) {
      _events.add(frame);
      return;
    }
    if (frame.flags != Ccn1.flagResponse) return;
    final waiter = _pending[frame.req];
    if (waiter == null || waiter.op != frame.op || waiter.done.isCompleted) return;
    _pending.remove(frame.req);
    _responsesReceived++;
    waiter.done.complete(frame);
  }

  void _onError(Object e) {
    _error = e;
    _finish(e);
  }

  void _onDone() => _finish(null);

  void _finish(Object? e) {
    if (_closed.isCompleted) return;
    for (final waiter in _pending.values) {
      final c = waiter.done;
      if (!c.isCompleted) {
        c.completeError(CcException(0, CcStatus.bad, e?.toString() ?? '载波已断开'));
      }
    }
    _pending.clear();
    for (final s in _inFlight) {
      if (!s.isCompleted) s.complete();
    }
    _inFlight.clear();
    _events.close();
    _closed.complete();
  }
}
