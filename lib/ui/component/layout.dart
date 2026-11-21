import 'package:flutter/material.dart';

/// 版心与断点。
///
/// 手机上一行铺满没问题; 平板横过来有 1000+ 逻辑像素时, 一列铺满的卡片会
/// 变成又宽又扁的怪东西, 所以内容限宽居中, 超宽时改用两列。
abstract final class Layout {
  /// 单列内容的版心宽。再宽一行字就长得读不下去。
  static const double maxContent = 720;

  /// 侧栏模式下表单/列表的版心宽。桌面窗口够宽, 720 会显得两侧空荡。
  static const double wideContent = 980;

  /// 底栏胶囊的版心宽。宽屏上让它别拉成一条扁带。
  static const double maxNav = 460;

  /// 到了这个宽度就把首页卡片排成两列。
  static const double twoColumn = 760;

  /// 页面外边距: 窄屏 20, 宽屏按版心居中后仍是 20。
  static const double gutter = 20;

  /// 到了这个宽度, 底栏换成左侧导航栏。窗口横过来之后, 底部一条胶囊离内容
  /// 太远、也太浪费竖向空间; 左侧竖排才像桌面应用。
  static const double railBreakpoint = 900;

  /// 左侧导航栏宽度。够放图标 + 文字 + 选中块的圆角, 又不至于挤掉内容。
  static const double railWidth = 288;

  /// 收起后的侧栏: 只留图标, 把横向空间让给内容。
  static const double railCollapsedWidth = 76;

  /// 侧栏模式下内容区的外边距。桌面窗口比手机宽, 留白也要跟着大一点。
  static const double railGutter = 36;

  static bool isTwoColumn(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= twoColumn;

  static bool isRail(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= railBreakpoint;
}