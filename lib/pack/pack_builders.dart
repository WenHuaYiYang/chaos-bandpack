import 'dart:convert';
import 'dart:typed_data';

import 'cipk.dart';
import 'shell_builder.dart';
import 'shell_writer.dart';

/// 打包素材: 一次构建要用的四件东西(前两件是二进制, 后两件是 Lua 模板)。
///
/// App 本身**不放**任何设备侧二进制 —— 素材在构建期从 Chaos-Module 检出同步
/// (见 tools/sync_pack_assets.dart), 因此这个类只负责持有, 不负责查找。
class PackAssets {
  const PackAssets({
    required this.ko,
    required this.iconBin,
    required this.fontLua,
    required this.iconLua,
  });

  /// chaos_sup.ko
  final Uint8List ko;

  /// chaos_icon.bin
  final Uint8List iconBin;

  /// 字体投递 Lua 模板(含 __FONT_NAME__ / __PACK_LABEL__ / __PACK_TITLE__)
  final String fontLua;

  /// 图标投递 Lua 模板(含 __PACK_NAME__ / __PACK_TITLE__)
  final String iconLua;
}

/// 表盘标题的宽度口径。
///
/// 手环上那行标题是 40 号字、整屏居中(屏宽 390px 上下), 实测“字体投递 花朝粗”
/// (7 个汉字 + 1 个空格 = 16 半角)正好占满一行而不折行/不截断 —— 上限由此而来。
abstract final class TitleText {
  /// 一行能放的半角字符数(全角算 2)
  static const int maxHalf = 16;

  /// 标题宽度(半角为单位)
  static int width(String s) {
    var w = 0;
    for (final cp in s.runes) {
      w += _isWide(cp) ? 2 : 1;
    }
    return w;
  }

  /// 超宽返回提示文案, 合法返回 null
  static String? validate(String s) {
    final t = s.trim();
    if (t.isEmpty) return '标题不能为空';
    final w = width(t);
    if (w > maxHalf) {
      return '标题太宽: 当前 ' + w.toString() + ' 个半角, 手环上最多 ' +
          maxHalf.toString() + ' 个半角(一个汉字算 2 个), 超出的部分会折行或被截断';
    }
    return null;
  }

  static bool _isWide(int cp) => switch (cp) {
        >= 0x1100 && <= 0x115F => true, // 谚文字母
        >= 0x2E80 && <= 0x303E => true, // CJK 部首/标点
        >= 0x3041 && <= 0x33FF => true, // 假名/注音/CJK 兼容
        >= 0x3400 && <= 0x4DBF => true, // CJK 扩展 A
        >= 0x4E00 && <= 0x9FFF => true, // CJK 统一汉字
        >= 0xA000 && <= 0xA4CF => true, // 彝文
        >= 0xAC00 && <= 0xD7A3 => true, // 谚文音节
        >= 0xF900 && <= 0xFAFF => true, // CJK 兼容汉字
        >= 0xFE10 && <= 0xFE19 => true, // 竖排标点
        >= 0xFE30 && <= 0xFE6F => true, // CJK 兼容形式
        >= 0xFF00 && <= 0xFF60 => true, // 全角形式
        >= 0xFFE0 && <= 0xFFE6 => true, // 全角符号
        _ => false,
      };
}

/// 字体包: 四个槽位的旧容器(设备侧 installer/font_pack.lua 按这个顺序找文件)。
abstract final class FontPackBuilder {
  static const int labelBytes = 12;
  static const String phName = '__FONT_NAME__';
  static const String phLabel = '__PACK_LABEL__';
  static const String phTitle = '__PACK_TITLE__';

  static FontPackResult build({
    required PackAssets assets,
    required FontPackInputs inputs,
    required Uint8List preview,
  }) {
    final labelUtf8 = utf8.encode(inputs.label);
    if (labelUtf8.isEmpty || labelUtf8.length > labelBytes) {
      throw PackError('字体短名要在 1..' + labelBytes.toString() + ' 字节之间: 「' + inputs.label + '」');
    }
    if (inputs.label.codeUnits.any((c) => c < 0x20)) {
      throw PackError('字体短名不能有控制字符');
    }
    // 超宽只是提醒, 不挡打包(与 PC 侧一致)。
    TitleText.validate(inputs.title);

    final lua = patchLua(assets.fontLua, {
      phName: inputs.label,
      phLabel: inputs.label,
      phTitle: inputs.title,
    });

    final entries = <ShellEntry>[
      ShellEntry('_lua/fontpack/main.lua', Uint8List.fromList(utf8.encode(lua))),
      ShellEntry('_lua/fontpack/chaos_sup.ko', assets.ko),
      ShellEntry('_lua/fontpack/chaos_icon.bin', assets.iconBin),
      ShellEntry('_lua/fontpack/font.ttf', inputs.font),
    ];
    final String pkg;
    if (inputs.pkgName != null) {
      ShellWriter.checkPkg(inputs.pkgName!);
      pkg = inputs.pkgName!;
    } else {
      pkg = ShellWriter.pkgFor(inputs.font);
    }
    final out = ShellBuilder.build(
      files: entries,
      pkgName: pkg,
      displayName: inputs.packName,
      preview: preview,
    );
    verifyBuilt(out, pkg, inputs.packName, entries);
    _checkPackedLua(out, 1, const [phName, phLabel, phTitle], inputs.label);
    return FontPackResult(out, pkg, inputs.packName);
  }

  /// 打完之后回读第 1 槽, 确认占位符一个不剩(PC 侧同一道门)。
  static void _checkPackedLua(
    Uint8List out,
    int idx,
    List<String> placeholders,
    String label,
  ) {
    final entry = ShellBuilder.parse(out).files[idx - 1];
    if (!entry.key.endsWith('main.lua')) {
      throw PackError('第 ' + idx.toString() + ' 槽不是投递 Lua: ' + entry.key);
    }
    final txt = utf8.decode(entry.value);
    for (final ph in placeholders) {
      if (txt.contains(ph)) throw PackError('投递 Lua 里还留着 ' + ph + ' 占位符');
    }
    if (!txt.contains('local FONT_NAME = "' + label + '"')) {
      throw PackError('投递 Lua 里的短名不是「' + label + '」');
    }
  }
}

class FontPackInputs {
  const FontPackInputs({
    required this.label,
    required this.packName,
    required this.title,
    required this.font,
    this.pkgName,
  });

  /// 清单短名(投递后清单里的名字, ≤ 12 字节, 可中文)
  final String label;

  /// 表盘显示名(手环表盘列表里看到的)
  final String packName;

  /// 表盘内那行标题(“字体投递 X”)
  final String title;

  /// 12 位数字包名, 传 null 时由字体内容自动推导
  final String? pkgName;

  /// 已归一化 + 子集化的字体字节(就是要写进包里的那一段)
  final Uint8List font;
}

class FontPackResult {
  const FontPackResult(this.bytes, this.pkgName, this.packName);
  final Uint8List bytes;
  final String pkgName;
  final String packName;
}

/// 图标包: 两个槽位的 p67 容器(main.lua + pack.bin)。
abstract final class IconPackBuilder {
  static const int shortBytes = 12;
  static const String phName = '__PACK_NAME__';
  static const String phTitle = '__PACK_TITLE__';
  static const String root = '_lua/xiaomi-band-10-pro/';
  static const int containerVersion = 0x00010107;
  static const int displayBytes = 60;

  static final RegExp _shortRe = RegExp(r'^[A-Za-z0-9_-]{1,12}$');

  static bool validShort(String name) => _shortRe.hasMatch(name);

  static IconPackResult build({
    required String template,
    required IconPackInputs inputs,
    required Uint8List preview,
  }) {
    final sb = ascii.encode(inputs.short);
    if (sb.isEmpty || sb.length > shortBytes) {
      throw PackError('图标包短名要在 1..' + shortBytes.toString() + ' 字节之间');
    }
    if (!validShort(inputs.short)) {
      throw PackError('图标包短名只能用 1–12 个 ASCII 字母、数字、下划线或连字符');
    }
    if (utf8.encode(inputs.packName).length > displayBytes) {
      throw PackError('p67 表盘名称超过 ' + displayBytes.toString() + ' 字节');
    }

    final files = inputs.files;
    final cipk = Cipk.build(files);
    final lua = patchLua(template, {phName: inputs.short, phTitle: inputs.title});

    final entries = <ShellEntry>[
      ShellEntry(root + 'main.lua', Uint8List.fromList(utf8.encode(lua))),
      ShellEntry(root + 'pack.bin', cipk),
    ];
    final String pkg;
    if (inputs.pkgName != null) {
      ShellWriter.checkPkg(inputs.pkgName!);
      pkg = inputs.pkgName!;
    } else {
      pkg = ShellWriter.pkgFor(cipk);
    }
    final out = ShellBuilder.build(
      files: entries,
      pkgName: pkg,
      displayName: inputs.packName,
      preview: preview,
      device: containerVersion,
    );
    verifyBuilt(out, pkg, inputs.packName, entries);

    // 把两槽读回来再核一遍, 才允许导出。
    final parsed = ShellBuilder.parse(out).files;
    if (!parsed[0].key.endsWith('main.lua')) throw PackError('第 1 槽不是投递 Lua');
    final txt = utf8.decode(parsed[0].value);
    for (final ph in const [phName, phTitle]) {
      if (txt.contains(ph)) throw PackError('投递 Lua 里还留着 ' + ph + ' 占位符');
    }
    if (!txt.contains(inputs.short)) {
      throw PackError('投递 Lua 里没找到短名「' + inputs.short + '」');
    }
    if (parsed[1].key != root + 'pack.bin') {
      throw PackError('第 2 槽不是 CIPK: ' + parsed[1].key);
    }
    final packData = parsed[1].value;
    if (!bytesEqual(packData, cipk)) throw PackError('pack.bin 与本次生成的容器不一致');
    final back = Cipk.parse(packData);
    if (back.length != files.length) throw PackError('CIPK 解回来张数不对');
    for (var i = 0; i < files.length; i++) {
      if (back[i].stem != files[i].stem) {
        throw PackError('第 ' + (i + 1).toString() + ' 张名字对不上: ' + back[i].stem);
      }
      if (!bytesEqual(back[i].data, files[i].data)) {
        throw PackError(back[i].stem + ' 内容不一致');
      }
    }
    return IconPackResult(out, pkg, inputs.packName, back.length);
  }
}

class IconPackInputs {
  const IconPackInputs({
    required this.short,
    required this.packName,
    required this.title,
    required this.files,
    this.pkgName,
  });

  /// 包短名(清单里的名字, 可打印 ASCII, ≤ 12 字节)
  final String short;
  final String packName;
  final String title;
  final String? pkgName;

  /// 已经过 AnimatedIcons.payload 整理的图标(未选的槽位不进包, 手环保持系统原图标)
  final List<CipkIcon> files;
}

class IconPackResult {
  const IconPackResult(this.bytes, this.pkgName, this.packName, this.iconCount);
  final Uint8List bytes;
  final String pkgName;
  final String packName;
  final int iconCount;
}

/// 打包的最后一道门: 把刚写出来的字节拆回来, 核对包名、显示名、槽数、每条槽的路径与内容。
///
/// 与“自己写出来”是两条独立路径(写入按表达式算, 回读按记录表里的偏移取), 所以能抓错位。
void verifyBuilt(
  Uint8List out,
  String pkgName,
  String packName,
  List<ShellEntry> entries,
) {
  final p = ShellBuilder.parse(out);
  if (p.pkg != pkgName) throw PackError('包名写错: ' + p.pkg);
  if (p.displayName != packName) throw PackError('表盘名写错: ' + p.displayName);
  if (p.files.length != entries.length) {
    throw PackError('槽数不符: 期望 ' + entries.length.toString() +
        ', 实际 ' + p.files.length.toString());
  }
  for (var i = 0; i < entries.length; i++) {
    if (p.files[i].key != entries[i].path) {
      throw PackError('第 ' + (i + 1).toString() + ' 槽路径不符: ' + p.files[i].key);
    }
    if (!bytesEqual(p.files[i].value, entries[i].data)) {
      throw PackError('第 ' + (i + 1).toString() + ' 槽内容不一致: ' + entries[i].path);
    }
  }
  ShellWriter.checkPkgAgainst(pkgName);
}

bool bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 把占位符换成本次的取值。[map] 里每个键都必须**恰好出现一次** —— 与 PC 侧同一条纪律。
///
/// 另外先把换行归一成 LF: 设备侧仓库里的 Lua 是 CRLF, 而 PC 侧打包器用文本模式读
/// (Python 会把 CRLF 折成 LF), 于是同一个模板两端产出的字节数会差“行数”那么多。
/// 逐字节对照测试就是靠这个差异发现的。归一只做一次, 放在这个函数里。
String patchLua(String src, Map<String, String> map) {
  final norm = src.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  for (final ph in map.keys) {
    final n = _countOccurrences(norm, ph);
    if (n != 1) throw PackError('投递 Lua 里 ' + ph + ' 应恰好出现 1 次, 实际 ' + n.toString() + ' 次');
  }
  var out = norm;
  for (final e in map.entries) {
    out = out.replaceAll(e.key, luaQuote(e.value));
  }
  return out;
}

int _countOccurrences(String s, String sub) {
  var n = 0;
  var i = s.indexOf(sub);
  while (i >= 0) {
    n++;
    i = s.indexOf(sub, i + sub.length);
  }
  return n;
}

/// 写成 Lua 双引号字面量。取值来自用户输入, 引号/反斜杠漏进去会在表盘的**构建期**
/// 抛错 ⇒ 整棵 UI 树不提交 ⇒ 切过去全黑(首版黑屏就是这一类)。
String luaQuote(String s) {
  final sb = StringBuffer();
  for (final ch in s.codeUnits) {
    if (ch == 0x22 || ch == 0x5C) {
      sb.writeCharCode(0x5C);
      sb.writeCharCode(ch);
    } else if (ch < 0x20) {
      sb.write('\\' + ch.toRadixString(10).padLeft(3, '0'));
    } else {
      sb.writeCharCode(ch);
    }
  }
  return sb.toString();
}

/// 供 UI 展示: 这次打包用到的内容摘要(便于用户核对导出的东西)。
String describePack(String label, String pkg, int bytes) =>
    label + ' · ' + pkg + ' · ' + (bytes / 1024).toStringAsFixed(1) + ' KB';
