import 'package:flutter/material.dart';

import '../../chaos/beauty_sync.dart';
import '../../chaos/delivery.dart';
import '../../chaos/session_scope.dart';
import '../../pack/beauty_pack.dart';
import '../component/app_icons.dart';
import '../component/maker_scaffold.dart';
import '../component/paper_card.dart';

class BeautyPackScreen extends StatefulWidget {
  const BeautyPackScreen({required this.pack, required this.fileName, super.key});

  final BeautyPack pack;
  final String fileName;

  @override
  State<BeautyPackScreen> createState() => _BeautyPackScreenState();
}

class _BeautyPackScreenState extends State<BeautyPackScreen> {
  bool _busy = false;
  String? _note;
  String? _error;
  double? _progress;

  Future<void> _send() async {
    if (_busy) return;
    final session = SessionScope.read(context);
    setState(() {
      _busy = true;
      _note = '正在检查手环';
      _error = null;
      _progress = null;
    });
    try {
      await BeautySync.send(
        session,
        widget.pack,
        onState: (ticket) {
          if (!mounted) return;
          setState(() => _note = switch (ticket.state) {
            DeliveryState.awaitingConsent => '请在手环上确认安装',
            DeliveryState.allowed => '手环已允许，准备传输',
            DeliveryState.transferring => '正在传输资源',
            _ => DeliveryState.name(ticket.state),
          });
        },
        onProgress: (sent, total) {
          if (!mounted) return;
          setState(() {
            _progress = total == 0 ? null : sent / total;
            if (sent == total) _note = '资源已发送，等待手环校验并安装';
          });
        },
      );
      if (mounted) setState(() => _note = '已安装。请在手环的对应列表中选择，不会自动替换当前资源。');
    } catch (error) {
      if (mounted) setState(() {
        _note = null;
        _error = BeautySync.readableError(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pack = widget.pack;
    final session = SessionScope.of(context);
    final theme = Theme.of(context);
    final reason = BeautySync.unavailableReason(session, pack.device);
    final bytes = pack.files.values.fold(0, (int total, value) => total + value.length);
    final kind = pack.kind == BeautyKind.font ? '字体' : '图标';
    return PopScope(
      canPop: !_busy,
      child: MakerScaffold(
        navReserve: false,
        title: '美化包',
        subtitle: widget.fileName,
        leading: IconButton(
          tooltip: '返回',
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
          icon: const Icon(AppIcons.back),
        ),
        children: [
          PaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pack.name, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('小米手环 ${pack.device.label} · $kind · ${pack.files.length} 个文件'),
                Text('资源大小：${(bytes / 1024).toStringAsFixed(1)} KiB'),
                const SizedBox(height: 12),
                for (final file in pack.files.keys.take(8)) Text(file, style: theme.textTheme.bodySmall),
                if (pack.files.length > 8) Text('另有 ${pack.files.length - 8} 个文件'),
              ],
            ),
          ),
          PaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (session.connected case final device?) Text('当前手环：${device.name}'),
                if (reason != null && !_busy) Text(reason, style: theme.textTheme.bodySmall),
                if (_busy) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: _progress),
                ],
                if (_note case final note?) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note)),
                if (_error case final error?) Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error, style: TextStyle(color: theme.colorScheme.error)),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy || reason != null ? null : _send,
                  icon: const Icon(AppIcons.send),
                  label: const Text('同步到手环'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
