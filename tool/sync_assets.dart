// 把打包用的素材从 Chaos-Module 检出同步到 assets/pack/。
//
// 与 Kotlin 版 build.gradle.kts 的 syncPackAssets 同口径: App 仓库里不放任何设备侧
// 二进制, 构建前用这个脚本拷进来。仓库默认找 ../Chaos-Module, 也可以用
//   CHAOS_REPO 环境变量 或 dart run tool/sync_assets.dart <仓库路径>
// 覆盖。
//
// 每个素材列了一串候选路径, 按顺序取第一个存在的。chaos_sup.ko 优先取最新的 CI
// 产物 (dist/<目标>/build-<run>/chaos_sup-<目标>/chaos_sup.ko), 找不到才回退到
// dist/chaos_sup.ko —— 本地 dist/ 经常是旧的。
//
// 缺素材时只警告, 但退出码非 0, 打包时会明确报错。
import 'dart:io';

/// 素材名 -> 候选相对路径(按优先级)。
const Map<String, List<String>> _sources = <String, List<String>>{
  'chaos_sup.ko': <String>[
    'dist/chaos_sup.ko',
  ],
  'chaos_icon.bin': <String>[
    'chaos_icon.bin',
    'dist/assets/chaos_icon.bin',
  ],
  'font_pack.lua': <String>[
    'installer/font_pack.lua',
  ],
  'icon_pack.lua': <String>[
    'installer/icon_pack.lua',
  ],
};

/// 在 dist/<目标>/build-<run>/ 下找最新的 chaos_sup.ko(按目录名里的 run 号排序)。
File? _latestBuildKo(Directory repo) {
  final Directory dist = Directory('${repo.path}/dist');
  if (!dist.existsSync()) return null;
  final List<File> candidates = <File>[];
  for (final FileSystemEntity target in dist.listSync()) {
    if (target is! Directory) continue;
    for (final FileSystemEntity build in target.listSync()) {
      if (build is! Directory) continue;
      final String name = build.uri.pathSegments
          .where((String s) => s.isNotEmpty)
          .last;
      if (!name.startsWith('build-')) continue;
      for (final FileSystemEntity inner in build.listSync()) {
        if (inner is! Directory) continue;
        final String leaf = inner.uri.pathSegments
            .where((String s) => s.isNotEmpty)
            .last;
        if (!leaf.startsWith('chaos_sup-')) continue;
        final File ko = File('${inner.path}/chaos_sup.ko');
        if (ko.existsSync()) candidates.add(ko);
      }
    }
  }
  if (candidates.isEmpty) return null;
  // 目录名形如 build-44737109053, 数字大的更新。
  int run(File f) {
    final Match? m = RegExp(r'build-(\d+)').firstMatch(f.path);
    return m == null ? 0 : int.parse(m.group(1)!);
  }

  candidates.sort((File a, File b) => run(a).compareTo(run(b)));
  return candidates.last;
}

void main(List<String> args) {
  final Directory here = File.fromUri(Platform.script).parent.parent;
  final Directory out = Directory('${here.path}/assets/pack');

  final String? explicit =
      args.isNotEmpty ? args.first : Platform.environment['CHAOS_REPO'];
  final Directory repo = Directory(explicit ?? '${here.parent.path}/Chaos-Module');

  stdout.writeln('素材来源: ${repo.path}');
  if (!repo.existsSync()) {
    stderr.writeln('找不到 Chaos-Module 检出: ${repo.path}');
    stderr.writeln('可以用 CHAOS_REPO 环境变量指定路径。');
    exitCode = 2;
    return;
  }

  out.createSync(recursive: true);
  int copied = 0;
  for (final MapEntry<String, List<String>> e in _sources.entries) {
    File? src;
    String label = '';
    for (final String rel in e.value) {
      final File f = File('${repo.path}/$rel');
      if (f.existsSync()) {
        src = f;
        label = rel;
        break;
      }
    }
    src ??= e.key == 'chaos_sup.ko' ? _latestBuildKo(repo) : null;
    if (src == null) {
      stderr.writeln('  缺少 ${e.value.first} —— 跳过 ${e.key}');
      continue;
    }
    if (label.isEmpty) label = src.path.substring(repo.path.length + 1);
    final File dst = File('${out.path}/${e.key}');
    dst.writeAsBytesSync(src.readAsBytesSync());
    copied++;
    stdout.writeln(
        '  ${e.key.padRight(16)} <- $label  (${dst.lengthSync()} B)');
  }
  stdout.writeln('同步完成: $copied/${_sources.length}');
  if (copied != _sources.length) exitCode = 1;
}
