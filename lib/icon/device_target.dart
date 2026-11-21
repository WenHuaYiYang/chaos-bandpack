/// 设备型号: [id] 是工程里存的短号, [label] 给界面看, [firmware] 是目标固件版本。
///
/// (Kotlin 侧在 `com.chaos.bandpack.data.DeviceTarget`, 图标层只是它的使用者。)
enum DeviceTarget {
  tenPro('p67', '10 Pro', '3.101.043'),
  ninePro('n67', '9 Pro', '3.1.187');

  const DeviceTarget(this.id, this.label, this.firmware);

  final String id;
  final String label;
  final String firmware;

  /// 按工程里存的 id 找回型号; 不认识的 id 直接报错, 不做兜底。
  static DeviceTarget fromId(String id) {
    for (final t in DeviceTarget.values) {
      if (t.id == id) return t;
    }
    throw DeviceTargetError('工程中的设备型号不支持：$id');
  }
}

class DeviceTargetError implements Exception {
  DeviceTargetError(this.message);

  final String message;

  @override
  String toString() => 'DeviceTargetError: $message';
}
