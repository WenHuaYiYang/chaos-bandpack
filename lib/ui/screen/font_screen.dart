import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../component/app_icons.dart';
import '../component/back_chevron.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;

import '../../chaos/beauty_sync.dart';
import '../../chaos/delivery.dart' show DeliveryState, DeliveryTicket;
import '../../chaos/session.dart' show ChaosSession;
import '../../chaos/session_scope.dart';
import '../../font/charset.dart' show Charset, Kind;
import '../../icon/device_target.dart';
import '../../font/font_subset.dart' show MissingCharsError, Options;
import '../../make/font_make.dart';
import '../../make/pack_make.dart';
import '../../pack/beauty_pack.dart';
import '../../pack/pack_builders.dart' show FontPackResult, TitleText;
import '../../pack/preview_factory.dart';
import '../../project/chaos_project.dart';
import '../../project/project_store.dart';
import '../../pack/preview_png.dart';
import '../component/maker_scaffold.dart';
import '../component/segmented.dart';
import '../prefs.dart';
import '../component/paper_card.dart';
import '../theme/paper_palette.dart';
import '../theme/tone.dart';

/// 字体制作页。
///
/// 一条纪律贯穿全程: **预览用的字体就是打进包里的那份字节**。选好字库后只做一次
/// 子集化，结果同时用于预览、同步和导出，不做“预览一套、打包另一套”。
class FontScreen extends StatefulWidget {
  const FontScreen({required this.onClose, super.key});

  /// 从首页推进来的全屏页, 没有底栏, 退回只能靠标题行的箭头或系统返回键。
  final VoidCallback onClose;

  @override
  State<FontScreen> createState() => _FontScreenState();
}

class _FontScreenState extends State<FontScreen> {
  static const String _sampleFamily = 'ChaosFontSample';
  static const String _sampleText = '中文字体预览 ABCabc 0123 你好，世界';

  final TextEditingController _label = TextEditingController(text: '文楷');
  final TextEditingController _packName = TextEditingController(text: '字:文楷');
  final TextEditingController _title = TextEditingController(text: '字体投递 文楷');

  String _sourceName = '';
  Uint8List? _source;
  Precheck? _pre;

  /// 目标机型: 决定容器格式(10 Pro 四槽 / 9 Pro 分片), 也决定包名推导的输入。
  DeviceTarget _device = DeviceTarget.tenPro;

  Kind _charset = Kind.simplified;
  bool _normalize = true;
  bool _preserve = false;

  Made? _made;
  Uint8List? _previewPng;
  String? _error;
  String? _note;
  bool _busy = false;
  bool _sampleReady = false;
  (int, int)? _progress;
  int? _deliveryState;

  bool _labelTouched = false;
  bool _titleTouched = false;

  ProjectStore? _store;

  /// 设置页的默认字集/归一化只在首次进页面时套用一次, 之后以用户当次的选择为准。
  bool _defaultsApplied = false;

  /// 上一次从 store 载入的工程, 用来区分"外部换工程"和"自己写的快照"。
  FontProject? _seen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ProjectStore store = ProjectScope.of(context);
    if (identical(store, _store)) return;
    _store?.removeListener(_onProject);
    _store = store..addListener(_onProject);
    _onProject();
    // 工程已经把选项铺回来了就不要覆盖; 否则用设置页里的制作默认值。
    if (!_defaultsApplied) {
      _defaultsApplied = true;
      if (_source == null) {
        final UiPrefs prefs = UiPrefsScope.read(context);
        _charset = prefs.defaultKind;
        _normalize = prefs.defaultNormalize;
      }
    }
  }

  /// store 里的字体工程换了(导入工程/打开投递包)就把它铺回输入框。
  void _onProject() {
    final ProjectStore? store = _store;
    if (store == null) return;
    final FontProject? font = store.font;
    if (font == null || identical(font, _seen)) return;
    _seen = font;
    _loadProject(font, store.device);
  }

  void _loadProject(FontProject project, DeviceTarget device) {
    setState(() {
      _label.text = project.info.short;
      _packName.text = project.info.display;
      _title.text = project.info.title;
      _sourceName = project.sourceName;
      _source = project.source;
      _device = device;
      _charset = project.charset == 'WITH_TRADITIONAL' ? Kind.withTraditional : Kind.simplified;
      _normalize = project.normalize;
      _preserve = project.preserve;
      _pre = null;
      _made = null;
      _previewPng = null;
      _sampleReady = false;
      _error = null;
      _note = '已载入工程里的字体: ' + project.sourceName;
      // 工程里的名字是用户定的, 之后选文件不该再被文件名覆盖。
      _labelTouched = true;
      _titleTouched = true;
    });
    _precheck(project.source);
  }

  Future<void> _precheck(Uint8List src) async {
    try {
      final Precheck pre = await Isolate.run(() => FontMake.precheck(src));
      if (mounted) setState(() => _pre = pre);
    } catch (_) {
      // 预检只影响提示, 失败不挡路(真正的失败会在生成时报出来)。
    }
  }

  /// 把当前编辑态写成工程快照。只记录源字体与选项, 不记录产物 —— 产物可以重算。
  void _syncProject() {
    final Uint8List? src = _source;
    final ProjectStore? store = _store;
    if (src == null || store == null) return;
    final FontProject project = FontProject(
      info: PackInfo(short: _labelText, display: _packText, title: _titleText),
      sourceName: _sourceName,
      source: src,
      charset: _charset == Kind.withTraditional ? 'WITH_TRADITIONAL' : 'SIMPLIFIED',
      normalize: _normalize,
      preserve: _preserve,
    );
    _seen = project;
    store.setDevice(_device);
    store.setFont(project);
  }

  @override
  void dispose() {
    _store?.removeListener(_onProject);
    _label.dispose();
    _packName.dispose();
    _title.dispose();
    super.dispose();
  }

  String get _labelText => _label.text.trim();
  String get _titleText => _title.text.trim();
  String get _packText => _packName.text.trim();

  String? get _labelProblem {
    final String v = _labelText;
    if (v.isEmpty) return '短名不能为空';
    final int bytes = _utf8Length(v);
    if (bytes > 12) return '短名 ${bytes} 字节，上限 12（中文最多 4 个字）';
    for (final int c in v.codeUnits) {
      if (c < 0x20 || c == 0x7F) return '短名不能含控制字符';
    }
    return null;
  }

  static int _utf8Length(String s) {
    var n = 0;
    for (final int c in s.codeUnits) {
      if (c < 0x80) {
        n += 1;
      } else if (c < 0x800) {
        n += 2;
      } else if (c >= 0xD800 && c <= 0xDBFF) {
        n += 4;
      } else {
        n += 3;
      }
    }
    return n;
  }

  String? get _titleProblem => TitleText.validate(_titleText);

  bool get _canBuild => _source != null && _labelProblem == null && !_busy;

  void _updateSubsetOptions(VoidCallback change) {
    if (_busy) return;
    setState(() {
      change();
      _made = null;
      _previewPng = null;
      _sampleReady = false;
      _error = null;
      _note = null;
    });
  }

  Future<void> _pickFont() async {
    try {
      final FilePickerResult? hit = await FilePicker.platform.pickFiles(
        dialogTitle: '选择 TTF / OTF 字体',
        type: FileType.custom,
        allowedExtensions: const <String>['ttf', 'otf', 'ttc'],
        withData: true,
      );
      if (hit == null || hit.files.isEmpty) return;
      final PlatformFile f = hit.files.first;
      final Uint8List? bytes = f.bytes;
      if (bytes == null) {
        _fail('读不到文件内容: ${f.name}');
        return;
      }
      final Precheck pre = await Isolate.run(() => FontMake.precheck(bytes));
      if (!mounted) return;
      setState(() {
        _sourceName = f.name;
        _source = bytes;
        _pre = pre;
        _made = null;
        _previewPng = null;
        _sampleReady = false;
        _error = null;
        _note = null;
        if (!_labelTouched) {
          final String guess = _guessLabel(f.name);
          if (guess.isNotEmpty) {
            _label.text = guess;
            _packName.text = '字:${guess}';
            if (!_titleTouched) _title.text = '字体投递 ${guess}';
          }
        }
      });
    } catch (e) {
      _fail('读字体失败: ${e}');
    }
  }

  /// 文件名去掉扩展名后只留字母数字, 取前 4 个 —— 与 Kotlin 版选文件时的推断一致。
  static String _guessLabel(String name) {
    final int dot = name.lastIndexOf('.');
    final String base = dot <= 0 ? name : name.substring(0, dot);
    final StringBuffer out = StringBuffer();
    for (final int c in base.runes) {
      final bool alpha = (c >= 0x30 && c <= 0x39) ||
          (c >= 0x41 && c <= 0x5A) ||
          (c >= 0x61 && c <= 0x7A);
      if (alpha && out.length < 4) out.writeCharCode(c);
    }
    return out.toString();
  }

  Future<void> _build() async {
    final Uint8List? src = _source;
    if (src == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
      _made = null;
      _previewPng = null;
      _sampleReady = false;
      _progress = null;
    });
    try {
      final Kind charset = _charset;
      final bool normalize = _normalize;
      final bool preserve = _preserve;
      final Made made = await Isolate.run(
        () => FontMake.build(
          src,
          options: Options(charset: charset, normalizeMetrics: normalize),
          preserve: preserve,
        ),
      );
      final Uint8List blob = await PreviewFactory.fontBlob(_titleText);
      final Uint8List png = PreviewPng.encode(blob);
      final bool sample = await _loadSample(made.font);
      if (!mounted) return;
      setState(() {
        _made = made;
        _previewPng = png;
        _sampleReady = sample;
        _busy = false;
      });
      _syncProject();
    } on MissingCharsError catch (e) {
      _fail('缺字: ${e.readable}');
    } catch (e) {
      _fail('子集化失败: ${e}');
    }
  }

  /// 把子集化后的字节注册成字族。用的就是即将打进包的那份字节。
  Future<bool> _loadSample(Uint8List font) async {
    try {
      final FontLoader loader = FontLoader(_sampleFamily)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(font)));
      await loader.load();
      return true;
    } catch (_) {
      return false;
    }
  }

  BeautyPack _beautyPack(Made made) {
    final String? problem = _labelProblem;
    if (problem != null) throw FormatException(problem);
    return BeautyPack(
      kind: BeautyKind.font,
      device: _device,
      name: _labelText,
      files: <String, Uint8List>{'font.ttf': made.font},
    );
  }

  String? _syncUnavailableReason(ChaosSession session) {
    if (_device == DeviceTarget.ninePro) {
      return '9 Pro 固件尚未验证直连同步，请导出兼容 .bin 后用 AstroBox 安装。';
    }
    return BeautySync.unavailableReason(session, _device);
  }

  Future<void> _exportBeauty() => _runOutput('导出字体包', () async {
    final Made? made = _made;
    if (made == null) return;
    final BeautyPack pack = _beautyPack(made);
    final String? path = await BeautySync.save(pack);
    if (!mounted) return;
    _note = path == null
        ? '已取消导出。'
        : '已导出字体包“${pack.name}”（.${BeautyPack.extension}）。';
  });

  Future<void> _syncBeauty() => _runOutput('同步字体', () async {
    final Made? made = _made;
    if (made == null) return;
    final ChaosSession session = SessionScope.read(context);
    final String? reason = _syncUnavailableReason(session);
    if (reason != null) throw StateError(reason);
    final BeautyPack pack = _beautyPack(made);
    setState(() => _progress = (0, 0));
    final DeliveryTicket ticket = await BeautySync.send(
      session,
      pack,
      onState: (DeliveryTicket status) {
        if (mounted && _deliveryState != status.state) {
          setState(() => _deliveryState = status.state);
        }
      },
      onProgress: (int sent, int total) {
        if (mounted) setState(() => _progress = (sent, total));
      },
    );
    if (!mounted) return;
    final String status = DeliveryState.name(ticket.state);
    if (ticket.state == DeliveryState.done) {
      _note = '字体同步：$status';
    } else {
      _error = '字体未能同步：$status';
    }
  });

  Future<void> _exportLegacy() => _runOutput('导出兼容 .bin', () async {
    final Made? made = _made;
    if (made == null) return;
    final String? problem = _titleProblem ?? _labelProblem;
    if (problem != null) throw FormatException(problem);
    final DeviceTarget device = _device;
    final String label = _labelText;
    final FontPackResult out = await PackMake.fontPack(
      label: label,
      packName: _packText,
      title: _titleText,
      font: made.font,
      device: device,
    );
    if (!mounted) return;
    final String? path = await FilePicker.platform.saveFile(
      dialogTitle: '保存兼容字体包 (.bin)',
      fileName: 'chaos-fontpack-${device.id}-$label.bin',
      type: FileType.custom,
      allowedExtensions: const <String>['bin'],
      bytes: out.bytes,
    );
    if (path != null && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await File(path).writeAsBytes(out.bytes);
    }
    if (!mounted) return;
    _note = path == null
        ? '已取消导出。'
        : '已导出兼容 .bin，表盘 ID ${out.pkgName}。';
  });

  Future<void> _runOutput(String operation, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        final String detail = e is FormatException ? e.message : BeautySync.readableError(e);
        _error = '$operation失败：$detail';
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _deliveryState = null;
        });
      }
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final PageTone tone = ToneScope.of(context);
    final ThemeData theme = Theme.of(context);
    final String? syncReason = _syncUnavailableReason(SessionScope.of(context));
    return MakerScaffold(
      title: '字体制作',
      subtitle: '选字库、字集档，预览后同步或导出',
      leading: BackChevron(onTap: widget.onClose),
      navReserve: false,
      bottomBar: FilledButton.icon(
        onPressed: _canBuild ? _build : null,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(AppIcons.build, size: 20),
        label: Text(_busy ? '处理中…' : (_made == null ? '生成字体' : '重新生成')),
      ),
      children: <Widget>[
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SettingRow(
                title: _source == null ? '选择 TTF / OTF' : _sourceName,
                subtitle: _source == null
                    ? '仅支持 TrueType 字体'
                    : '${_source!.length ~/ 1024} KB  ·  ${_pre?.glyphs ?? '?'} 个字形',
                leading: const Icon(AppIcons.pickFont, size: 22),
                trailing: const Icon(AppIcons.chevronRight, size: 20),
                onTap: _busy ? null : _pickFont,
              ),
              if (_pre != null) ...<Widget>[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _Chip(label: 'cmap ${_pre!.cmapChars}', ok: true),
                    if (_pre!.ok)
                      const _Chip(label: 'GB2312 齐', ok: true)
                    else
                      _Chip(label: '缺 ${_pre!.missingRequired} 字', ok: false),
                    if (_pre!.traditional > 0)
                      _Chip(label: '繁体 ${_pre!.traditional}', ok: true),
                  ],
                ),
                if (!_pre!.ok) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    '这套字库缺必需字（GB2312 + ASCII + CJK 标点）: ${_pre!.sampleText}…',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ],
          ),
        ),
        PaperCard(
          child: Column(
            children: <Widget>[
              Segmented<DeviceTarget>(
                value: _device,
                items: const <DeviceTarget, String>{
                  DeviceTarget.tenPro: '10 Pro',
                  DeviceTarget.ninePro: '9 Pro',
                },
                onChanged: (DeviceTarget v) {
                  if (!_busy) setState(() => _device = v);
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _device == DeviceTarget.ninePro
                      ? '${_device.label} · 兼容导出 .bin：64 KB 分片，字体上限 8 MB'
                      : '${_device.label} · 固件 ${_device.firmware}',
                  style: theme.textTheme.bodySmall?.copyWith(color: tone.muted),
                ),
              ),
            ],
          ),
        ),
        const SectionLabel('命名'),
        PaperCard(
          child: Column(
            children: <Widget>[
              TextField(
                controller: _label,
                decoration: InputDecoration(
                  labelText: '短名',
                  helperText: '手环上显示的名字，最多 4 个汉字',
                  errorText: _labelProblem,
                ),
                onChanged: (_) {
                  _labelTouched = true;
                  if (!_titleTouched) _title.text = '字体投递 ${_label.text.trim()}';
                  _packName.text = '字:${_label.text.trim()}';
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _packName,
                decoration: const InputDecoration(
                  labelText: '兼容包名',
                  helperText: '兼容 .bin 在表盘列表里的名字',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                decoration: InputDecoration(
                  labelText: '兼容包标题',
                  helperText: '兼容 .bin 表盘内的标题行',
                  errorText: _titleProblem,
                  counterText: '${TitleText.width(_titleText)}/16 半角',
                ),
                onChanged: (_) {
                  _titleTouched = true;
                  setState(() {});
                },
              ),
            ],
          ),
        ),
        const SectionLabel('子集化'),
        PaperCard(
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Segmented(
                      value: _charset,
                      items: const <Kind, String>{
                        Kind.simplified: '精简',
                        Kind.withTraditional: '含繁体',
                      },
                      onChanged: (Kind v) => _updateSubsetOptions(() => _charset = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _normalize,
                onChanged: _busy ? null : (bool v) => _updateSubsetOptions(() => _normalize = v),
                title: const Text('归一化垂直度量'),
                subtitle: const Text('行高与基线对齐'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _preserve,
                onChanged: _busy ? null : (bool v) => _updateSubsetOptions(() => _preserve = v),
                title: const Text('保留原始字节'),
                subtitle: const Text('保留原始字重与行高'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '必需字集 ${Charset.required.length ~/ 1000}k；含繁体再 +${Charset.big5.length ~/ 1000}k。'
                  '只打包字集范围内的字形。',
                  style: theme.textTheme.bodySmall?.copyWith(color: tone.muted),
                ),
              ),
            ],
          ),
        ),
        if (_made != null) ...<Widget>[
          const SectionLabel('产出'),
          PaperCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(PaperPalette.shapeSm),
                      child: Image.memory(
                        _previewPng!,
                        width: 112,
                        height: 160,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('打包结果', style: theme.textTheme.titleSmall),
                          const SizedBox(height: 6),
                          _Stat('字体', '${(_made!.font.length / 1024).round()} KB'),
                          _Stat('原始',
                              '${(_made!.report.srcBytes / 1048576).toStringAsFixed(1)} MB'),
                          _Stat('字形',
                              '${_made!.report.outGlyphs} / ${_made!.report.srcGlyphs}'),
                          _Stat('cmap', '${_made!.report.cmapChars} 字'),
                          if (_made!.report.charset == Kind.withTraditional)
                            _Stat('繁体', '${_made!.report.traditional} 字'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(PaperPalette.shapeSm),
                  ),
                  child: Text(
                    _sampleText,
                    style: TextStyle(
                      fontFamily: _sampleReady ? _sampleFamily : null,
                      fontSize: 17,
                      height: 1.6,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_error != null)
          _Banner(text: _error!, color: theme.colorScheme.error, icon: AppIcons.error),
        if (_note != null)
          _Banner(text: _note!, color: tone.deep, icon: AppIcons.info),
        if (_progress case (final sent, final total))
          PaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _deliveryState == DeliveryState.awaitingConsent
                      ? '请在手环上确认安装'
                      : total > 0 && sent == total
                          ? '正在等待手环确认安装结果'
                          : '正在同步字体',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: total == 0 ? null : sent / total, minHeight: 6),
              ],
            ),
          ),
        if (_made != null)
          PaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _busy || syncReason != null ? null : _syncBeauty,
                  icon: const Icon(AppIcons.linked, size: 20),
                  label: const Text('同步字体到手环'),
                ),
                if (syncReason != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(syncReason, style: theme.textTheme.bodySmall?.copyWith(color: tone.muted)),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _exportBeauty,
                  icon: const Icon(AppIcons.saveProject, size: 20),
                  label: const Text('导出字体包 .${BeautyPack.extension}'),
                ),
                TextButton(
                  onPressed: _busy ? null : _exportLegacy,
                  child: const Text('兼容导出 .bin'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color c = ok ? theme.colorScheme.primary : theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: theme.textTheme.labelMedium?.copyWith(color: c)),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: ToneScope.of(context).muted),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(PaperPalette.shapeMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
