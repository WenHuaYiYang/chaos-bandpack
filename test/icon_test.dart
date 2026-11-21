import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chaos_bandpack/icon/animated_icons.dart';
import 'package:chaos_bandpack/icon/device_target.dart';
import 'package:chaos_bandpack/icon/dgf1.dart';
import 'package:chaos_bandpack/icon/gif_icons.dart';
import 'package:chaos_bandpack/icon/icon_spec.dart';
import 'package:chaos_bandpack/icon/lvgl_icon_codec.dart';
import 'package:chaos_bandpack/icon/native_icon_stems.dart';
import 'package:chaos_bandpack/icon/nine_icon_spec.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

/// 读取金标准:[test/fixtures] 下的原始字节。
Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

/// `valid.dgf` 的调色板由 Python 脚本按 `(i ^ 85, 255 - i, i, 0 if i == 0 else 255)`
/// 的 BGRA 顺序合成; 这里按同一公式还原成 ARGB。
int goldenColor(int i) {
  final b = i ^ 85;
  final g = 255 - i;
  final r = i;
  final a = i == 0 ? 0 : 255;
  return (a << 24) | (r << 16) | (g << 8) | b;
}

void main() {
  group('LVGL 图像', () {
    test('cover96.bin 是 96 × 96 的 BGRA 图像, 回编逐字节一致', () {
      final raw = fixture('cover96.bin');
      expect(raw.length, 36876);
      expect(raw[0], LvglIconCodec.headerTag);
      expect(raw[1], 16); // BGRA8888
      expect(Dgf1.u16(raw, 4), 96);
      expect(Dgf1.u16(raw, 6), 96);
      expect(Dgf1.u16(raw, 8), 384); // stride

      final image = LvglIconCodec.decode(raw);
      expect(image.width, 96);
      expect(image.height, 96);
      expect(image.pixels.length, 9216);
      expect(image.pixels.every((p) => p == 0x80402010), isTrue);

      // 12 字节头 + 96 × 96 BGRA, 与原文件逐字节一致。
      final again = LvglIconCodec.bgra(image.pixels, 96, 96);
      expect(again.length, raw.length);
      expect(again, orderedEquals(raw));
    });

    test('legacy112.bin 是 112 × 112 的 BGRA 图像, 回编逐字节一致', () {
      final raw = fixture('legacy112.bin');
      expect(raw.length, 50188);
      expect(raw.length, 12 + 112 * 112 * 4);
      expect(raw[0], LvglIconCodec.headerTag);
      expect(raw[1], 16);
      expect(Dgf1.u16(raw, 4), 112);
      expect(Dgf1.u16(raw, 6), 112);
      expect(Dgf1.u16(raw, 8), 448);

      final image = LvglIconCodec.decode(raw);
      expect(image.width, 112);
      expect(image.height, 112);
      expect(image.pixels.length, 12544);
      expect(image.pixels.every((p) => p == 0xff132739), isTrue);
      expect(LvglIconCodec.bgra(image.pixels, 112, 112), orderedEquals(raw));
    });

    test('索引 RLE 编码可以原样解回', () {
      // 索引 0 固定留给透明, 所以这里用 250 种不透明色 + 0 做往返。
      final pixels =
          List<int>.generate(160 * 124, (i) => i % 7 == 0 ? 0 : (0xFF000000 | ((i % 250) << 8)));
      final bin = LvglIconCodec.indexedRle(pixels, 160, 124);
      final image = LvglIconCodec.decode(bin);
      expect(image.width, 160);
      expect(image.height, 124);
      expect(image.pixels, orderedEquals(pixels));
    });
  });

  group('DGF1 动画', () {
    test('valid.dgf 的头部、帧表、总长都符合金标准', () {
      final raw = fixture('valid.dgf');
      expect(raw.length, 10540);
      expect(String.fromCharCodes(raw.sublist(0, 4)), 'DGF1');
      expect(Dgf1.u16(raw, 4), 96);
      expect(Dgf1.u16(raw, 6), 96);
      expect(Dgf1.u16(raw, 8), 2);
      expect(Dgf1.u16(raw, 10), 0);
      expect(Dgf1.u32(raw, 12), 60001);
      expect(Dgf1.u32(raw, 16), 0xFFFFFFFF);
      expect(Dgf1.u32(raw, 20), Dgf1.tableOffset);
      expect(Dgf1.u32(raw, 24), 1108);
      expect(raw.sublist(28, 60), orderedEquals(List<int>.generate(32, (i) => i)));

      final anim = Dgf1.parse(raw);
      expect(anim.frames.length, 2);
      expect(anim.durationMs, 60001);
      expect(anim.plays, 0xFFFFFFFF);
      expect(anim.sourceHash, orderedEquals(List<int>.generate(32, (i) => i)));
      expect(anim.frames[0].delayMs, 1);
      expect(anim.frames[0].offset, 1108);
      expect(anim.frames[0].length, 144);
      expect(anim.frames[1].delayMs, 60000);
      expect(anim.frames[1].offset, 1252);
      expect(anim.frames[1].length, 9288);
      expect(anim.frames[1].offset + anim.frames[1].length, raw.length);
    });

    test('valid.dgf 每帧解压后恰好为 9216 字节, 像素查合成调色板', () {
      final raw = fixture('valid.dgf');
      final anim = Dgf1.parse(raw);
      for (var f = 0; f < anim.frames.length; f++) {
        final record = anim.frames[f];
        final indices = Dgf1.unpack(raw, record.offset, record.length);
        expect(indices.length, Dgf1.pixels, reason: '第 $f 帧解压长度');
        final pixels = anim.pixels(f);
        expect(pixels.length, Dgf1.pixels);
        expect(pixels, orderedEquals([for (final v in indices) goldenColor(v)]));
      }
      // 第一帧是 72 组 (0xFF, 0x01): 每次重复 128 个索引 1。
      final first = Dgf1.unpack(raw, anim.frames[0].offset, anim.frames[0].length);
      expect(first.every((v) => v == 1), isTrue);
    });

    test('valid.dgf 回编: 头部/帧表/总长逐字节一致, 负载等价', () {
      final raw = fixture('valid.dgf');
      final anim = Dgf1.parse(raw);
      final again = Dgf1.encode(<Frame>[
        for (var i = 0; i < anim.frames.length; i++)
          Frame(anim.pixels(i), anim.frames[i].delayMs),
      ], anim.plays, raw);

      // 帧数与调色板顺序都可复现, 所以总长与帧表(时长/偏移/长度)完全一致。
      expect(again.length, raw.length);
      expect(again.sublist(0, 28), orderedEquals(raw.sublist(0, 28)));
      expect(again.sublist(Dgf1.tableOffset, 1108), orderedEquals(raw.sublist(Dgf1.tableOffset, 1108)));
      // 源文件哈希就是 encode 的入参, 与 DGF1 的 sha256 字段对得上。
      expect(again.sublist(28, 60), orderedEquals(sha256.convert(raw).bytes));

      final back = Dgf1.parse(again);
      expect(back.durationMs, anim.durationMs);
      expect(back.plays, anim.plays);
      expect(back.frames.length, anim.frames.length);
      for (var i = 0; i < anim.frames.length; i++) {
        expect(back.frames[i].delayMs, anim.frames[i].delayMs);
        expect(back.pixels(i), orderedEquals(anim.pixels(i)), reason: '第 $i 帧像素');
      }
    });

    test('3 帧自行编码后可以解回同样的像素与时长', () {
      final frames = <Frame>[
        for (var f = 0; f < 3; f++)
          Frame(List<int>.generate(Dgf1.pixels, (i) => i < 96 ? 0 : (0xff000000 | (i & 255) << 16 | (i % 251) << 8 | (i % 241))), 10 + f),
      ];
      final out = Dgf1.encode(frames, 1, Uint8List.fromList(<int>[1, 2, 3]));
      final parsed = Dgf1.parse(out);
      expect(parsed.frames.length, 3);
      expect(parsed.durationMs, 33);
      expect(parsed.plays, 1);
      for (var f = 0; f < 3; f++) {
        expect(parsed.frames[f].delayMs, 10 + f);
        expect(parsed.pixels(f).take(96).every((p) => (p >> 24) & 255 == 0), isTrue);
      }
    });

    test('超过 256 色时共用一份有界调色板并保留透明', () {
      final frames = <Frame>[
        for (var f = 0; f < 3; f++)
          Frame(
              List<int>.generate(
                  Dgf1.pixels,
                  (i) => i < 96
                      ? 0
                      : (0xff000000 |
                          (((i * 17 + f) & 255) << 16) |
                          (((i ~/ 3) & 255) << 8) |
                          ((i ~/ 7) & 255))),
              10 + f),
      ];
      final out = Dgf1.encode(frames, 1, Uint8List.fromList(<int>[1, 2, 3]));
      expect(out.length, lessThanOrEqualTo(Dgf1.maxBytes));
      final parsed = Dgf1.parse(out);
      for (var i = 0; i < frames.length; i++) {
        expect(parsed.pixels(i).take(96).every((p) => (p >> 24) & 255 == 0), isTrue);
      }
    });

    test('超过 1 MiB 的动画被拒绝且不抽帧', () {
      final random = math.Random(67);
      final frames = <Frame>[
        for (var f = 0; f < 128; f++)
          Frame(
              List<int>.generate(Dgf1.pixels, (_) {
                final c = random.nextInt(256);
                return 0xff000000 | (c << 16) | (c << 8) | c;
              }),
              20),
      ];
      expect(
        () => Dgf1.encode(frames, 0, Uint8List.fromList(<int>[1])),
        throwsA(predicate((e) => e.toString().contains('1 MiB'))),
      );
      expect(frames.length, 128);
      expect(frames.every((f) => f.pixels.length == Dgf1.pixels), isTrue);
    });

    test('损坏的 DGF1 会被拒绝', () {
      final raw = fixture('valid.dgf');
      expect(() => Dgf1.parse(raw.sublist(0, raw.length - 1)), throwsA(isA<Dgf1Error>()));
      final bad = Uint8List.fromList(raw)..[0] = 0x45;
      expect(() => Dgf1.parse(bad), throwsA(isA<Dgf1Error>()));
    });
  });

  group('GIF 合成与循环', () {
    final references =
        jsonDecode(utf8.decode(fixture('reference.json'))) as Map<String, dynamic>;

    for (final name in references.keys) {
      test('$name 的像素、时长与循环次数与 Pillow 一致', () {
        final original = fixture('$name.gif');
        expect(GifIcons.isGif(original), isTrue);
        final ref = references[name] as Map<String, dynamic>;
        final made = GifIcons.convert(original);
        final parsed = Dgf1.parse(made.animation);

        expect(parsed.plays, ref['plays'] as int, reason: '循环次数');
        expect(parsed.frames.map((f) => f.delayMs).toList(),
            (ref['delays'] as List<dynamic>).cast<int>());
        expect(parsed.sourceHash, orderedEquals(sha256.convert(original).bytes));
        expect(made.frameCount, parsed.frames.length);
        expect(made.durationMs, parsed.durationMs);
        expect(made.plays, parsed.plays);

        final rgba = fixture('$name.rgba');
        expect(rgba.length, parsed.frames.length * Dgf1.pixels * 4);
        for (var f = 0; f < parsed.frames.length; f++) {
          final expected = List<int>.generate(Dgf1.pixels, (i) {
            final p = (f * Dgf1.pixels + i) * 4;
            final a = rgba[p + 3];
            if (a == 0) return 0; // 透明像素的 RGB 不参与比较
            return (a << 24) | (rgba[p] << 16) | (rgba[p + 1] << 8) | rgba[p + 2];
          });
          expect(parsed.pixels(f), orderedEquals(expected), reason: '$name 第 $f 帧');
          if (f == 0) {
            expect(LvglIconCodec.decode(made.cover).pixels, orderedEquals(expected));
          }
        }
      });
    }

    test('无效 GIF 被拒绝且不抽帧不改时长', () {
      expect(() => GifIcons.convert(fixture('zero-delay.gif')), throwsA(isA<GifIconError>()));
      expect(
        () => GifIcons.convert(fixture('too-many.gif')),
        throwsA(predicate((e) => e.toString().contains('256'))),
      );
      final valid = fixture('disposal.gif');
      final half = Uint8List.sublistView(valid, 0, valid.length ~/ 2);
      expect(() => GifIcons.convert(half), throwsA(isA<GifIconError>()));
      final broken = Uint8List.fromList(valid);
      broken[6] = 0;
      broken[7] = 0;
      expect(() => GifIcons.convert(broken), throwsA(isA<GifIconError>()));
    });
  });

  group('槽位与原生资源', () {
    test('native-stems.txt 的顺序与内容与 NativeIconStems 一致', () {
      final lines = File('test/fixtures/native-stems.txt')
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      expect(lines.length, 106);
      expect(NativeIconStems.all.length, 106);
      expect(NativeIconStems.all.toList(), orderedEquals(lines));
      expect(NativeIconStems.all.first, 'ctrl_flashlight');
      expect(NativeIconStems.all.last, 'card_widget_card_bg');
    });

    test('桌面/控制中心/设置槽位数量与落盘路径', () {
      expect(IconSpec.desktop.length, 38); // 与 Kotlin 的 IconSpec.DESKTOP 一致
      expect(IconSpec.control.length, 9);
      expect(IconSpec.settings.length, 10);
      expect(IconSpec.devicePath('alarm'), '/data/chaos/icons/alarm.bin');
      expect(IconSpec.stemOf('alarm')!.label, '闹钟');
      expect(IconSpec.stemOf('alarm')!.canvas, 96);
      expect(IconSpec.outBytes, 12 + 96 * 96 * 4);
      expect(IconSpec.header, orderedEquals(LvglIconCodec.header(96, 96, 16, 0, 384)));
      expect(IconSpec.matchName('alarm')!.stem, 'alarm');
      expect(IconSpec.previewStems('perpetual_calendar'), <String>['calendar_background']);
      expect(IconSpec.duplicateStems(<String?>['a', 'b', 'a']), <String>{'a'});
      expect(IconSpec.all(DeviceTarget.ninePro).length, NineIconSpec.slots.length);
      expect(IconSpec.all(DeviceTarget.ninePro).first.stem, 'heartrate');
    });

    test('CIA1 索引与动画键', () {
      expect(AnimatedIcons.stems.length, 38);
      expect(AnimatedIcons.key('alarm'), 'alarm_anim');
      expect(AnimatedIcons.isAnimationKey('alarm_anim'), isTrue);
      expect(AnimatedIcons.base('alarm_anim'), 'alarm');
      final index = AnimatedIcons.index(<String>{'alarm', 'music', 'wxpay'});
      expect(index.length, 20);
      expect(String.fromCharCodes(index.sublist(0, 4)), 'CIA1');
      expect(Dgf1.u16(index, 8), 38);
      expect(AnimatedIcons.readIndex(index), <String>{'alarm', 'music', 'wxpay'});
    });
  });
}
