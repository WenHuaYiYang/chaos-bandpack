import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chaos/ansi_terminal.dart';
import '../../chaos/delivery.dart';
import '../../protocol/cc_client.dart';
import '../../protocol/ops.dart';
import '../../chaos/session.dart';
import '../../chaos/session_scope.dart';
import '../component/app_icons.dart';
import '../component/maker_scaffold.dart';
import '../theme/paper_palette.dart';
import '../theme/tone.dart';

/// 真终端界面: 一段滚动的输出 + 一行命令输入。
///
/// 手环那头是"命令 + 换行进 PTY、字节流出 PTY", 不是全屏 VT100, 所以这里也
/// 不假装自己是 xterm: 保留完整滚动记录、可选文本、Ctrl+C 和清屏, 其余交给 shell。
class NshScreen extends StatefulWidget {
  const NshScreen({super.key});

  @override
  State<NshScreen> createState() => _NshScreenState();
}

class _NshScreenState extends State<NshScreen> with WidgetsBindingObserver {
  static const int _maxChars = 32000;
  static const Duration _foregroundPoll = Duration(milliseconds: 150);
  static const Duration _backgroundPoll = Duration(seconds: 1);

  late ChaosSession _session;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  final AnsiTerminal _screen = AnsiTerminal(columns: 96, maxLines: 3000);
  NshStatus? _status;
  Timer? _poll;
  bool _polling = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = SessionScope.read(context);
    WidgetsBinding.instance.addObserver(this);
    _status = _session.nshStatus;
    _screen.write(_session.nshOutput);
    _session.addListener(_onSession);
    _schedule();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSession);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _schedule();

  void _onSession() {
    if (!mounted) return;
    if (_session.nsh == null) {
      _poll?.cancel();
      setState(() {
        _status = null;
        _error = _session.error ?? '连接已断开';
      });
    }
  }

  void _schedule() {
    _poll?.cancel();
    final active = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _poll = Timer.periodic(active ? _foregroundPoll : _backgroundPoll, (_) => _pull());
  }

  Future<void> _pull() async {
    final nsh = _session.nsh;
    // 没有 lease 时设备侧什么也不会回; 直接 READ 只会抛"会话还没开"。
    // 这个轮询是按时间触发的, 必须在发请求之前就问清楚有没有会话。
    if (_polling || nsh == null || nsh.lease == null) return;
    _polling = true;
    try {
      final read = await nsh.read();
      if (!mounted) return;
      _append(read.output.isEmpty ? null : read.text, read.status);
    } catch (err) {
      // 单次读取失败不关界面: 真断开由 session 统一通知, 这里只是这一拍没拿到。
      if (mounted && _error == null) setState(() => _error = _clean(err));
    } finally {
      _polling = false;
    }
  }

  void _append(String? text, NshStatus status) {
    setState(() {
      _status = status;
      if (text != null && text.isNotEmpty) {
        // 交给终端模型解释转义序列; 原始字节也留一份, 切页回来能重放。
        _screen.write(text);
        final raw = _session.nshOutput + text;
        _session.nshOutput =
            raw.length > _maxChars ? raw.substring(raw.length - _maxChars) : raw;
      }
      if (status.running || status.state == NshState.starting) _error = null;
    });
    _session.nshStatus = status;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _open() async {
    final nsh = _session.nsh;
    if (nsh == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 设备侧回收旧 PTY 是异步的: 期间 OPEN 会一直回 BUSY。这里做有界退避,
      // 让"刚关掉又马上重开"能自己过去; 超过次数就停下, 免得把设备刷成持续繁忙。
      NshStatus? status;
      for (int attempt = 1; attempt <= 5; attempt++) {
        try {
          status = await nsh.open();
          break;
        } on CcException catch (err) {
          if (err.status != CcStatus.busy || attempt == 5) rethrow;
          if (mounted) {
            setState(() => _error = '手环正在回收上一个终端，等待中…（第 ' + attempt.toString() + ' 次）');
          }
          await Future<void>.delayed(Duration(milliseconds: 700 * attempt));
          if (!mounted) return;
        }
      }
      if (!mounted || status == null) return;
      _error = null;
      _append(null, status);
      // 打开后立刻取一次: 设备侧可能还留着上一轮的提示行(权限、欢迎语)。
      await _pull();
      _focus.requestFocus();
    } on CcException catch (err) {
      if (mounted) setState(() => _error = _hint(err));
    } catch (err) {
      if (mounted) setState(() => _error = _clean(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final nsh = _session.nsh;
    final line = _input.text;
    if (nsh == null || line.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await nsh.write(line.endsWith('\n') ? line : line + '\n');
      if (!mounted) return;
      _input.clear();
      await _pull();
    } on CcException catch (err) {
      if (mounted) setState(() => _error = _hint(err));
    } catch (err) {
      if (mounted) setState(() => _error = _clean(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _interrupt() async {
    final nsh = _session.nsh;
    if (nsh == null) return;
    try {
      await nsh.write('\u0003');
    } catch (_) {
      // 写不进去也没有别的办法; 用户可以关掉会话重开。
    }
  }

  Future<void> _close() async {
    final nsh = _session.nsh;
    if (nsh == null || _busy) return;
    setState(() => _busy = true);
    try {
      await nsh.close();
    } catch (err) {
      if (mounted) setState(() => _error = _clean(err));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
          _session.nshStatus = null;
        });
      }
    }
  }

  /// StateError 的 toString 前面永远挂着 "Bad state: ", 那是给调试看的。
  static String _clean(Object err) => err.toString().replaceFirst('Bad state: ', '');

  static String _hint(CcException err) {
    if (err.status == 8) {
      // 手环只有在旧 shell 真正退出后才允许新会话。如果一条命令卡住不退，
      // 它会一直停在回收中，等多久都没用 —— 这时只能让手环那边彻底重启。
      return '手环上的旧终端还没退出，所以暂时开不了新会话。'
          '先等十几秒点「重新打开」；仍然不行就在手环上关掉再打开 ChaosConnect，'
          '或者重启一次手环。';
    }
    if (err.status == 3) return '手环没有授权 NSH。到 ChaosConnect 的 Android 端权限里打开「NSH 终端」。';
    if (err.status == 11) return '会话已经换了一茬，重新打开会话。';
    return '终端请求失败：' + err.statusName;
  }

  @override
  Widget build(BuildContext context) {
    final tone = ToneScope.of(context);
    final theme = Theme.of(context);
    final status = _status;
    final running = status?.running ?? false;
    final phase = status == null
        ? '未打开'
        : running
            ? '运行中'
            : status.state == NshState.starting
                ? '启动中'
                : status.state == NshState.stopping
                    ? '正在回收'
                    : status.state == NshState.exited
                        ? '已退出'
                        : '失败';
    return MakerScaffold(
      navReserve: false,
      title: '终端',
      subtitle: _session.connected?.name ?? '手环',
      leading: IconButton(
        tooltip: '返回',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(AppIcons.back),
      ),
      actions: <Widget>[
        IconButton(
          tooltip: '清屏',
          onPressed: () => setState(_screen.reset),
          icon: const Icon(AppIcons.clear),
        ),
        if (!running)
          TextButton(
            onPressed: _busy ? null : _open,
            child: Text(status == null ? '打开会话' : '重新打开'),
          ),
        if (running)
          IconButton(
            tooltip: '关闭会话',
            onPressed: _busy ? null : _close,
            icon: const Icon(AppIcons.unlinked),
          ),
      ],
      bottomBar: _inputBar(tone, running),
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: running ? const Color(0xFF30A46C) : tone.muted,
              ),
            ),
            const SizedBox(width: 8),
            Text(phase, style: theme.textTheme.bodySmall?.copyWith(color: tone.muted)),
            if (status != null && status.error != 0) ...<Widget>[
              const SizedBox(width: 8),
              Text('errno ' + status.error.toString(),
                  style: theme.textTheme.bodySmall?.copyWith(color: tone.muted)),
            ],
          ],
        ),
        if (_error case final message?) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message, style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
        ),
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          constraints: const BoxConstraints(minHeight: 240),
          decoration: BoxDecoration(
            color: const Color(0xFF16150F),
            borderRadius: BorderRadius.circular(PaperPalette.shapeMd),
          ),
          child: SingleChildScrollView(
            controller: _scroll,
            child: _TerminalView(screen: _screen),
          ),
        ),
      ],
    );
  }

  Widget _inputBar(PageTone tone, bool running) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: tone.card,
        borderRadius: BorderRadius.circular(PaperPalette.shapeLg),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: <Widget>[
          Text(r'$', style: TextStyle(fontFamily: 'monospace', fontSize: 14, color: tone.muted)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _focus,
              enabled: running,
              textInputAction: TextInputAction.send,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.deny(RegExp('[\u0000\u0004]')),
              ],
              onSubmitted: (_) => _send(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: running ? '输入命令，回车执行' : '先打开会话',
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          IconButton(
            tooltip: '中断 (Ctrl+C)',
            onPressed: running ? _interrupt : null,
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
          ),
          IconButton(
            tooltip: '发送',
            onPressed: running && !_busy ? _send : null,
            icon: const Icon(AppIcons.send, size: 20),
          ),
        ],
      ),
    );
  }
}

/// 把字符网格画成一行行 Text。相邻同样式的格子合并成一个 span,
/// 一条 96 列的行通常只剩几段, 重绘成本远低于一格一个 Widget。
class _TerminalView extends StatelessWidget {
  const _TerminalView({required this.screen});

  final AnsiTerminal screen;

  static const Color _defaultFg = Color(0xFFE8E6DA);

  @override
  Widget build(BuildContext context) {
    final lines = screen.lines;
    final bool empty = lines.length == 1 && screen.toText().trim().isEmpty;
    if (empty) {
      return const Text(
        '输入命令后按回车。Ctrl+C 可中断当前命令。',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.5,
          color: Color(0xFF8B8B7E),
        ),
      );
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final line in lines)
            Text.rich(
              TextSpan(children: _spans(line)),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.5,
                color: _defaultFg,
              ),
            ),
        ],
      ),
    );
  }

  static List<InlineSpan> _spans(List<AnsiCell> line) {
    final spans = <InlineSpan>[];
    final buf = StringBuffer();
    AnsiStyle? current;

    void flush() {
      if (buf.isEmpty) return;
      final style = current ?? AnsiStyle.plain;
      Color? fg = style.fg == null ? null : Color(0xFF000000 | style.fg!);
      Color? bg = style.bg == null ? null : Color(0xFF000000 | style.bg!);
      if (style.reverse) {
        final Color text = fg ?? _defaultFg;
        final Color back = bg ?? const Color(0xFF16150F);
        fg = back;
        bg = text;
      }
      spans.add(TextSpan(
        text: buf.toString(),
        style: TextStyle(
          color: fg,
          backgroundColor: bg,
          fontWeight: style.bold ? FontWeight.w700 : null,
          decoration: style.underline ? TextDecoration.underline : null,
        ),
      ));
      buf.clear();
    }

    for (final cell in line) {
      if (cell.style != current) {
        flush();
        current = cell.style;
      }
      buf.write(cell.ch);
    }
    flush();
    // 去掉行尾空白, 免得每行都拖一条看不见的尾巴。
    while (spans.isNotEmpty) {
      final last = spans.last;
      if (last is! TextSpan || last.text == null) break;
      final trimmed = last.text!.replaceFirst(RegExp(r'\s+$'), '');
      if (trimmed.isEmpty) {
        spans.removeLast();
      } else {
        if (trimmed != last.text) {
          spans[spans.length - 1] = TextSpan(text: trimmed, style: last.style);
        }
        break;
      }
    }
    if (spans.isEmpty) spans.add(const TextSpan(text: ' '));
    return spans;
  }
}
