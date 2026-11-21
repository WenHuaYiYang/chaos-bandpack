import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../protocol/cc_client.dart';
import '../protocol/ops.dart';
import 'delivery.dart';
import 'file_engine.dart';
import 'spp_transport.dart';

enum LinkState { idle, scanning, connecting, handshaking, ready, failed }

class _ConnectAttempt {
  bool canceled = false;
  final done = Completer<void>();
}

/// 一台手环(已配对设备)。
@immutable
class BandDevice {
  const BandDevice({required this.address, required this.name});

  final String address;
  final String name;

  @override
  bool operator ==(Object other) => other is BandDevice && other.address == address;

  @override
  int get hashCode => address.hashCode;
}

/// 连接会话: 管一条 SPP 载波、一个 CcClient、以及挂在它上面的文件引擎/投递/NSH。
///
/// 做成 ChangeNotifier 是因为三件事都是异步且会失败的(蓝牙权限、连接、握手),
/// 页面只需要听一个状态, 不必各自维护 FutureBuilder 的四种状态。
class ChaosSession extends ChangeNotifier {
  ChaosSession({SppPlatform? platform}) : _platform = platform ?? MethodChannelSpp();

  final SppPlatform _platform;
  static const _heartbeatInterval = Duration(seconds: 3);
  static const _heartbeatTimeout = Duration(seconds: 4);

  LinkState _state = LinkState.idle;
  String? _error;
  String? _adapter;
  List<BandDevice> _devices = const <BandDevice>[];
  /// 搜到的附近设备(可能含没配对的)。与 [devices] 分开存: 已配对的那些
  /// 断开重进页面还在, 搜出来的只在这一次搜索有效。
  List<SppPeer> _peers = const <SppPeer>[];
  bool _searching = false;
  BandDevice? _connected;
  BandDevice? _lastDevice;
  Timer? _heartbeat;
  SppTransport? _transport;
  CcClient? _client;
  FileEngine? _engine;
  DeliveryClient? _delivery;
  NshClient? _nsh;
  CcHello? _hello;
  CcAccess? _access;
  CcPing? _ping;
  StreamSubscription<void>? _closedSub;
  _ConnectAttempt? _attempt;
  Future<void>? _disconnecting;
  bool _disposed = false;

  /// 终端界面的滚动记录与最近状态。放在会话里, 这样切走再回来还看得见
  /// 上一段输出 —— 终端一离开就清空, 用户会以为命令没执行。
  String nshOutput = '';
  NshStatus? nshStatus;

  LinkState get state => _state;
  String? get error => _error;
  String? get adapter => _adapter;
  List<BandDevice> get devices => _devices;
  List<SppPeer> get peers => _peers;
  bool get searching => _searching;
  BandDevice? get connected => _connected;
  BandDevice? get reconnectDevice => _lastDevice;
  bool get releasing => _disconnecting != null;
  FileEngine? get engine => _engine;
  DeliveryClient? get delivery => _delivery;
  NshClient? get nsh => _nsh;
  CcHello? get hello => _hello;
  CcAccess? get access => _access;
  CcPing? get ping => _ping;
  bool get isReady => _state == LinkState.ready;
  bool get isConnecting => _state == LinkState.connecting || _state == LinkState.handshaking;
  bool get canceling => _attempt?.canceled ?? false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _set(LinkState s, {String? error}) {
    _state = s;
    _error = error;
    _notify();
  }

  /// 读适配器状态并列出已配对设备。没有权限时会先申请。
  Future<void> scan() async {
    if (_disposed || releasing || isConnecting || isReady || _state == LinkState.scanning) return;
    _set(LinkState.scanning);
    try {
      String state = await _platform.adapterState();
      if (state == 'unauthorized') {
        final bool ok = await _platform.requestPermissions();
        if (!ok) {
          _set(LinkState.failed, error: '没有蓝牙权限, 请到系统设置里允许');
          return;
        }
        state = await _platform.adapterState();
      }
      _adapter = state;
      if (state != 'on') {
        _devices = const <BandDevice>[];
        _set(LinkState.failed, error: switch (state) {
          'off' => '蓝牙未开启, 或者这台机器没有蓝牙',
          // 平台通道不存在(Web、或者第三方构建的 runner)。别把责任推给用户说"本机没蓝牙"。
        'unsupported' => '这个版本的同步器没带蓝牙支持',
          _ => '蓝牙不可用($state)',
        });
        return;
      }
      final list = await _platform.bondedDevices();
      _devices = <BandDevice>[
        for (final d in list) BandDevice(address: d.address, name: d.name),
      ];
      _set(LinkState.idle);
    } catch (e) {
      _set(LinkState.failed, error: _readable(e));
    }
  }

  /// 主动搜一遍附近的设备。与 [scan] 不同: 这个真的会发信号, 所以耗时
  /// (默认 12 秒), 而且可能什么都没搜到 —— 那不代表出错。
  ///
  /// 搜完顺手把已配对列表也刷新一遍: 搜到的新设备一旦配上, 两个列表都要更新。
  Future<void> search({Duration timeout = const Duration(seconds: 12)}) async {
    if (_disposed || _searching || releasing || isConnecting || isReady) return;
    _searching = true;
    _notify();
    try {
      final List<SppPeer> found = await _platform.discover(timeout: timeout);
      _peers = found;
      _error = null;
    } catch (e) {
      _peers = const <SppPeer>[];
      _error = _readable(e);
    } finally {
      _searching = false;
      _notify();
    }
    // 搜索期间可能配上了新设备, 已配对列表跟着重读一次。
    try {
      final list = await _platform.bondedDevices();
      _devices = <BandDevice>[
        for (final d in list) BandDevice(address: d.address, name: d.name),
      ];
      _notify();
    } catch (_) {
      // 读不到就保留旧列表, 不值得为它再报一次错。
    }
  }

  /// 配对一台搜到的设备, 成功后并进已配对列表。
  Future<bool> pair(SppPeer peer) async {
    final bool ok = await _platform.pair(peer.address);
    if (ok) {
      await scan();
    }
    return ok;
  }

  /// 串口打开不等于 ChaosConnect 就绪，只有收到 HELLO 回复才进入 ready。
  Future<void> connect(BandDevice device) async {
    if (_attempt != null || _disconnecting != null || _searching ||
        _disposed || _state == LinkState.scanning || isReady) return;
    final attempt = _ConnectAttempt();
    _attempt = attempt;
    _lastDevice = device;
    _set(LinkState.connecting);
    try {
      await SppTransport.checkAdapter(_platform);
      if (attempt.canceled) return;
      // 先保存载波；在 Windows 原生 connect 尚未返回时也可以取消它。
      final t = _transport = SppTransport(_platform);
      await t.connect(device.address);
      if (attempt.canceled) return;

      final client = _client = CcClient(t, onRequestTimeout: (timeout) {
        final client = _client;
        if (client != null && identical(_transport, t) &&
            timeout.op != CcOp.ping && client.responsesReceived == timeout.responsesAtSend) {
          _loseLink('手环没有应答，连接已失效。可以直接重连。');
        }
      });
      _closedSub = t.closed.asStream().listen((_) {
        if (identical(_transport, t)) {
          _loseLink(_readable(t.failure ?? StateError('蓝牙串口已断开')));
        }
      });
      final engine = _engine = FileEngine(client);
      _set(LinkState.handshaking);
      if (attempt.canceled) return;
      final hello = await engine.handshake();
      if (attempt.canceled) return;
      if (t.failure case final failure?) throw failure;
      _hello = hello;
      _delivery = DeliveryClient(client)..chunk = engine.chunk;
      _nsh = NshClient(client);
      _connected = device;
      _startHeartbeat(engine);
      _set(LinkState.ready);
      unawaited(_refreshAccess());
    } catch (e) {
      if (attempt.canceled) return;
      final String reason;
      if (_state == LinkState.handshaking) {
        reason = e is TimeoutException
            ? '蓝牙串口已打开，但手环没有回复 ChaosConnect 握手。'
            : '蓝牙串口已打开，但握手没完成：${_readable(e)}';
      } else {
        reason = _readable(e);
      }
      await _clearLink();
      if (!attempt.canceled) _set(LinkState.failed, error: reason);
    } finally {
      if (!attempt.canceled) _attempt = null;
      attempt.done.complete();
    }
  }

  /// 平台层抛上来的 PlatformException 自带人话 message; 直接 toString() 会把
  /// "PlatformException(connect, ..., null, null)" 这种壳子也贴到界面上。
  static String _readable(Object e) {
    if (e is PlatformException) return e.message ?? e.code;
    // op 0 是 CcClient 给"载波断了"留的位置, 不是真的哪个操作失败。
    // 这时候 detail 就是断开原因, 界面只需要那一句。
    if (e is CcException && e.op == 0 && e.detail.isNotEmpty) {
      return e.detail.replaceFirst('Bad state: ', '');
    }
    return e.toString().replaceFirst('Bad state: ', '');
  }

  /// 固件在 15 秒收不到有效请求时会清掉会话，但蓝牙串口不一定关闭。
  /// 普通请求已经有应答时不额外打扰；空闲时用 PING 续期，也顺便探测失联。
  void _startHeartbeat(FileEngine engine) {
    final client = engine.client;
    int previousResponses = client.responsesReceived;
    bool probing = false;
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) async {
      if (_disposed || !isReady || !identical(_engine, engine) || probing) return;
      final responses = client.responsesReceived;
      final active = responses != previousResponses;
      previousResponses = responses;
      // 不把心跳排到满窗口后面。若请求都没应答，普通请求的超时也会结束会话。
      if (active || !client.hasWindowSlot) return;
      probing = true;
      try {
        await _probeHeartbeat(engine);
      } finally {
        previousResponses = client.responsesReceived;
        probing = false;
      }
    });
  }

  Future<void> _probeHeartbeat(FileEngine engine) async {
    final client = engine.client;
    for (int attempt = 0; attempt < 2; attempt++) {
      if (_disposed || !isReady || !identical(_engine, engine) || !client.hasWindowSlot) return;
      try {
        final ping = await engine.ping(timeout: _heartbeatTimeout);
        if (!identical(_engine, engine)) return;
        if (!ping.connected) {
          _loseLink('手环已结束这次会话。可以直接重连。');
        } else if (_ping?.devMode != ping.devMode || _ping?.authState != ping.authState ||
            _ping?.policy != ping.policy || _ping?.token != ping.token) {
          _ping = ping;
          _notify();
        }
        return;
      } on CcRequestTimeout catch (e) {
        // 一帧丢失不等于断线；若同时有其他匹配的应答，也不必重连。
        if (!identical(_engine, engine) || client.responsesReceived != e.responsesAtSend) return;
      } catch (_) {
        // 非 OK 应答仍说明手环能回包；底层真断开另有 closed 回调。
        return;
      }
    }
    if (identical(_engine, engine)) {
      _loseLink('手环没有回复心跳，连接已失效。可以直接重连。');
    }
  }

  void _loseLink(String reason) {
    if (_disposed || !isReady || releasing) return;
    // 先登记同一份关闭任务，再让 UI 显示失联。等旧串口完全释放后才允许重连。
    final task = _disconnecting = _clearLink();
    _set(LinkState.failed, error: reason);
    unawaited(_finishRelease(task));
  }

  Future<void> _finishRelease(Future<void> task) async {
    try {
      await task;
    } finally {
      if (identical(_disconnecting, task)) {
        _disconnecting = null;
        _notify();
      }
    }
  }

  Future<void> _refreshAccess() async {
    final FileEngine? e = _engine;
    if (e == null) return;
    try {
      final access = await e.access();
      if (!identical(_engine, e)) return;
      _access = access;
      _notify();
    } catch (_) {
      // 老模块没有 GET_ACCESS; 不影响文件读写
    }
  }

  /// 重新读一次权限位(用户在设备上点了允许之后要刷新)。
  Future<void> refreshAccess() => _refreshAccess();

  Future<void> setDevMode(bool on) async {
    final FileEngine? e = _engine;
    if (e == null) return;
    await e.setDevMode(on);
    await _refreshAccess();
  }

  Future<void> disconnect({bool silent = false}) async {
    final task = _disconnecting ??= _stopLink();
    try {
      await task;
    } finally {
      if (identical(_disconnecting, task)) _disconnecting = null;
    }
    if (!silent) _set(LinkState.idle);
  }

  Future<void> _stopLink() async {
    final attempt = _attempt;
    if (attempt != null) attempt.canceled = true;
    // 先把清理任务挂到 _disconnecting，再通知界面，避免监听者重入。
    await Future<void>.value();
    _notify();
    await _clearLink();
    if (attempt != null) {
      await attempt.done.future;
      if (identical(_attempt, attempt)) _attempt = null;
    }
  }

  Future<void> _clearLink() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    final closedSub = _closedSub;
    final client = _client;
    final transport = _transport;
    _closedSub = null;
    _client = null;
    _transport = null;
    _engine = null;
    _delivery = null;
    _nsh = null;
    nshOutput = '';
    nshStatus = null;
    _hello = null;
    _access = null;
    _ping = null;
    _connected = null;
    await closedSub?.cancel();
    await client?.close();
    await transport?.close();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect(silent: true));
    super.dispose();
  }
}
