/// 一个够用的 VT100/ANSI 屏幕模型。
///
/// 手环那头吐的是原始字节流: 有 ESC[K 这种擦行、有颜色、有回车覆盖。
/// 直接把这些字节塞进 Text 里, 屏幕上就会出现方块 —— 那不是乱码,
/// 是控制序列没被解释。这里按真实终端的方式维护一个字符网格, 由界面负责画。
library;

/// 单元格的样式。颜色用 0xRRGGBB, null 表示默认色。
class AnsiStyle {
  const AnsiStyle({
    this.fg,
    this.bg,
    this.bold = false,
    this.dim = false,
    this.underline = false,
    this.reverse = false,
  });

  final int? fg;
  final int? bg;
  final bool bold;
  final bool dim;
  final bool underline;
  final bool reverse;

  static const AnsiStyle plain = AnsiStyle();

  bool get isPlain =>
      fg == null && bg == null && !bold && !dim && !underline && !reverse;

  AnsiStyle copyWith({
    int? fg,
    int? bg,
    bool? bold,
    bool? dim,
    bool? underline,
    bool? reverse,
    bool clearFg = false,
    bool clearBg = false,
  }) =>
      AnsiStyle(
        fg: clearFg ? null : (fg ?? this.fg),
        bg: clearBg ? null : (bg ?? this.bg),
        bold: bold ?? this.bold,
        dim: dim ?? this.dim,
        underline: underline ?? this.underline,
        reverse: reverse ?? this.reverse,
      );

  @override
  bool operator ==(Object other) =>
      other is AnsiStyle &&
      other.fg == fg &&
      other.bg == bg &&
      other.bold == bold &&
      other.dim == dim &&
      other.underline == underline &&
      other.reverse == reverse;

  @override
  int get hashCode => Object.hash(fg, bg, bold, dim, underline, reverse);
}

class AnsiCell {
  const AnsiCell(this.ch, this.style);

  final String ch;
  final AnsiStyle style;

  static const AnsiCell blank = AnsiCell(' ', AnsiStyle.plain);
}

/// 标准 16 色。数值取自 xterm 默认配色, 在深色底上辨识度够。
const List<int> ansiPalette = <int>[
  0x1C1C1C, 0xCC5555, 0x4E9A06, 0xC4A000, 0x3465A4, 0x75507B, 0x06989A, 0xD3D7CF,
  0x555753, 0xEF2929, 0x8AE234, 0xFCE94F, 0x729FCF, 0xAD7FA8, 0x34E2E2, 0xEEEEEC,
];

int _palette256(int index) {
  if (index < 16) return ansiPalette[index];
  if (index < 232) {
    final int i = index - 16;
    int level(int v) => v == 0 ? 0 : 55 + v * 40;
    return (level(i ~/ 36) << 16) | (level((i ~/ 6) % 6) << 8) | level(i % 6);
  }
  final int v = 8 + (index - 232) * 10;
  return (v << 16) | (v << 8) | v;
}

/// 屏幕模型: 固定列宽, 保留一段滚动历史。
class AnsiTerminal {
  AnsiTerminal({this.columns = 96, this.maxLines = 4000}) {
    _lines.add(_blankLine());
  }

  final int columns;
  final int maxLines;

  final List<List<AnsiCell>> _lines = <List<AnsiCell>>[];
  int _row = 0;
  int _col = 0;
  AnsiStyle _style = AnsiStyle.plain;
  int _savedRow = 0;
  int _savedCol = 0;

  // 解析状态: 控制序列可能被拆在两个 chunk 里, 所以状态要跨 write 保留。
  String _state = 'ground';
  final StringBuffer _csi = StringBuffer();
  bool _oscEsc = false;

  int get cursorRow => _row;
  int get cursorCol => _col;

  /// 当前屏幕内容。
  List<List<AnsiCell>> get lines => List<List<AnsiCell>>.unmodifiable(_lines);

  void reset() {
    _lines
      ..clear()
      ..add(_blankLine());
    _row = 0;
    _col = 0;
    _style = AnsiStyle.plain;
    _state = 'ground';
    _csi.clear();
  }

  List<AnsiCell> _blankLine() =>
      List<AnsiCell>.filled(columns, AnsiCell.blank, growable: true);

  void _ensureRow(int row) {
    while (_lines.length <= row) {
      _lines.add(_blankLine());
    }
    // 超出历史上限时从最老的开始丢, 光标跟着上移, 否则越滚越偏。
    while (_lines.length > maxLines) {
      _lines.removeAt(0);
      if (_row > 0) _row--;
    }
  }

  void _ensureCol(int col) {
    final line = _lines[_row];
    while (line.length <= col) {
      line.add(AnsiCell.blank);
    }
  }

  void write(String data) {
    for (final int c in data.runes) {
      _feed(c);
    }
  }

  void _feed(int c) {
    switch (_state) {
      case 'osc':
        if (c == 0x07) {
          _state = 'ground';
        } else if (c == 0x1b) {
          _oscEsc = true;
        } else if (_oscEsc && c == 0x5c) {
          _state = 'ground';
          _oscEsc = false;
        } else {
          _oscEsc = false;
        }
        return;
      case 'charset':
        _state = 'ground';
        return;
      case 'esc':
        _state = 'ground';
        if (c == 0x5b) {
          _csi.clear();
          _state = 'csi';
        } else if (c == 0x5d) {
          _state = 'osc';
          _oscEsc = false;
        } else if (c == 0x28 || c == 0x29) {
          _state = 'charset';
        } else if (c == 0x37) {
          _savedRow = _row;
          _savedCol = _col;
        } else if (c == 0x38) {
          _row = _savedRow;
          _col = _savedCol;
        } else if (c == 0x63) {
          reset();
        } else if (c == 0x4d) {
          _row = _row > 0 ? _row - 1 : 0;
        } else if (c == 0x44) {
          _lineFeed();
        } else if (c == 0x45) {
          _lineFeed();
          _col = 0;
        }
        return;
      case 'csi':
        if (c >= 0x40 && c <= 0x7e) {
          _dispatch(_csi.toString(), String.fromCharCode(c));
          _csi.clear();
          _state = 'ground';
        } else if (c == 0x1b) {
          // 序列被打断, 重新开始一个转义。
          _csi.clear();
          _state = 'esc';
        } else {
          _csi.writeCharCode(c);
        }
        return;
    }

    // ground
    if (c == 0x1b) {
      _state = 'esc';
    } else if (c == 0x0a) {
      _lineFeed();
    } else if (c == 0x0d) {
      _col = 0;
    } else if (c == 0x08) {
      if (_col > 0) _col--;
    } else if (c == 0x09) {
      _col = ((_col ~/ 8) + 1) * 8;
      if (_col >= columns) _col = columns - 1;
    } else if (c == 0x07) {
      // 响铃: 桌面端不出声, 也不该在屏幕上留字符。
    } else if (c < 0x20) {
      // 其余控制字符忽略。
    } else {
      _put(String.fromCharCode(c));
    }
  }

  void _lineFeed() {
    _row++;
    _ensureRow(_row);
  }

  void _put(String ch) {
    if (_col >= columns) {
      _col = 0;
      _lineFeed();
    }
    _ensureRow(_row);
    _ensureCol(_col);
    _lines[_row][_col] = AnsiCell(ch, _style);
    _col++;
  }

  List<int> _params(String raw) {
    // 私有模式(?)和中间字节都不属于数值参数, 直接跳过前缀。
    var s = raw;
    while (s.isNotEmpty && (s.codeUnitAt(0) < 0x30 || s.codeUnitAt(0) > 0x39)) {
      if (s.codeUnitAt(0) == 0x3b) break;
      s = s.substring(1);
    }
    if (s.isEmpty) return const <int>[];
    return s.split(';').map((e) => int.tryParse(e.trim()) ?? 0).toList();
  }

  int _arg(List<int> p, int i, int fallback) =>
      i < p.length && p[i] != 0 ? p[i] : fallback;

  void _dispatch(String raw, String finalByte) {
    final p = _params(raw);
    switch (finalByte) {
      case 'm':
        _sgr(p);
      case 'K':
        _eraseLine(_arg(p, 0, 0));
      case 'J':
        _eraseDisplay(_arg(p, 0, 0));
      case 'H':
      case 'f':
        _row = (_arg(p, 0, 1) - 1).clamp(0, maxLines - 1);
        _col = (_arg(p, 1, 1) - 1).clamp(0, columns - 1);
        _ensureRow(_row);
      case 'A':
        _row = (_row - _arg(p, 0, 1)).clamp(0, maxLines - 1);
      case 'B':
        _row += _arg(p, 0, 1);
        _ensureRow(_row);
      case 'C':
        _col = (_col + _arg(p, 0, 1)).clamp(0, columns - 1);
      case 'D':
        _col = (_col - _arg(p, 0, 1)).clamp(0, columns - 1);
      case 'G':
        _col = (_arg(p, 0, 1) - 1).clamp(0, columns - 1);
      case 'd':
        _row = (_arg(p, 0, 1) - 1).clamp(0, maxLines - 1);
        _ensureRow(_row);
      case 's':
        _savedRow = _row;
        _savedCol = _col;
      case 'u':
        _row = _savedRow;
        _col = _savedCol;
      default:
        // 模式设置、设备查询、滚动区域对"记录屏幕"没有意义。
        break;
    }
  }

  void _eraseLine(int mode) {
    _ensureRow(_row);
    final line = _lines[_row];
    switch (mode) {
      case 1:
        for (var i = 0; i <= _col && i < line.length; i++) {
          line[i] = AnsiCell(' ', AnsiStyle(bg: _style.bg));
        }
      case 2:
        line
          ..clear()
          ..addAll(_blankLine());
      default:
        for (var i = _col; i < line.length; i++) {
          line[i] = AnsiCell(' ', AnsiStyle(bg: _style.bg));
        }
    }
  }

  void _eraseDisplay(int mode) {
    switch (mode) {
      case 1:
        for (var r = 0; r < _row; r++) {
          _lines[r]
            ..clear()
            ..addAll(_blankLine());
        }
        _eraseLine(1);
      case 2:
        for (final line in _lines) {
          line
            ..clear()
            ..addAll(_blankLine());
        }
        _row = 0;
        _col = 0;
      default:
        _eraseLine(0);
        for (var r = _row + 1; r < _lines.length; r++) {
          _lines[r]
            ..clear()
            ..addAll(_blankLine());
        }
    }
  }

  void _sgr(List<int> p) {
    if (p.isEmpty) {
      _style = AnsiStyle.plain;
      return;
    }
    for (var i = 0; i < p.length; i++) {
      final int v = p[i];
      if (v == 0) {
        _style = AnsiStyle.plain;
      } else if (v == 1) {
        _style = _style.copyWith(bold: true);
      } else if (v == 2) {
        _style = _style.copyWith(dim: true);
      } else if (v == 4) {
        _style = _style.copyWith(underline: true);
      } else if (v == 7) {
        _style = _style.copyWith(reverse: true);
      } else if (v == 22) {
        _style = _style.copyWith(bold: false, dim: false);
      } else if (v == 24) {
        _style = _style.copyWith(underline: false);
      } else if (v == 27) {
        _style = _style.copyWith(reverse: false);
      } else if (v >= 30 && v <= 37) {
        _style = _style.copyWith(fg: ansiPalette[v - 30]);
      } else if (v == 39) {
        _style = _style.copyWith(clearFg: true);
      } else if (v >= 40 && v <= 47) {
        _style = _style.copyWith(bg: ansiPalette[v - 40]);
      } else if (v == 49) {
        _style = _style.copyWith(clearBg: true);
      } else if (v >= 90 && v <= 97) {
        _style = _style.copyWith(fg: ansiPalette[v - 90 + 8]);
      } else if (v >= 100 && v <= 107) {
        _style = _style.copyWith(bg: ansiPalette[v - 100 + 8]);
      } else if (v == 38 || v == 48) {
        final bool fg = v == 38;
        if (i + 2 < p.length && p[i + 1] == 5) {
          final int color = _palette256(p[i + 2].clamp(0, 255));
          _style = fg ? _style.copyWith(fg: color) : _style.copyWith(bg: color);
          i += 2;
        } else if (i + 4 < p.length && p[i + 1] == 2) {
          final int color = ((p[i + 2].clamp(0, 255)) << 16) |
              ((p[i + 3].clamp(0, 255)) << 8) |
              p[i + 4].clamp(0, 255);
          _style = fg ? _style.copyWith(fg: color) : _style.copyWith(bg: color);
          i += 4;
        } else {
          break;
        }
      }
    }
  }

  /// 把屏幕压成纯文本, 用于复制和测试。
  String toText() {
    final buf = StringBuffer();
    for (final line in _lines) {
      final text = line.map((c) => c.ch).join().replaceFirst(RegExp(r'\s+$'), '');
      buf.writeln(text);
    }
    return buf.toString();
  }
}
