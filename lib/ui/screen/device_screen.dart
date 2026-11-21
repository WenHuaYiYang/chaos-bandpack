import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../chaos/delivery.dart';
import '../../chaos/file_engine.dart';
import '../../chaos/session.dart';
import '../../chaos/session_scope.dart';
import '../../chaos/spp_transport.dart' show SppPeer;
import '../../protocol/cc_client.dart';
import '../../protocol/ops.dart';
import '../component/app_icons.dart';
import '../component/link_pulse.dart';
import '../component/maker_route.dart';
import '../../project/project_store.dart';
import '../../chaos/beauty_sync.dart';
import 'files_screen.dart';
import 'nsh_screen.dart';
import '../component/maker_scaffold.dart';
import '../component/paper_card.dart';
import '../theme/paper_palette.dart';
import '../theme/tone.dart';

/// 设备页: 配对 -> 连接 -> 握手 -> 权限 -> 文件浏览 -> NSH。
///
/// 真机通信的每一步在页面上都有可见反馈, 因为 SPP 出问题(配对丢了、能力位不够、
/// 权限位没开)在别处完全看不出来 —— 表现只是“投递失败”。
class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

enum _DeviceAction { link, files, install, nsh }

class _DeviceScreenState extends State<DeviceScreen> {
  static const String _rootPath = '/data/chaos';

  /// 会话归应用外壳所有 —— 切到别的页再回来链路还在, 不必重新握手。
  late final ChaosSession _session;
  FileEngine? _readyEngine;
  Object? _operation;
  final _notes = <_DeviceAction, String>{};
  bool get _busy => _operation != null;
  bool get _ready => _readyEngine != null;
  /// 这一次进页面后有没有真的搜过。用来区分"还没搜"和"搜了但附近没有"。
  bool _searched = false;


  @override
  void initState() {
    super.initState();
    _session = SessionScope.read(context);
    _readyEngine = _activeEngine;
    _session.addListener(_onSession);
    // 只在还没连上时扫一次: 断开重进页面不该把已连的链路打断。
    // 必须推迟到首帧之后 —— scan() 会立刻 notifyListeners, 而 initState 处于
    // build 阶段, 当场通知会让 SessionScope 在构建中标记为需要重建并断言失败。
    if (_session.state == LinkState.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_session.releasing && _session.state == LinkState.idle) {
          unawaited(_session.scan());
        }
      });
    }
  }

  FileEngine? get _activeEngine =>
      _session.isReady && !_session.releasing ? _session.engine : null;

  void _onSession() {
    if (!mounted) return;
    final engine = _activeEngine;
    final lostLink = _ready && !identical(_readyEngine, engine);
    setState(() {
      _readyEngine = engine;
      if (lostLink) {
        // 旧连接的 Future 可能还没结束，不能让它改下一条连接的界面。
        _operation = null;
        _notes.clear();
      }
    });
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    super.dispose();
  }

  Future<void> _guard(
    Future<void> Function(bool Function() current) job, {
    _DeviceAction action = _DeviceAction.link,
  }) async {
    if (_busy || _session.releasing) return;
    final operation = Object();
    bool current() => mounted && identical(_operation, operation);
    setState(() {
      _operation = operation;
      _notes.remove(action);
    });
    try {
      await job(current);
    } catch (e) {
      if (current()) setState(() => _notes[action] = _actionError(e));
    } finally {
      if (current()) setState(() => _operation = null);
    }
  }

  static String _actionError(Object error) => switch (error) {
    CcRequestTimeout(op: CcOp.list) => '手环未回复目录读取。若仍显示已连接，可点「刷新」重试。',
    CcException(op: CcOp.nshOpen, status: CcStatus.busy) =>
      '手环终端正忙，蓝牙仍已连接。请关闭其他终端会话，或稍后再试。',
    _ => error.toString().replaceFirst('Bad state: ', ''),
  };

  Future<void> _connect(BandDevice device) =>
      _guard((_) => _session.connect(device));

  @override
  Widget build(BuildContext context) {
    final PageTone tone = ToneScope.of(context);
    return MakerScaffold(
      title: '设备',
      subtitle: _subtitle(),
      actions: <Widget>[
        if (_ready)
          IconButton(
            tooltip: '断开',
            onPressed: _busy ? null : () => _guard((_) => _session.disconnect()),
            icon: const Icon(AppIcons.unlinked),
          ),
      ],
      children: <Widget>[
        if (_session.error != null) _errorCard(_session.error!, tone),
        _linkCard(tone),
        if (_notes[_DeviceAction.link] case final note?) _errorCard(note, tone),
        if (_ready) ...<Widget>[
          _helloCard(tone),
          _accessCard(tone),
          _filesCard(tone),
          _installCard(tone),
          _nshCard(tone),
        ],
      ],
    );
  }

  String _subtitle() => _session.releasing
      ? '正在释放旧连接…'
      : switch (_session.state) {
        LinkState.idle => _session.adapter == 'on' ? '选择一台已配对的手环' : '蓝牙不可用',
        LinkState.scanning => '正在读已配对设备…',
        LinkState.connecting => _session.canceling ? '正在取消…' : '正在打开蓝牙串口…',
        LinkState.handshaking => _session.canceling ? '正在取消…' : '正在等待手环握手…',
        LinkState.ready => _session.connected?.name ?? '已连接',
        LinkState.failed => '未连接',
      };

  Widget _errorCard(String message, PageTone tone) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0xFFB3261E).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(PaperPalette.shapeMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(AppIcons.error, color: Color(0xFFB3261E), size: 17),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF8C1D18), fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkCard(PageTone tone) {
    final bool ready = _ready;
    final bool searching = _session.searching;
    final bool releasing = _session.releasing;
    final bool locked = _busy || searching || releasing || _session.isConnecting ||
        _session.state == LinkState.scanning;
    final BandDevice? reconnect = _session.state == LinkState.failed
        ? _session.reconnectDevice
        : null;
    final bool canCancel = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows && _session.isConnecting;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              LinkPulse(
                active: ready,
                busy: _session.isConnecting || searching || releasing,
                size: 58,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text(
                        (ready ? _session.connected?.name : reconnect?.name) ?? '已配对的手环',
                        key: ValueKey<String>(
                          (ready ? _session.connected?.address : reconnect?.address) ?? 'none',
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _StatusBadge(
                      label: ready
                          ? '已握手'
                          : _session.isConnecting
                              ? '正在接通'
                              : searching
                                  ? '正在搜索'
                                  : reconnect != null
                                      ? '连接已断开'
                                      : '待连接',
                      color: ready
                          ? const Color(0xFF30A46C)
                          : _session.state == LinkState.failed
                              ? const Color(0xFFB3261E)
                              : tone.deep,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (canCancel)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _session.canceling ? null : () => unawaited(_session.disconnect()),
                child: const Text('取消连接'),
              ),
            ),
          if (reconnect != null)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: locked ? null : () => _connect(reconnect),
                icon: const Icon(AppIcons.refresh, size: 18),
                label: const Text('重连'),
              ),
            ),
          if (!ready && _session.devices.isEmpty && !searching)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: locked ? null : () => _guard((_) => _session.scan()),
                icon: const Icon(AppIcons.refresh, size: 18),
                label: Text(_session.adapter == 'on' ? '重新读取已配对' : '检查蓝牙'),
              ),
            ),
          for (final BandDevice d in _session.devices)
            SettingRow(
              title: d.name,
              subtitle: d.address,
              onTap: locked || ready ? null : () => _connect(d),
              trailing: ready && _session.connected?.address == d.address
                  ? const Icon(AppIcons.ok, size: 20)
                  : const Icon(AppIcons.linked, size: 20),
            ),
          if (!ready) ...<Widget>[
            const SizedBox(height: 6),
            _searchBlock(tone, searching: searching, locked: locked),
          ],
          if (ready)
            Text(
              '块 ${_session.engine?.chunk ?? 0} B · 窗口 ${_session.hello?.window ?? 0} · 路径上限 ${_session.hello?.maxPath ?? 0}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tone.muted),
            ),
        ],
      ),
    );
  }

  /// 主动搜索那一块。与上面的"已配对"列表分开: 上面是历史, 这里是此刻空气里
  /// 有什么。搜一次要十几秒, 所以按钮和进度条都得说清楚现在在干嘛。
  Widget _searchBlock(PageTone tone, {required bool searching, required bool locked}) {
    // 已配对的设备在上面的列表里已经有了, 这里只列新的, 免得同一台手环出现两次。
    final Set<String> known = <String>{
      for (final BandDevice d in _session.devices) d.address,
    };
    final List<SppPeer> fresh = <SppPeer>[
      for (final SppPeer p in _session.peers)
        if (!p.paired && !known.contains(p.address)) p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Divider(height: 22, color: tone.muted.withValues(alpha: 0.18)),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                searching ? '正在搜索附近的设备…' : '附近的设备',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (searching)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        if (searching)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '大约十秒。手环那边先打开 ChaosConnect, 点「发起蓝牙配对」, 它才会对外应答。',
              style: TextStyle(fontSize: 11.5, color: tone.muted),
            ),
          ),
        if (!searching && _searched && fresh.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '附近没有搜到新设备。手环要停在 ChaosConnect 的配对页才会应答; 已经配过对的直接在上面那一栏点它。',
              style: TextStyle(fontSize: 12, color: tone.muted),
            ),
          ),
        for (final SppPeer p in fresh)
          SettingRow(
            leading: Icon(AppIcons.device, size: 20, color: tone.muted),
            title: p.name.isEmpty ? p.address : p.name,
            subtitle: p.name.isEmpty ? '未配对' : p.address + ' · 未配对',
            trailing: locked
                ? null
                : TextButton(
                    onPressed: () => _guard((current) async {
                      final bool ok = await _session.pair(p);
                      if (!ok && current()) {
                        setState(() => _notes[_DeviceAction.link] = '这台机器不支持从应用里发起配对, 到系统的蓝牙设置里配一次');
                      }
                    }),
                    child: const Text('配对'),
                  ),
          ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: locked
                ? null
                : () async {
                    if (_session.releasing) return;
                    setState(() => _notes.remove(_DeviceAction.link));
                    await _session.search();
                    if (mounted) setState(() => _searched = true);
                  },
            icon: const Icon(AppIcons.search, size: 18),
            label: Text(_searched ? '再搜一次' : '搜索附近设备'),
          ),
        ),
        if (_session.adapter != 'on')
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '蓝牙没打开的时候搜不到任何东西。',
              style: TextStyle(fontSize: 11.5, color: tone.muted),
            ),
          ),
      ],
    );
  }

  Widget _helloCard(PageTone tone) {
    final CcHello? h = _session.hello;
    if (h == null) return const SizedBox.shrink();
    final List<String> caps = <String>[
      if (h.hasRmdir) '递归删除',
      if (h.hasDelivery) '投递包',
      if (h.hasNsH) 'NSH',
      if (h.androidCarrier) 'Android 载波',
      if (h.devMode) '开发者模式',
    ];
    return PaperCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionLabel('握手'),
            Text(
              '协议 v${h.version} · 能力 ${caps.isEmpty ? '无' : caps.join(' / ')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tone.muted),
            ),
            if (!h.androidCarrier)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '模块版本太旧: 传文件还行, NSH 和投递包用不了。',
                  style: TextStyle(fontSize: 12, color: tone.muted),
                ),
              ),
          ],
        ),
    );
  }

  Widget _accessCard(PageTone tone) {
    final CcAccess? a = _session.access;
    return PaperCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionLabel('权限'),
            SettingRow(
              title: '读取文件',
              subtitle: _permSub(a, CcPerm.read),
              trailing: _permIcon(a, CcPerm.read),
            ),
            SettingRow(
              title: '写入 / 投递',
              subtitle: _permSub(a, CcPerm.write),
              trailing: _permIcon(a, CcPerm.write),
            ),
            SettingRow(
              title: '删除与重命名',
              subtitle: _permSub(a, CcPerm.deleteRename),
              trailing: _permIcon(a, CcPerm.deleteRename),
            ),
            SettingRow(
              title: 'NSH 终端',
              subtitle: _permSub(a, CcPerm.nsh),
              trailing: _permIcon(a, CcPerm.nsh),
            ),
            SettingRow(
              title: '开发者模式',
              subtitle: a == null ? '未知' : (a.allows(CcPerm.devMode) ? '已开启' : '已关闭'),
              trailing: Switch(
                value: a?.allows(CcPerm.devMode) ?? false,
                onChanged: _busy || a == null ? null : (v) => _guard((_) => _session.setDevMode(v)),
              ),
            ),
            if (a != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '策略 ${_policyName(a.policy)} · 判定 ${a.authName} · 载波 ${a.android ? 'Android' : '文件桥'}',
                  style: TextStyle(fontSize: 11.5, color: tone.muted),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _guard((_) => _session.refreshAccess()),
                icon: const Icon(AppIcons.refresh, size: 17),
                label: const Text('刷新权限'),
              ),
            ),
          ],
        ),
    );
  }

  String _policyName(int policy) => switch (policy) {
        CcPolicy.allow => '允许',
        CcPolicy.deny => '拒绝',
        _ => '询问',
      };

  String _permSub(CcAccess? a, int bit) {
    if (a == null) return '设备没有返回权限表(旧模块)';
    return a.allows(bit) ? '已授予' : '未授予 —— 在手环的 Chaos 应用里开';
  }

  Widget _permIcon(CcAccess? a, int bit) {
    final bool on = a?.allows(bit) ?? false;
    return Icon(
      on ? AppIcons.ok : AppIcons.clear,
      size: 20,
      color: on ? const Color(0xFF30A46C) : Colors.grey,
    );
  }

  Widget _filesCard(PageTone tone) {
    final CcAccess? a = _session.access;
    final bool canRead = a?.allows(CcPerm.read) ?? false;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('文件'),
          const SizedBox(height: 2),
          Text(
            canRead ? '浏览、下载、上传、改名和删除手环上的文件' : '手环没给读取权限, 到 ChaosConnect 的 Android 端权限里打开',
            style: TextStyle(fontSize: 12.5, color: tone.muted),
          ),
          if (_notes[_DeviceAction.files] case final note?)
            Padding(padding: const EdgeInsets.only(top: 10), child: _errorCard(note, tone)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: !canRead || _busy ? null : _openFiles,
              icon: const Icon(AppIcons.folder, size: 18),
              label: const Text('打开文件管理'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFiles() async {
    final session = _session;
    final project = ProjectScope.read(context);
    final tone = TonePalette.device(context);
    await Navigator.of(context).push(
      makerRoute(
        label: '文件',
        page: const FilesScreen(),
        tone: (_) => tone,
        session: session,
        project: project,
      ),
    );
  }

  /// 安装资源包: 直接选一份 .chp 同步过去。
  ///
  /// 制作页也能同步, 但"从别处拿到一个美化包, 想装上"是更常见的场景, 那时
  /// 用户手上没有工程, 只有一个文件。这里走同一条安装通道, 不重复实现。
  Widget _installCard(PageTone tone) {
    final CcHello? h = _session.hello;
    final bool supported = h?.hasDelivery == true && h?.androidCarrier == true;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('安装资源包'),
          const SizedBox(height: 2),
          Text(
            supported
                ? '选一份 .chp 美化包, 手环确认后安装到空闲槽位'
                : '这份固件不支持资源直传, 可用旧版 .bin 投递表盘',
            style: TextStyle(fontSize: 12.5, color: tone.muted),
          ),
          if (_notes[_DeviceAction.install] case final note?)
            Padding(padding: const EdgeInsets.only(top: 10), child: _errorCard(note, tone)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: !supported || _busy ? null : _installPack,
              icon: const Icon(AppIcons.build, size: 18),
              label: const Text('选择美化包'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _installPack() async {
    final selected = await BeautySync.pick();
    if (selected == null || !mounted) return;
    await _guard((current) async {
      await BeautySync.send(_session, selected.pack);
      if (current()) {
        setState(() => _notes[_DeviceAction.install] =
            '已安装「' + selected.pack.name + '」。到手环的字体／图标列表里选择, 不会自动切换。');
      }
    }, action: _DeviceAction.install);
  }

  Widget _nshCard(PageTone tone) {
    final bool hasNsh = _session.access?.allows(CcPerm.nsh) ?? false;
    final NshStatus? status = _session.nshStatus;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('NSH 终端'),
          const SizedBox(height: 2),
          Text(
            hasNsh
                ? (status?.running == true ? '会话运行中，进入终端继续操作' : '可以在手环上执行系统命令')
                : '需要先开 NSH 权限位(设备侧 /data/chaos/connect-android.cfg)',
            style: TextStyle(fontSize: 12.5, color: tone.muted),
          ),
          if (_notes[_DeviceAction.nsh] case final note?)
            Padding(padding: const EdgeInsets.only(top: 10), child: _errorCard(note, tone)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: !hasNsh || _busy ? null : _openTerminal,
              icon: const Icon(AppIcons.forward, size: 18),
              label: const Text('打开终端'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openTerminal() async {
    final NavigatorState nav = Navigator.of(context);
    final session = _session;
    final project = ProjectScope.read(context);
    final tone = TonePalette.device(context);
    nav.push(
      makerRoute(
        label: '终端',
        page: const NshScreen(),
        tone: (_) => tone,
        session: session,
        project: project,
      ),
    );
  }

}

/// 链路阶段的小胶囊。颜色只承担"通/没通"，文字负责说清在哪一步，
/// 免得用户把"正在接通"和"已握手"看成同一个状态。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              label,
              key: ValueKey<String>(label),
              style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
