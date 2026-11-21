import 'package:flutter/widgets.dart';

import '../icon/device_target.dart';
import 'chaos_project.dart';

/// 一份工程的当前状态。
///
/// 制作页各自持有自己的编辑态(输入框、选中槽位), 但这个状态必须在切页、导入、
/// 保存之间活下来 —— 所以真正的工程数据放在这里, 页面只往里写快照。
class ProjectStore extends ChangeNotifier {
  DeviceTarget _device = DeviceTarget.tenPro;
  IconProject? _icons;
  FontProject? _font;
  String? _file;

  DeviceTarget get device => _device;

  IconProject? get icons => _icons;

  FontProject? get font => _font;

  /// 这份工程是从哪个文件读进来的(显示用, 不参与保存)。
  String? get file => _file;

  bool get isEmpty => _icons == null && _font == null;

  void setDevice(DeviceTarget device) {
    if (_device == device) return;
    _device = device;
    notifyListeners();
  }

  void setIcons(IconProject icons) {
    _icons = icons;
    notifyListeners();
  }

  void setFont(FontProject font) {
    _font = font;
    notifyListeners();
  }

  void clearIcons() {
    _icons = null;
    notifyListeners();
  }

  /// 整体替换(导入工程 / 导入投递包时用)。
  void apply(ChaosProject project, {String? file}) {
    _device = project.device;
    _icons = project.icons;
    _font = project.font;
    _file = file;
    notifyListeners();
  }

  void forgetFile() => _file = null;

  ChaosProject? snapshot() {
    final IconProject? icons = _icons;
    final FontProject? font = _font;
    if (icons == null && font == null) return null;
    return ChaosProject(device: _device, icons: icons, font: font);
  }
}

/// 把 [ProjectStore] 放到树里, 让任意页面都能读写当前工程。
class ProjectScope extends InheritedNotifier<ProjectStore> {
  const ProjectScope({
    required ProjectStore store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  static ProjectStore of(BuildContext context) {
    final ProjectScope? scope =
        context.dependOnInheritedWidgetOfExactType<ProjectScope>();
    assert(scope != null, 'ProjectScope 不在树里');
    return scope!.notifier!;
  }

  static ProjectStore read(BuildContext context) {
    final ProjectScope? scope =
        context.getElementForInheritedWidgetOfExactType<ProjectScope>()?.widget
            as ProjectScope?;
    assert(scope != null, 'ProjectScope 不在树里');
    return scope!.notifier!;
  }
}
