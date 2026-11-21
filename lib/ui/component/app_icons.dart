import 'package:flutter/widgets.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';

/// 界面图标。全部来自 MingCute(<https://www.mingcute.com/>)的 Line/Fill 双字形,
/// 一处定义, 各页只引用 [AppIcons], 不再直接写 Material 的 Icons.*。
///
/// 选型原则: 常态用 Line, 选中/激活用同一枚的 Fill —— 同一个语义只换字重,
/// 形状不变, 底栏与分段器切换时读者不需要重新认图。
abstract final class AppIcons {
  // 底栏与页面导航
  static const IconData home = MingCuteIcons.home1Line;
  static const IconData homeActive = MingCuteIcons.home1Fill;
  static const IconData font = MingCuteIcons.fontLine;
  static const IconData fontActive = MingCuteIcons.fontFill;
  // 图标制作: 用 2x2 格子加号, 读作「一排排图标槽, 再添一个」。
  // App Store 那枚 A 标是苹果的商号形状, 放在自己的制作页上既不对题也容易被误认。
  static const IconData iconPack = MingCuteIcons.grid2x2PlusLine;
  static const IconData iconPackActive = MingCuteIcons.grid2x2PlusFill;
  static const IconData device = MingCuteIcons.bluetoothLine;
  static const IconData deviceActive = MingCuteIcons.bluetoothFill;
  static const IconData settings = MingCuteIcons.settings2Line;
  static const IconData settingsActive = MingCuteIcons.settings2Fill;
  // 二级页左上角的返回。MingCute 没有 chevronLeft, 单向箭头就是 arrowLeft。
  static const IconData back = MingCuteIcons.arrowLeftLine;
  // 资源商店: 用购物袋。原来的店招轮廓(storeLine)在小尺寸下像一顶帽子,
  // 底栏里看不出是"买东西的地方"; 购物袋的提手一压就认出来了。
  static const IconData store = MingCuteIcons.shoppingBag2Line;
  static const IconData storeActive = MingCuteIcons.shoppingBag2Fill;

  // 连接与传输
  static const IconData linked = MingCuteIcons.bluetoothConnectedLine;
  static const IconData unlinked = MingCuteIcons.unlinkLine;
  static const IconData transfer = MingCuteIcons.transferLine;
  static const IconData refresh = MingCuteIcons.refresh2Line;
  /// 主动搜附近设备。与 [refresh](重读已配对列表)不是一回事, 所以分开两枚。
  static const IconData search = MingCuteIcons.searchLine;
  static const IconData send = MingCuteIcons.sendLine;
  static const IconData download = MingCuteIcons.downloadLine;
  static const IconData upload = MingCuteIcons.uploadLine;

  // 文件与工程
  static const IconData openProject = MingCuteIcons.folderOpenLine;
  static const IconData saveProject = MingCuteIcons.save2Line;
  static const IconData file = MingCuteIcons.fileLine;
  static const IconData folder = MingCuteIcons.folderLine;

  // 制作页
  // 生成包: 用 packageLine, 因为这个按钮的产物就是一个 .bin 包。
  // 原来的魔棒读作「AI 一键生成」, 和这里点一下真的在子集化/编码不是一回事。
  static const IconData build = MingCuteIcons.packageLine;
  static const IconData pickImage = MingCuteIcons.imagePlusLine;
  static const IconData pickFont = MingCuteIcons.fontLine;
  static const IconData slots = MingCuteIcons.layoutGridLine;
  static const IconData add = MingCuteIcons.addLine;
  static const IconData clear = MingCuteIcons.closeCircleLine;
  static const IconData forward = MingCuteIcons.arrowRightLine;
  static const IconData chevronRight = MingCuteIcons.arrowRightLine;

  // 动图预览: 播放/暂停用同一套圆形图标, 只是换字重。
  static const IconData play = MingCuteIcons.playLine;
  static const IconData pause = MingCuteIcons.pauseLine;

  // 状态
  static const IconData ok = MingCuteIcons.checkCircleLine;
  static const IconData info = MingCuteIcons.informationLine;
  static const IconData warn = MingCuteIcons.alertLine;
  static const IconData error = MingCuteIcons.closeCircleLine;
}
