/// 只读取字符串、整数和表字面量，**不求值 Lua**。
///
/// 投递包里那份 `main.lua` 是设备侧脚本，我们能拿到的可信信息只有它声明的
/// 几个常量。这里刻意做成一个极小的字面量读取器：认识的语法才读，别的一律
/// 报错，绝不把 Lua 交给求值器（在手机上执行容器里的脚本等于开后门）。
class LuaLiteral {
  LuaLiteral(this.text, [int start = 0]) : at = start;

  /// 待读文本。
  final String text;

  /// 当前读取位置。
  int at;

  int _nodes = 0;

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0B || c == 0x0C;

  static bool _isName(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F;

  void _space() {
    while (at < text.length && _isSpace(text.codeUnitAt(at))) {
      at++;
    }
  }

  /// 读一个字面量: 字符串 / 整数 / 表。
  Object? value([int depth = 0]) {
    if (depth > 6 || ++_nodes > 3000) {
      throw ImportError('投递清单嵌套过深或过大');
    }
    _space();
    if (at >= text.length) throw ImportError('投递清单意外结束');
    final String ch = text[at];
    if (ch == '"' || ch == "'") return _string();
    if (ch == '{') return _table(depth);
    if (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39) {
      final int begin = at;
      while (at < text.length) {
        final int c = text.codeUnitAt(at);
        if (c < 0x30 || c > 0x39) break;
        at++;
      }
      return int.parse(text.substring(begin, at));
    }
    throw ImportError('清单包含不能读取的表达式');
  }

  Object _table(int depth) {
    at++;
    final Map<String, Object?> map = <String, Object?>{};
    final List<Object?> list = <Object?>[];
    _space();
    while (at < text.length && text[at] != '}') {
      final int begin = at;
      while (at < text.length && _isName(text.codeUnitAt(at))) {
        at++;
      }
      final String name = text.substring(begin, at);
      _space();
      if (name.isNotEmpty && at < text.length && text[at] == '=') {
        at++;
        if (map.containsKey(name)) throw ImportError('清单字段重复');
        map[name] = value(depth + 1);
      } else {
        at = begin;
        list.add(value(depth + 1));
      }
      _space();
      if (at < text.length && (text[at] == ',' || text[at] == ';')) {
        at++;
        _space();
      } else {
        break;
      }
    }
    if (at >= text.length || text[at] != '}') {
      throw ImportError('不是有效的清单字面量');
    }
    at++;
    if (map.isNotEmpty && list.isNotEmpty) throw ImportError('清单表类型混杂');
    return map.isNotEmpty ? map : list;
  }

  String _string() {
    final String quote = text[at];
    at++;
    final StringBuffer out = StringBuffer();
    while (at < text.length) {
      final String ch = text[at];
      at++;
      if (ch == quote) {
        final String s = out.toString();
        if (s.length > 256) throw ImportError('清单字符串过长');
        return s;
      }
      if (ch != '\\') {
        out.write(ch);
        continue;
      }
      if (at >= text.length) throw ImportError('清单字符串未结束');
      final String next = text[at];
      at++;
      switch (next) {
        case '\\' || '"' || "'":
          out.write(next);
        case 'n':
          out.write('\n');
        case 'r':
          out.write('\r');
        case 't':
          out.write('\t');
        default:
          if (next.codeUnitAt(0) >= 0x30 && next.codeUnitAt(0) <= 0x39) {
            String number = next;
            for (int i = 0; i < 2; i++) {
              if (at < text.length) {
                final int c = text.codeUnitAt(at);
                if (c >= 0x30 && c <= 0x39) {
                  number += text[at];
                  at++;
                }
              }
            }
            final int byte = int.parse(number);
            if (byte > 255) throw ImportError('清单字符串转义超出字节范围');
            out.writeCharCode(byte);
          } else {
            throw ImportError('清单字符串转义不支持');
          }
      }
    }
    throw ImportError('清单字符串未结束');
  }
}

/// 容器导入错误。
class ImportError implements Exception {
  const ImportError(this.message);

  final String message;

  @override
  String toString() => 'ImportError: $message';
}
