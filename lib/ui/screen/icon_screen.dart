import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../component/animated_icon_dialog.dart';
import '../component/app_icons.dart';
import '../component/back_chevron.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../chaos/beauty_sync.dart';
import '../../chaos/delivery.dart' show DeliveryState, DeliveryTicket;
import '../../chaos/session.dart' show ChaosSession;
import '../../chaos/session_scope.dart';
import '../../icon/animated_icons.dart' as anim;
import '../../icon/device_target.dart';
import '../../icon/dgf1.dart';
import '../../icon/icon_input_names.dart';
import '../../icon/icon_spec.dart';
import '../../make/icon_import.dart';
import '../../make/icon_make.dart';
import '../../make/pack_make.dart';
import '../../pack/beauty_pack.dart';
import '../../pack/cipk.dart';
import '../../pack/icon_png.dart';
import '../../pack/pack_builders.dart' show IconPackResult, TitleText;
import '../../pack/preview_factory.dart';
import '../../pack/preview_png.dart';
import '../../project/chaos_project.dart';
import '../../project/project_store.dart';
import '../component/maker_scaffold.dart';
import '../component/segmented.dart';
import '../component/paper_card.dart';
import '../theme/paper_palette.dart';
import '../theme/tone.dart';

/// 图标制作页。
///
/// 一条纪律: 工程里存**源素材**(任意尺寸的图 / 动图), 只有导出时才按目标槽位换算。
/// 这样同一份工程切到 9 Pro 还能重新导出, 不必重新拖一遍图。
class IconScreen extends StatefulWidget {
  const IconScreen({required this.onClose, super.key});

  /// 从首页推进来的全屏页, 没有底栏, 退回只能靠标题行的箭头或系统返回键。
  final VoidCallback onClose;

  @override
  State<IconScreen> createState() => _IconScreenState();
}

class _IconScreenState extends State<IconScreen> {
  final TextEditingController _short = TextEditingController(text: 'chaos');
  final TextEditingController _packName = TextEditingController(text: '图标:chaos');
  final TextEditingController _title = TextEditingController(text: '图标投递 chaos');

  DeviceTarget _device = DeviceTarget.tenPro;
  IconSpecGroup _group = IconSpecGroup.desktop;

  /// stem -> 已转好的槽位 BIN(进包的就是这份字节)。
  final Map<String, Uint8List> _images = <String, Uint8List>{};
  /// stem -> DGF1 动画(仅 10 Pro 桌面)。
  final Map<String, Uint8List> _animations = <String, Uint8List>{};
  /// stem -> 缩略图 PNG。
  final Map<String, Uint8List> _thumbs = <String, Uint8List>{};
  final Map<String, int> _frames = <String, int>{};

  bool _busy = false;
  String? _error;
  String? _note;
  Uint8List? _previewPng;
  String? _previewPkg;
  int _previewIcons = 0;
  (int, int)? _progress;
  int? _deliveryState;

  ProjectStore? _store;

  /// 上一次从 store 载入的工程, 用来区分"外部换工程"和"自己写的快照"。
  IconProject? _seen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ProjectStore store = ProjectScope.of(context);
    if (identical(store, _store)) return;
    _store?.removeListener(_onProject);
    _store = store..addListener(_onProject);
    _onProject();
  }

  /// store 里的图标工程换了(导入工程/打开投递包)就把它铺回网格。
  void _onProject() {
    final ProjectStore? store = _store;
    if (store == null) return;
    final IconProject? icons = store.icons;
    if (icons == null || identical(icons, _seen)) return;
    _seen = icons;
    setState(() {
      _short.text = icons.info.short;
      _packName.text = icons.info.display;
      _title.text = icons.info.title;
      _device = store.device;
      _images
        ..clear()
        ..addAll(icons.images);
      _animations.clear();
      _frames.clear();
      _thumbs.clear();
      for (final MapEntry<String, Uint8List> e in icons.images.entries) {
        if (anim.AnimatedIcons.isAnimationKey(e.key)) {
          _animations[anim.AnimatedIcons.base(e.key)] = e.value;
        }
      }
      // 动画键在 images 里只作载体, 展示仍按静态槽位走。
      _images.removeWhere((String k, Uint8List _) => anim.AnimatedIcons.isAnimationKey(k));
      _previewPng = null;
      _error = null;
      _note = '已载入工程里的 ' + _images.length.toString() + ' 个图标';
    });
    _thumbsUp();
  }

  /// 载入的图只有 BIN, 缩略图得现解。
  Future<void> _thumbsUp() async {
    for (final MapEntry<String, Uint8List> e in _images.entries.toList()) {
      final Uint8List? png = IconPng.encode(e.value);
      if (png == null || !mounted) continue;
      setState(() => _thumbs[e.key] = png);
    }
  }

  /// 把当前编辑态写成工程快照。
  void _syncProject() {
    final ProjectStore? store = _store;
    if (store == null) return;
    final Map<String, Uint8List> images = <String, Uint8List>{
      for (final MapEntry<String, Uint8List> e in _images.entries) e.key: e.value,
      for (final MapEntry<String, Uint8List> e in _animations.entries)
        anim.AnimatedIcons.key(e.key): e.value,
    };
    final IconProject project = IconProject(
      info: PackInfo(short: _shortText, display: _packText, title: _titleText),
      images: images,
    );
    _seen = project;
    store.setDevice(_device);
    store.setIcons(project);
  }

  @override
  void dispose() {
    _store?.removeListener(_onProject);
    _short.dispose();
    _packName.dispose();
    _title.dispose();
    super.dispose();
  }

  String get _shortText => _short.text.trim();
  String get _titleText => _title.text.trim();
  String get _packText => _packName.text.trim();

  /// 短名规则按机型分叉: 10 Pro 进 p67 容器, 只认 ASCII 字母数字下划线连字符;
  /// 9 Pro 是侧载表盘, 可以带空格以外的可打印 ASCII。
  String? get _shortProblem {
    final String v = _shortText;
    if (_device == DeviceTarget.tenPro) {
      if (!RegExp(r'^[A-Za-z0-9_-]{1,12}$').hasMatch(v)) {
        return '只允许 A-Z a-z 0-9 _ -, 1..12 字节';
      }
      return null;
    }
    final List<int> bytes = utf8.encode(v);
    if (bytes.isEmpty || bytes.length > 12) return '须为 1..12 个字节';
    for (final int c in bytes) {
      if (c <= 32 || c == 127) return '不能含空格或控制字符';
    }
    return null;
  }

  String? get _titleProblem => TitleText.validate(_titleText);

  List<IconSpecSlot> get _slots => IconSpec.slotsOf(_group, _device);

  int get _filled => _images.length;

  /// 桌面组的动画数(只有 10 Pro 会有)。
  int get _animatedCount => _animations.length;

  /// 分组说明随机型与分组变: 桌面在 10 Pro 能吃 GIF, 在 9 Pro 只能静态图,
  /// 系统资源那组反过来只认原生 BIN。
  String get _groupHint {
    if (_group == IconSpecGroup.native) {
      return '只收原生 BIN, 尺寸随资源走, 文件名要对上设备映射。';
    }
    if (_group == IconSpecGroup.desktop) {
      return _device == DeviceTarget.tenPro
          ? '新图 96 × 96; GIF 能放 1–256 帧; 老的原生 BIN 保持原尺寸。'
          : '100 × 100, 9 Pro 桌面素材。';
    }
    return _group == IconSpecGroup.control
        ? '静态图, 透明边保留; 勿扰和免打扰共用一张。'
        : '静态图, 透明边保留。';
  }

  /// 短名输入按机型过滤: 与其事后报错, 不如根本敲不进去。
  void _onShortChanged(String raw) {
    final String filtered = String.fromCharCodes(
      raw.runes.where(
        (int c) => _device == DeviceTarget.tenPro
            ? (c >= 0x30 && c <= 0x39) ||
                (c >= 0x41 && c <= 0x5A) ||
                (c >= 0x61 && c <= 0x7A) ||
                c == 0x5F ||
                c == 0x2D
            : c >= 0x21 && c <= 0x7E,
      ),
    );
    final String clipped = filtered.length > 12 ? filtered.substring(0, 12) : filtered;
    if (clipped != raw) {
      _short.value = TextEditingValue(
        text: clipped,
        selection: TextSelection.collapsed(offset: clipped.length),
      );
    }
    _packName.text = '图标:' + clipped;
    if (clipped.isNotEmpty) _title.text = '图标投递 ' + clipped;
    setState(() {});
  }

  Future<void> _pickSlot(IconSpecSlot slot) async {
    try {
      final FilePickerResult? hit = await FilePicker.platform.pickFiles(
        dialogTitle: '选择 ${slot.label} 的图标',
        type: FileType.custom,
        allowedExtensions: const <String>['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif', 'bin'],
        withData: true,
      );
      if (hit == null || hit.files.isEmpty) return;
      final PlatformFile f = hit.files.first;
      final Uint8List? bytes = f.bytes;
      if (bytes == null) {
        _fail('读不到文件内容: ${f.name}');
        return;
      }
      await _apply(slot, bytes, f.name);
    } catch (e) {
      _fail('处理失败: ${e}');
    }
  }

  /// 批量导入: 按文件名认出用途, 一个文件都不用点第二次。
  ///
  /// 一个槽位算一组, **整组要么全都进去, 要么全都不动**。GIF 配 _anim.bin 这类
  /// 成对的素材, 只写进去一半会让工程里出现一张没有动画可播的封面, 后面排查
  /// 很费劲; 所以失败时保留这个槽位原来的选择。
  Future<void> _importMany() async {
    try {
      final FilePickerResult? hit = await FilePicker.platform.pickFiles(
        dialogTitle: '选择图标或动图(文件名要能对上槽位)',
        type: FileType.custom,
        allowedExtensions: const <String>[
          'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif', 'bin',
        ],
        allowMultiple: true,
        withData: true,
      );
      if (hit == null || hit.files.isEmpty) return;
      setState(() {
        _busy = true;
        _error = null;
        _note = null;
      });
      final List<PlatformFile> files = hit.files;
      final IconInputPlan plan = IconInputNames.plan(
        <String>[for (final PlatformFile f in files) f.name],
        _device,
      );
      Map<String, Uint8List> next = <String, Uint8List>{
        ..._images,
        for (final MapEntry<String, Uint8List> e in _animations.entries)
          anim.AnimatedIcons.key(e.key): e.value,
      };
      var done = 0;
      final List<String> problems = <String>[];
      for (final IconInputGroup g in plan.groups) {
        final IconSpecSlot? slot = IconSpec.stemOf(g.stem, _device);
        final String label = slot?.label ?? g.stem;
        if (g.error != null) {
          problems.add(label + '：' + g.error!);
          continue;
        }
        try {
          final (Map<String, Uint8List> made, int _) =
              await _convertGroup(g, files);
          next = <String, Uint8List>{
            ...anim.AnimatedIcons.withoutSlot(next, g.stem),
            ...made,
          };
          done++;
        } on Object catch (e) {
          final String why = e is IconMakeError
              ? e.message
              : e is anim.AnimatedIconsError
                  ? e.message
                  : e is Dgf1Error
                      ? e.message
                      : '素材不合适';
          problems.add(label + '：' + why);
        }
      }
      if (!mounted) return;
      if (done > 0) {
        setState(() {
          _images
            ..clear()
            ..addAll(<String, Uint8List>{
              for (final MapEntry<String, Uint8List> e in next.entries)
                if (!anim.AnimatedIcons.isAnimationKey(e.key)) e.key: e.value,
            });
          _animations.clear();
          _frames.clear();
          _thumbs.clear();
          for (final MapEntry<String, Uint8List> e in next.entries) {
            if (!anim.AnimatedIcons.isAnimationKey(e.key)) continue;
            final String stem = anim.AnimatedIcons.base(e.key);
            _animations[stem] = e.value;
            _frames[stem] = Dgf1.parse(e.value).frames.length;
          }
          _previewPng = null;
        });
        _syncProject();
        _thumbsUp();
      }
      setState(() {
        _busy = false;
        if (plan.unmatched > 0) {
          problems.insert(0, '有 ' + plan.unmatched.toString() + ' 个文件名没对上槽位, 已跳过');
        }
        _note = done == 0 ? null : '已导入 ' + done.toString() + ' 个图标';
        _error = problems.isEmpty ? null : problems.join('\n');
      });
    } catch (e) {
      _fail('导入失败: ' + e.toString());
    }
  }

  /// 整组换算丢进 isolate: 解码几张图能占几十毫秒, 放在主线程要掉帧。
  Future<(Map<String, Uint8List>, int)> _convertGroup(
    IconInputGroup group,
    List<PlatformFile> files,
  ) {
    final List<Uint8List?> inputs = <Uint8List?>[
      for (final PlatformFile f in files) f.bytes,
    ];
    final List<String> names = <String>[for (final PlatformFile f in files) f.name];
    final DeviceTarget device = _device;
    final Uint8List? existing = _images[group.stem];
    return Isolate.run(
      () => IconImport.group(
        group: group,
        inputs: inputs,
        names: names,
        device: device,
        existingCover: existing,
      ),
    );
  }

  /// 单张进槽: 解码 -> 按槽位换算 -> 立刻出缩略图。
  Future<void> _apply(IconSpecSlot slot, Uint8List bytes, String name) async {
    final Uint8List? cover = _images[slot.stem];
    final DeviceTarget device = _device;
    final IconSpecSlot forRun = slot;
    final IconMade made = await Isolate.run(
      () => IconMake.convert(
        bytes: bytes,
        name: name,
        slot: forRun,
        existingCover: cover,
      ),
    );
    final Uint8List? png = IconPng.encode(made.bytes);
    if (!mounted) return;
    setState(() {
      _images[slot.stem] = made.bytes;
      if (made.animation != null) {
        _animations[slot.stem] = made.animation!;
        _frames[slot.stem] = made.frames;
      } else {
        _animations.remove(slot.stem);
        _frames.remove(slot.stem);
      }
      if (png != null) _thumbs[slot.stem] = png;
      _device = device;
      _previewPng = null;
      _note = made.animated
          ? '${slot.label}: ${made.frames} 帧，配套新版 Chaos 才能播放动画；旧版仅使用封面'
          : null;
    });
    _syncProject();
  }

  void _clearSlot(IconSpecSlot slot) {
    setState(() {
      _images.remove(slot.stem);
      _animations.remove(slot.stem);
      _thumbs.remove(slot.stem);
      _frames.remove(slot.stem);
      _previewPng = null;
    });
    _syncProject();
  }

  Future<void> _build() async {
    if (_images.isEmpty) {
      _fail('至少放一张图标');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
      _previewPng = null;
      _previewPkg = null;
    });
    try {
      final List<CipkIcon> icons = await _makeIconFiles(_device);
      final Uint8List blob = await PreviewFactory.iconBlob(_titleText, _shortText);
      final Uint8List png = PreviewPng.encode(blob);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _previewPng = png;
        _previewIcons = icons.length;
      });
    } on FormatException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('图标预览失败：$e');
    }
  }

  Future<List<CipkIcon>> _makeIconFiles(DeviceTarget device) async {
    final List<CipkIcon> icons = await PackMake.iconFiles(
      picked: Map<String, Uint8List>.of(_images),
      animations: Map<String, Uint8List>.of(_animations),
      device: device,
    );
    if (icons.isEmpty) {
      throw FormatException('${device.label} 没有可用的图标，请为该机型添加图标。');
    }
    return icons;
  }

  Future<BeautyPack> _beautyPack() async {
    final String? problem = _shortProblem;
    if (problem != null) throw FormatException(problem);
    final DeviceTarget device = _device;
    final String short = _shortText;
    final List<CipkIcon> icons = await _makeIconFiles(device);
    return BeautyPack(
      kind: BeautyKind.icon,
      device: device,
      name: short,
      files: <String, Uint8List>{
        for (final CipkIcon icon in icons) icon.fileName: icon.data,
      },
    );
  }

  String? _syncUnavailableReason(ChaosSession session) {
    if (_device == DeviceTarget.ninePro) {
      return '9 Pro 固件尚未验证直连同步，请导出兼容 .bin 后用 AstroBox 安装。';
    }
    return BeautySync.unavailableReason(session, _device);
  }

  Future<void> _exportBeauty() => _runOutput('导出图标包', () async {
    final BeautyPack pack = await _beautyPack();
    if (!mounted) return;
    final String? path = await BeautySync.save(pack);
    if (!mounted) return;
    _note = path == null
        ? '已取消导出。'
        : '已导出图标包“${pack.name}”（.${BeautyPack.extension}）。';
  });

  Future<void> _syncBeauty() => _runOutput('同步图标', () async {
    final ChaosSession session = SessionScope.read(context);
    final String? reason = _syncUnavailableReason(session);
    if (reason != null) throw StateError(reason);
    setState(() => _progress = (0, 0));
    final BeautyPack pack = await _beautyPack();
    if (!mounted) return;
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
      _note = '图标同步：$status';
    } else {
      _error = '图标未能同步：$status';
    }
  });

  Future<void> _exportLegacy() => _runOutput('导出兼容 .bin', () async {
    final String? problem = _titleProblem;
    if (problem != null) throw FormatException(problem);
    final DeviceTarget device = _device;
    final String short = _shortText;
    final String display = _packText;
    final String title = _titleText;
    final List<CipkIcon> icons = await _makeIconFiles(device);
    if (!mounted) return;
    final IconPackResult out = await PackMake.iconPack(
      short: short,
      packName: display,
      title: title,
      files: icons,
      device: device,
    );
    if (!mounted) return;
    final String? path = await FilePicker.platform.saveFile(
      dialogTitle: '保存兼容图标包 (.bin)',
      fileName: 'chaos-iconpack-${device.id}-$short.bin',
      type: FileType.custom,
      allowedExtensions: const <String>['bin'],
      bytes: out.bytes,
    );
    if (path != null && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await File(path).writeAsBytes(out.bytes);
    }
    if (!mounted) return;
    _previewPkg = path == null ? null : out.pkgName;
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
      title: '图标制作',
      subtitle: '选机型、填槽位，预览后同步或导出',
      leading: BackChevron(onTap: widget.onClose),
      navReserve: false,
      actions: <Widget>[
        IconButton(
          tooltip: '批量导入',
          onPressed: _busy ? null : _importMany,
          icon: const Icon(AppIcons.pickImage),
        ),
      ],
      bottomBar: FilledButton.icon(
        onPressed: _busy || _images.isEmpty ? null : _build,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(AppIcons.build, size: 20),
        label: Text(_busy ? '处理中…' : '生成图标（${_filled} 个）'),
      ),
      children: <Widget>[
        PaperCard(
          child: Column(
            children: <Widget>[
              Segmented<DeviceTarget>(
                items: const <DeviceTarget, String>{
                  DeviceTarget.tenPro: '10 Pro',
                  DeviceTarget.ninePro: '9 Pro',
                },
                value: _device,
                onChanged: (DeviceTarget v) {
                  if (_busy || v == _device) return;
                  setState(() {
                    _device = v;
                    _group = IconSpecGroup.desktop;
                    _previewPng = null;
                    _previewPkg = null;
                    _error = null;
                    _note = null;
                  });
                  _syncProject();
                },
              ),
              const SizedBox(height: 8),
              Text(
                '${_device.label} · 固件 ${_device.firmware} · 桌面 ${IconSpec.slotsOf(IconSpecGroup.desktop, _device).length} 槽',
                style: theme.textTheme.bodySmall?.copyWith(color: tone.muted),
              ),
            ],
          ),
        ),
        const SectionLabel('命名'),
        PaperCard(
          child: Column(
            children: <Widget>[
              TextField(
                controller: _short,
                decoration: InputDecoration(
                  labelText: '短名',
                  helperText: (_device == DeviceTarget.tenPro
                          ? '字母、数字、_、- · '
                          : '只收 ASCII · ') +
                      _shortText.length.toString() +
                      '/12',
                  errorText: _shortProblem,
                ),
                onChanged: _onShortChanged,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _packName,
                decoration: const InputDecoration(labelText: '兼容包名', helperText: '兼容 .bin 在表盘列表里的名字'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                decoration: InputDecoration(
                  labelText: '包标题',
                  helperText: '兼容 .bin 的表盘标题，上限 16 个半角',
                  errorText: _titleProblem,
                  counterText: '${TitleText.width(_titleText)}/16 半角',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        SectionLabel(
          '槽位',
          trailing: Text(
            '${_filled} / ${IconSpec.all(_device).length}',
            style: theme.textTheme.bodySmall?.copyWith(color: tone.muted),
          ),
        ),
        PaperCard(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
          child: Column(
            children: <Widget>[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    for (final IconSpecGroup g in const <IconSpecGroup>[
                      IconSpecGroup.desktop,
                      IconSpecGroup.control,
                      IconSpecGroup.settings,
                      IconSpecGroup.native,
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _Pill(
                          label: '${g.label} ${IconSpec.slotsOf(g, _device).length}',
                          active: g == _group,
                          onTap: () => setState(() => _group = g),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _groupHint,
                  style: theme.textTheme.bodySmall?.copyWith(color: tone.muted),
                ),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 84,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.78,
                ),
                itemCount: _slots.length,
                itemBuilder: (BuildContext ctx, int i) {
                  final IconSpecSlot slot = _slots[i];
                  final Uint8List? png = _thumbs[slot.stem];
                  final Uint8List? animation = _animations[slot.stem];
                  return _SlotCell(
                    label: slot.label,
                    png: png,
                    animated: animation != null,
                    frames: _frames[slot.stem] ?? 0,
                    onTap: _busy ? null : () => _pickSlot(slot),
                    onClear: _busy || png == null ? null : () => _clearSlot(slot),
                    onPreview: animation == null
                        ? null
                        : () => showAnimatedIconDialog(context, bytes: animation),
                  );
                },
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '点击选取，长按清空。空槽位不打包。',
                  style: theme.textTheme.bodySmall?.copyWith(color: tone.muted),
                ),
              ),
            ],
          ),
        ),
        if (_previewPng != null) ...<Widget>[
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
                          Text('图标预览', style: theme.textTheme.titleSmall),
                          const SizedBox(height: 6),
                          _Stat('图标', '${_previewIcons} 个'),
                          if (_device == DeviceTarget.tenPro)
                            _Stat('动态', '${_animatedCount} 个'),
                          _Stat('机型', _device.label),
                          if (_previewPkg != null) _Stat('ID', _previewPkg!),
                        ],
                      ),
                    ),
                  ],
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
                          : '正在同步图标',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: total == 0 ? null : sent / total, minHeight: 6),
              ],
            ),
          ),
        if (_previewPng != null)
          PaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _busy || syncReason != null ? null : _syncBeauty,
                  icon: const Icon(AppIcons.linked, size: 20),
                  label: const Text('同步图标到手环'),
                ),
                if (syncReason != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(syncReason, style: theme.textTheme.bodySmall?.copyWith(color: tone.muted)),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _exportBeauty,
                  icon: const Icon(AppIcons.saveProject, size: 20),
                  label: const Text('导出图标包 .${BeautyPack.extension}'),
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

class _SlotCell extends StatelessWidget {
  const _SlotCell({
    required this.label,
    required this.png,
    required this.animated,
    required this.frames,
    this.onTap,
    this.onClear,
    this.onPreview,
  });

  final String label;
  final Uint8List? png;
  final bool animated;
  final int frames;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  /// 有动画时给一个单独的播放角标: 点格子是换图, 长按是清空, 看动画得是第三个
  /// 动作, 所以塞在格子里做一枚能点的小圆章。
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PageTone tone = ToneScope.of(context);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onClear,
      child: Column(
        children: <Widget>[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              decoration: BoxDecoration(
                color: png == null ? theme.colorScheme.surfaceContainerHigh : null,
                borderRadius: BorderRadius.circular(PaperPalette.shapeMd),
                border: Border.all(
                  color: png == null ? Colors.transparent : theme.colorScheme.primary,
                  width: 1.4,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (png != null)
                    Image.memory(png!, fit: BoxFit.cover, gaplessPlayback: true)
                  else
                    Icon(AppIcons.add, color: tone.muted, size: 20),
                  if (animated)
                    Positioned(
                      left: 3,
                      right: 3,
                      bottom: 3,
                      child: GestureDetector(
                        onTap: onPreview,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(
                                AppIcons.play,
                                size: 10,
                                color: theme.colorScheme.onPrimary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${frames}f',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onPrimary,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: tone.muted),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: active ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
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
            width: 40,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: ToneScope.of(context).muted),
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
            child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
