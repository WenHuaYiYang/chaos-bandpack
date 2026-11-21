import 'dart:typed_data';

/// 标准反射 CRC-32(多项式 0xEDB88320), 与固件 `cc_crc32` 逐位一致。
///
/// 固件侧是"分两段累加": 先算帧头前 12 字节, 再把 payload 接着喂进去,
/// 中间不结尾也不重置 —— 所以这里也给流式接口, 不要写成一次算完的便利函数。
class Crc32 {
  static const int _poly = 0xEDB88320;
  static final Uint32List _table = _build();

  static Uint32List _build() {
    final t = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (_poly ^ (c >> 1)) : (c >> 1);
      }
      t[i] = c;
    }
    return t;
  }

  /// 累加一段。第一次传 [seed] = 0xFFFFFFFF, 之后把上次的返回值接着传。
  static int update(int seed, List<int> data, [int start = 0, int? end]) {
    var crc = seed;
    final stop = end ?? data.length;
    for (var i = start; i < stop; i++) {
      crc = _table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    }
    return crc;
  }

  /// 收尾: 取反。固件 `crc32_final` 同款。
  static int finalize(int crc) => (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;

  /// 一次算完一整段(不带初值/收尾的裸接口, 只给自测用)。
  static int of(List<int> data) => finalize(update(0xFFFFFFFF, data));
}
