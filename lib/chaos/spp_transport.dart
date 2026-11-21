import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../protocol/frame_link.dart';

/// 设备侧的 SPP 服务 UUID 与声道(docs/CHAOSCONNECT-ANDROID.md)。
///
/// 手环注册的是**私有 UUID**(不是标准 00001101), 所以手机必须用这个 UUID 建连;
/// 服务通道 19 只在手环侧有意义, 手机不需要指定。
abstract final class ChaosSpp {
  static const String uuid = '43434e31-0001-4a10-8000-4348414f5301';
  static const String channel = 'com.chaos.chaos_bandpack/spp';

  /// 设备侧一次连接最多只接受 1 条; 读块 4 KiB 是 Kotlin 侧的缓冲, 与协议无关。
  static const int maxConnections = 1;
}

/// 扫到的一台设备。已配对与否决定能不能直接连 —— 没配对的要先配对。
class SppPeer {
  const SppPeer({required this.address, required this.name, required this.paired});

  final String address;
  final String name;
  final bool paired;

  @override
  bool operator ==(Object other) => other is SppPeer && other.address == address;

  @override
  int get hashCode => address.hashCode;
}

/// 与 Android 原生层的窄接口。抽出来是为了能在测试里替换成内存实现。
abstract class SppPlatform {
  /// 'on' / 'off' / 'unauthorized' / 'unsupported'
  Future<String> adapterState();

  /// 申请电池之外唯一需要的运行时权限(Android 12+ 的 BLUETOOTH_CONNECT)。
  Future<bool> requestPermissions();

  /// 已配对的设备列表(address 是标准 6 字节地址的可读串)
  Future<List<({String address, String name})>> bondedDevices();

  /// 主动搜一遍附近的设备(经典蓝牙 inquiry / startDiscovery)。
  ///
  /// 与 [bondedDevices] 的区别是它真的会发信号: 结果里可能有没配对的设备,
  /// 也可能因为附近什么都没有而返回空 —— 那不是错误, 只是真的没人应答。
  /// [timeout] 是搜索窗口, 平台侧不保证精确到毫秒。
  Future<List<SppPeer>> discover({Duration timeout});

  /// 配对新设备。成功不代表已经连上, 只代表以后可以直接连。
  Future<bool> pair(String address);

  Future<void> connect(String address, String uuid);

  /// 写一段裸字节(调用方已加好长度前缀)
  Future<void> send(Uint8List bytes);

  Future<void> close();

  /// 原生侧推上来的事件: 'chunk' 带 ByteArray, 'closed' 带原因
  void setHandlers({
    required void Function(Uint8List chunk) onChunk,
    required void Function(String reason) onClosed,
  });
}

/// 走 MethodChannel 的真实现。
class MethodChannelSpp implements SppPlatform {
  MethodChannelSpp([MethodChannel? channel])
      : _ch = channel ?? const MethodChannel(ChaosSpp.channel) {
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'chunk':
          final data = call.arguments;
          if (data is Uint8List) _onChunk?.call(data);
          break;
        case 'closed':
          _onClosed?.call(call.arguments?.toString() ?? '连接中断');
          break;
      }
      return null;
    });
  }

  final MethodChannel _ch;
  void Function(Uint8List chunk)? _onChunk;
  void Function(String reason)? _onClosed;

  @override
  void setHandlers({
    required void Function(Uint8List chunk) onChunk,
    required void Function(String reason) onClosed,
  }) {
    _onChunk = onChunk;
    _onClosed = onClosed;
  }

  /// 平台通道不存在时(Web、或者没带 SPP 实现的构建)invokeMethod 会抛
  /// MissingPluginException。这里把它翻成 'unsupported', 让界面给出人话,
  /// 而不是把平台异常原样贴出来。
  @override
  Future<String> adapterState() async {
    try {
      return (await _ch.invokeMethod<String>('adapter')) ?? 'unsupported';
    } on MissingPluginException {
      return 'unsupported';
    }
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      return (await _ch.invokeMethod<bool>('permissions')) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<List<({String address, String name})>> bondedDevices() async {
    final List<Object?> raw;
    try {
      raw = await _ch.invokeMethod<List<Object?>>('bonded') ?? const <Object?>[];
    } on MissingPluginException {
      return const <({String address, String name})>[];
    }
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((m) => (
              address: m['address']?.toString() ?? '',
              name: m['name']?.toString() ?? '',
            ))
        .where((d) => d.address.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<SppPeer>> discover({Duration timeout = const Duration(seconds: 12)}) async {
    final List<Object?> raw;
    try {
      raw = await _ch.invokeMethod<List<Object?>>(
            'discover',
            <String, Object?>{'timeoutMs': timeout.inMilliseconds},
          ) ??
          const <Object?>[];
    } on MissingPluginException {
      return const <SppPeer>[];
    } on PlatformException catch (e) {
      // 平台侧说"蓝牙关了/没权限"是有用信息, 不能当成"附近没有设备"咽下去。
      throw StateError(e.message ?? e.code);
    }
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((m) => SppPeer(
              address: m['address']?.toString() ?? '',
              name: m['name']?.toString() ?? '',
              paired: m['paired'] == true,
            ))
        .where((p) => p.address.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<bool> pair(String address) async {
    try {
      return await _ch.invokeMethod<bool>('pair', <String, Object?>{'address': address}) ?? false;
    } on MissingPluginException {
      // 这个版本的桌面版没带配对能力, 不是"配对失败"。
      return false;
    } on PlatformException catch (e) {
      // 系统给的失败原因(附近没有、被取消、超时)比一个 false 有用得多,
      // 界面要能照着它告诉用户下一步做什么。
      throw StateError(e.message ?? e.code);
    }
  }

  @override
  Future<void> connect(String address, String uuid) =>
      _ch.invokeMethod<void>('connect', {'address': address, 'uuid': uuid});

  @override
  Future<void> send(Uint8List bytes) =>
      _ch.invokeMethod<void>('send', {'bytes': bytes});

  @override
  Future<void> close() => _ch.invokeMethod<void>('close');
}

/// 真机载波: 把 socket 的裸流拼成“u32LE 长度 + WearPacket”的帧。
class SppTransport implements CcTransport {
  SppTransport(this._platform) {
    _link = FrameLink(_in.add);
    _platform.setHandlers(
      onChunk: (chunk) {
        try {
          _link.feed(chunk);
        } catch (e) {
          _fail(e);
        }
      },
      onClosed: (reason) => _fail(StateError(reason)),
    );
  }

  static Future<void> checkAdapter(SppPlatform platform) async {
    final state = await platform.adapterState();
    if (state != 'on') {
      throw StateError(switch (state) {
        'off' => '蓝牙未开启',
        'unauthorized' => '缺少蓝牙权限',
        _ => '这台设备走不了经典蓝牙',
      });
    }
  }

  Future<void> connect(String address) async {
    await _platform.connect(address, ChaosSpp.uuid);
    // 串口可能刚打开就断了，原因不一定能通过广播流传到稍后创建的协议客户端。
    if (_isClosed) throw _failure ?? StateError('已取消连接');
  }

  final SppPlatform _platform;
  late final FrameLink _link;
  final _in = StreamController<Uint8List>.broadcast();
  final _closed = Completer<void>();
  bool _isClosed = false;
  Object? _failure;
  Future<void>? _closing;

  Object? get failure => _failure;

  @override
  Stream<Uint8List> get incoming => _in.stream;

  @override
  void send(Uint8List packet) {
    if (_isClosed) throw StateError('载波已关闭');
    // 一次只允许一笔在途写: 设备侧的 SPP 队列很小, 并发写只会把帧搅乱。
    unawaited(_platform.send(FrameLink.pack(packet)).catchError((Object e) {
      _fail(e);
    }));
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _isClosed = true;
    try {
      await _platform.close();
    } catch (_) {
      // 原生载波可能已经断了。
    }
    await _in.close();
    if (!_closed.isCompleted) _closed.complete();
  }

  @override
  Future<void> get closed => _closed.future;

  void _fail(Object e) {
    if (_isClosed) return;
    _failure = e;
    _in.addError(e);
    unawaited(close());
  }
}
