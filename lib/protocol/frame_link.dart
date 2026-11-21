import 'dart:async';
import 'dart:typed_data';

/// SPP 载波上的流帧: **u32LE 长度 + 完整 WearPacket**。
///
/// 这一层只认长度前缀, 不认识 WearPacket 也不认识 CCN1 —— 它要处理的是
/// 蓝牙串口的碎包与粘包: 一次 read 可能只来半个长度头, 也可能一次来三帧。
class FrameLink {
  FrameLink(this._out);

  final void Function(Uint8List bytes) _out;

  final _buf = BytesBuilder(copy: true);
  Uint8List _pending = Uint8List(0);

  /// 喂一段刚从 socket 读到的东西。能切出几帧就回调几次。
  void feed(List<int> chunk) {
    if (chunk.isEmpty) return;
    _buf.add(chunk);
    var data = _buf.takeBytes();
    var off = 0;
    while (data.length - off >= 4) {
      final len = data[off] | (data[off + 1] << 8) | (data[off + 2] << 16) | (data[off + 3] << 24);
      // 上限 64 KiB 只是防呆: 真帧最大 2416 字节, 超了说明流已经错位
      if (len <= 0 || len > 65536) {
        throw StateError('流帧长度异常: $len —— 载波已错位');
      }
      if (data.length - off - 4 < len) break;
      final frame = Uint8List.sublistView(data, off + 4, off + 4 + len);
      off += 4 + len;
      _out(Uint8List.fromList(frame));
    }
    if (off < data.length) {
      _pending = Uint8List.fromList(Uint8List.sublistView(data, off));
    } else {
      _pending = Uint8List(0);
    }
    _buf.add(_pending);
  }

  /// 给一个完整的 WearPacket 加上长度前缀, 可以直接写进 socket。
  static Uint8List pack(List<int> packet) {
    final out = Uint8List(4 + packet.length);
    final n = packet.length;
    out[0] = n & 0xFF;
    out[1] = (n >> 8) & 0xFF;
    out[2] = (n >> 16) & 0xFF;
    out[3] = (n >> 24) & 0xFF;
    out.setRange(4, 4 + n, packet);
    return out;
  }
}

/// 传输载波的抽象: 真机走 SPP/RFCOMM, 测试走内存管道, 两者对上层完全一样。
abstract class CcTransport {
  /// 收到的完整 WearPacket 字节
  Stream<Uint8List> get incoming;

  /// 写一笔(内部自己加长度前缀)
  void send(Uint8List packet);

  Future<void> close();

  /// 载波断开时完成。心跳与重连都靠它判断。
  Future<void> get closed;
}

/// 内存载波: 把两个连接对插, 用于协议层自测。
class LoopbackTransport implements CcTransport {
  LoopbackTransport();

  final _in = StreamController<Uint8List>.broadcast();
  final _closed = Completer<void>();
  LoopbackTransport? _peer;
  bool _isClosed = false;

  static (LoopbackTransport, LoopbackTransport) pair() {
    final a = LoopbackTransport();
    final b = LoopbackTransport();
    a._peer = b;
    b._peer = a;
    return (a, b);
  }

  @override
  Stream<Uint8List> get incoming => _in.stream;

  @override
  void send(Uint8List packet) {
    if (_isClosed) throw StateError('载波已关闭');
    _peer?._in.add(Uint8List.fromList(packet));
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _in.close();
    if (!_closed.isCompleted) _closed.complete();
    final p = _peer;
    if (p != null && !p._isClosed) await p.close();
  }

  @override
  Future<void> get closed => _closed.future;
}
