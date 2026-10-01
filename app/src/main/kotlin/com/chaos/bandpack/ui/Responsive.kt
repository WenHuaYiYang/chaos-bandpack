package com.chaos.bandpack.ui

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** 宽度档位(只关心这三档; 具体数值由 material3-window-size-class 判定) */
enum class WidthClass { COMPACT, MEDIUM, EXPANDED }

/**
 * 当前窗口宽度档位。MainActivity 用官方 `calculateWindowSizeClass` 算好后放进这里,
 * 界面按档位决定列数/边距/是否分栏 —— 不针对某一个手机尺寸写死布局。
 */
val LocalWidthClass = staticCompositionLocalOf { WidthClass.COMPACT }

/** 图标网格列数: 紧凑 4 / 中等 6 / 宽屏 8 */
val WidthClass.gridColumns: Int
    get() = when (this) {
        WidthClass.COMPACT -> 4
        WidthClass.MEDIUM -> 6
        WidthClass.EXPANDED -> 8
    }

/** 页面左右边距: 紧凑 16 / 其余 24 */
val WidthClass.pagePadding: Dp
    get() = when (this) {
        WidthClass.COMPACT -> 16.dp
        else -> 24.dp
    }

/** 是否宽到可以左右分栏(字体页: 左参数右预览) */
val WidthClass.twoPane: Boolean get() = this != WidthClass.COMPACT
