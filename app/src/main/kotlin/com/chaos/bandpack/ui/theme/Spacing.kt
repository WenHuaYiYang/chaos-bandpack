package com.chaos.bandpack.ui.theme

import androidx.compose.ui.unit.dp

/**
 * 间距系统: 只用 4/8/12/16/20/24/32 七档。界面代码里**不出现**这七个数以外的随机间距,
 * 也不在组件里散落魔法 dp —— 需要新档位时先想清楚层级, 而不是随手加一个 13dp。
 */
object Spacing {
    /** 4 —— 图标与文字、紧贴的标签 */
    val xs = 4.dp

    /** 8 —— 同一组内的行距 */
    val s = 8.dp

    /** 12 —— 列表项之间 */
    val m = 12.dp

    /** 16 —— 页面边距(紧凑屏)、段落之间 */
    val l = 16.dp

    /** 20 —— 卡片内边距 */
    val xl = 20.dp

    /** 24 —— 大节之间、页面边距(宽屏) */
    val xxl = 24.dp

    /** 32 —— 页首/页尾的呼吸 */
    val xxxl = 32.dp

    /** 页面左右边距: 紧凑屏 16, 中等以上 24 */
    val pageCompact = l
    val pageExpanded = xxl

    /** 触控目标下限(无障碍) */
    val minTouch = 48.dp

    /** 正文阅读宽上限: 再宽的行读起来会累; 宽屏下内容居中并卡这个宽度 */
    val contentMaxWidth = 720.dp
}
