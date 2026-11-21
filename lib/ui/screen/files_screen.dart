import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../chaos/file_engine.dart';
import '../../chaos/session.dart';
import '../../chaos/session_scope.dart';
import '../../protocol/cc_client.dart';
import '../../protocol/ops.dart';
import '../component/app_icons.dart';
import '../component/maker_scaffold.dart';
import '../component/paper_card.dart';
import '../theme/paper_palette.dart';
import '../theme/tone.dart';

/// 手环文件管理器。
///
/// 手环那边的文件接口是"按路径的增删改查", 没有列表缓存也没有通配符, 所以这里
/// 只做最朴素的浏览器: 进目录、看大小、下载、上传、改名、删除。录像这类文件
/// 通常几十 MB, 下载按 2 KB 分块, 进度条必须真实反映已确认写入的字节。
class FilesScreen extends StatefulWidget {
  const FilesScreen({this.startPath = '/data/chaos', super.key});

  final String startPath;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  late final ChaosSession _session;
  late String _path = widget.startPath;
  List<CcEntry>? _entries;
  bool _busy = false;
  String? _note;
  String? _error;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _session = SessionScope.read(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  FileEngine? get _engine => _session.isReady ? _session.engine : null;

  Future<void> _run(Future<void> Function(FileEngine engine) job) async {
    final engine = _engine;
    if (engine == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
      _progress = null;
    });
    try {
      await job(engine);
    } catch (err) {
      if (mounted) setState(() => _error = _readable(err));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  static String _readable(Object err) {
    if (err is CcException) {
      if (err.detail.isNotEmpty) return err.detail;
      return switch (err.status) {
        CcStatus.access => '手环没给这个权限, 到 ChaosConnect 的 Android 端权限里打开。',
        CcStatus.notFound => '文件不存在, 可能刚被删掉。',
        CcStatus.exist => '目标已经存在。',
        CcStatus.noSpace => '手环空间不够。',
        CcStatus.isDir => '这是个目录。',
        CcStatus.notDir => '这不是目录。',
        CcStatus.io => '手环读写失败。',
        _ => '手环返回 ' + err.statusName,
      };
    }
    return err.toString().replaceFirst('Bad state: ', '');
  }

  Future<void> _refresh() => _run((engine) async {
        final list = await engine.listAll(_path);
        list.sort((a, b) {
          if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        if (!mounted) return;
        setState(() => _entries = list);
      });

  Future<void> _open(String path) async {
    setState(() => _path = path);
    await _refresh();
  }

  Future<void> _download(CcEntry entry) async {
    final path = _join(_path, entry.name);
    String? target = await FilePicker.platform.saveFile(
      dialogTitle: '保存 ' + entry.name,
      fileName: entry.name,
    );
    if (target == null || !mounted) return;
    await _run((engine) async {
      final bytes = await engine.readFile(path, onProgress: (done, total) {
        if (mounted && total > 0) setState(() => _progress = done / total);
      });
      await File(target!).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() => _note = '已保存到 ' + target);
    });
  }

  /// 把整个目录递归下载到本地。录像往往是一个目录里十几个文件, 一个个点太慢。
  Future<void> _downloadFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择保存位置');
    if (dir == null || !mounted) return;
    await _run((engine) async {
      var files = 0;
      var bytes = 0;
      Future<void> walk(String remote, Directory local) async {
        final list = await engine.listAll(remote);
        for (final entry in list) {
          final from = _join(remote, entry.name);
          if (entry.isDir) {
            final sub = Directory(local.path + Platform.pathSeparator + entry.name);
            await sub.create(recursive: true);
            await walk(from, sub);
          } else {
            final data = await engine.readFile(from);
            await File(local.path + Platform.pathSeparator + entry.name)
                .writeAsBytes(data, flush: true);
            files++;
            bytes += data.length;
            if (mounted) {
              setState(() => _note = '已下载 ' + files.toString() + ' 个文件');
            }
          }
        }
      }

      final base = Directory(dir + Platform.pathSeparator + _leaf(_path));
      await base.create(recursive: true);
      await walk(_path, base);
      if (!mounted) return;
      setState(() => _note = '已下载 ' + files.toString() + ' 个文件, 共 ' + _bytes(bytes));
    });
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(withReadStream: true);
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final file = picked.files.single;
    final Uint8List data;
    if (file.bytes != null) {
      data = file.bytes!;
    } else if (file.path != null) {
      data = await File(file.path!).readAsBytes();
    } else {
      setState(() => _error = '读不到这个文件的内容。');
      return;
    }
    await _run((engine) async {
      await engine.writeFile(
        _join(_path, file.name),
        data,
        onProgress: (done, total) {
          if (mounted && total > 0) setState(() => _progress = done / total);
        },
      );
      if (!mounted) return;
      setState(() => _note = '已上传 ' + file.name);
      await _refresh();
    });
  }

  Future<void> _rename(CcEntry entry) async {
    final name = await _ask('重命名', '新名字', entry.name);
    if (name == null || name == entry.name || !mounted) return;
    if (name.contains('/')) {
      setState(() => _error = '名字里不能带斜杠。');
      return;
    }
    await _run((engine) async {
      await engine.rename(_join(_path, entry.name), _join(_path, name));
      if (!mounted) return;
      setState(() => _note = '已改名');
      await _refresh();
    });
  }

  Future<void> _delete(CcEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ' + entry.name + '?'),
        content: Text(entry.isDir ? '目录必须为空才能删。' : '删除后无法恢复。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run((engine) async {
      final path = _join(_path, entry.name);
      if (entry.isDir) {
        await engine.rmdir(path);
      } else {
        await engine.remove(path);
      }
      if (!mounted) return;
      setState(() => _note = '已删除');
      await _refresh();
    });
  }

  Future<void> _mkdir() async {
    final name = await _ask('新建文件夹', '名字', '');
    if (name == null || name.isEmpty || !mounted) return;
    await _run((engine) async {
      await engine.mkdir(_join(_path, name));
      if (!mounted) return;
      setState(() => _note = '已创建');
      await _refresh();
    });
  }

  Future<String?> _ask(String title, String label, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tone = ToneScope.of(context);
    final theme = Theme.of(context);
    final access = _session.access;
    final bool canWrite = access?.allows(CcPerm.write) ?? false;
    final bool canDelete = access?.allows(CcPerm.deleteRename) ?? false;
    return MakerScaffold(
      navReserve: false,
      title: '文件',
      subtitle: _session.connected?.name ?? '手环',
      leading: IconButton(
        tooltip: '返回',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(AppIcons.back),
      ),
      actions: <Widget>[
        IconButton(
          tooltip: '新建文件夹',
          onPressed: _busy ? null : _mkdir,
          icon: const Icon(AppIcons.add),
        ),
        IconButton(
          tooltip: '上传文件',
          onPressed: _busy || !canWrite ? null : _upload,
          icon: const Icon(AppIcons.upload),
        ),
      ],
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(AppIcons.folder, size: 17, color: tone.muted),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                _path,
                style: theme.textTheme.bodySmall?.copyWith(color: tone.muted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            TextButton.icon(
              onPressed: _busy ? null : () => _open(_parent(_path)),
              icon: const Icon(AppIcons.upload, size: 17),
              label: const Text('上一级'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(AppIcons.refresh, size: 17),
              label: const Text('刷新'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _downloadFolder,
              icon: const Icon(AppIcons.download, size: 17),
              label: const Text('下载此目录'),
            ),
          ],
        ),
        if (_busy) ...<Widget>[
          const SizedBox(height: 6),
          LinearProgressIndicator(value: _progress),
        ],
        if (_note case final note?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(note, style: TextStyle(fontSize: 12, color: tone.muted)),
          ),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error, style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
          ),
        if (!canWrite || !canDelete)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '写权限' + (canWrite ? '已开' : '未开') + ' · 删除权限' + (canDelete ? '已开' : '未开'),
              style: TextStyle(fontSize: 11.5, color: tone.muted),
            ),
          ),
        PaperCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_entries == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text('正在读取…', style: TextStyle(fontSize: 12.5, color: tone.muted)),
                )
              else if (_entries!.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text('空目录', style: TextStyle(fontSize: 12.5, color: tone.muted)),
                )
              else
                for (final entry in _entries!)
                  _FileRow(
                    entry: entry,
                    busy: _busy,
                    tone: tone,
                    onOpen: entry.isDir ? () => _open(_join(_path, entry.name)) : null,
                    onDownload: entry.isDir || _busy ? null : () => _download(entry),
                    onRename: _busy ? null : () => _rename(entry),
                    onDelete: _busy ? null : () => _delete(entry),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '录像之类的文件通常几十 MB, 下载按块确认写入; 手环掉线会中断并保留已下载部分。',
          style: TextStyle(fontSize: 11.5, color: tone.muted),
        ),
      ],
    );
  }

  static String _join(String a, String b) => a.endsWith('/') ? a + b : a + '/' + b;

  static String _leaf(String path) {
    if (path == '/' || path.isEmpty) return 'root';
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  static String _parent(String path) {
    if (path == '/' || path.isEmpty) return '/';
    final i = path.lastIndexOf('/');
    return i <= 0 ? '/' : path.substring(0, i);
  }

  static String _bytes(int n) {
    if (n < 1024) return n.toString() + ' B';
    if (n < 1024 * 1024) return (n / 1024).toStringAsFixed(1) + ' KB';
    return (n / 1024 / 1024).toStringAsFixed(2) + ' MB';
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.entry,
    required this.busy,
    required this.tone,
    this.onOpen,
    this.onDownload,
    this.onRename,
    this.onDelete,
  });

  final CcEntry entry;
  final bool busy;
  final PageTone tone;
  final VoidCallback? onOpen;
  final VoidCallback? onDownload;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(PaperPalette.shapeSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: <Widget>[
            Icon(
              entry.isDir ? AppIcons.folder : AppIcons.file,
              size: 19,
              color: tone.muted,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.name,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    entry.isDir ? '目录' : _FilesScreenState._bytes(entry.size),
                    style: TextStyle(fontSize: 11.5, color: tone.muted),
                  ),
                ],
              ),
            ),
            if (onDownload != null)
              IconButton(
                tooltip: '下载',
                onPressed: busy ? null : onDownload,
                icon: const Icon(AppIcons.download, size: 18),
              ),
            PopupMenuButton<String>(
              enabled: !busy,
              tooltip: '更多',
              onSelected: (value) {
                if (value == 'rename') onRename?.call();
                if (value == 'delete') onDelete?.call();
              },
              itemBuilder: (context) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'rename', child: Text('重命名')),
                PopupMenuItem<String>(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
