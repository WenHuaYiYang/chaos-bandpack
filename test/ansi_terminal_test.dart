import 'package:chaos_bandpack/chaos/ansi_terminal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ESC[K 擦掉行尾而不是留下方块', () {
    final t = AnsiTerminal(columns: 20);
    t.write('ap> ls\x1b[K');
    expect(t.toText().trimRight(), 'ap> ls');
  });

  test('回车覆盖同一行，模拟进度条', () {
    final t = AnsiTerminal(columns: 20);
    t.write('50%\r100%');
    expect(t.toText().trimRight(), '100%');
  });

  test('换行与擦除整屏', () {
    final t = AnsiTerminal(columns: 20);
    t.write('one\ntwo\n');
    t.write('\x1b[2J\x1b[H');
    t.write('three');
    final text = t.toText();
    expect(text.trimRight(), 'three');
    expect(text.contains('one'), isFalse);
  });

  test('SGR 颜色解析成前景色，重置后回到默认', () {
    final t = AnsiTerminal(columns: 20);
    t.write('\x1b[31mred\x1b[0m plain');
    final line = t.lines.first;
    expect(line[0].style.fg, ansiPalette[1]);
    expect(line[0].ch, 'r');
    expect(line[4].style.isPlain, isTrue);
  });

  test('256 色与真彩色都认', () {
    final t = AnsiTerminal(columns: 20);
    t.write('\x1b[38;5;196mx');
    expect(t.lines.first[0].style.fg, isNotNull);
    t.write('\x1b[0m\x1b[38;2;10;20;30my');
    expect(t.lines.first[1].style.fg, 0x0A141E);
  });

  test('控制序列被拆在两个 chunk 里也能接上', () {
    final t = AnsiTerminal(columns: 20);
    t.write('abc\x1b[');
    t.write('2K');
    t.write('xy');
    // ESC[2K 只擦内容, 不移动光标: 真实终端也会把 xy 写在原来的第 4 列。
    expect(t.toText().trimRight(), '   xy');
  });

  test('OSC 标题序列不污染屏幕', () {
    final t = AnsiTerminal(columns: 20);
    t.write('\x1b]0;title\x07hello');
    expect(t.toText().trimRight(), 'hello');
  });

  test('制表符与退格按终端语义处理', () {
    final t = AnsiTerminal(columns: 40);
    t.write('a\tb');
    expect(t.lines.first[0].ch, 'a');
    expect(t.lines.first[8].ch, 'b');
    t.write('\b\bX');
    expect(t.lines.first[7].ch, 'X');
  });

  test('历史超过上限时丢最老的，光标不越界', () {
    final t = AnsiTerminal(columns: 10, maxLines: 5);
    for (var i = 0; i < 20; i++) {
      t.write('line ' + i.toString() + '\n');
    }
    expect(t.lines.length, lessThanOrEqualTo(5));
    expect(t.cursorRow, lessThan(t.lines.length));
  });

  test('宽字符只占一格，不会把行撑破', () {
    final t = AnsiTerminal(columns: 4);
    t.write('中文测试');
    expect(t.lines.length, 1);
    expect(t.lines.first[0].ch, '中');
    expect(t.cursorCol, 4);
  });
}
