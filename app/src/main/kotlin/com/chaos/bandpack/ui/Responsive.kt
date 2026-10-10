package com.chaos.bandpack.ui

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.chaos.bandpack.data.DeviceTarget

/** 宽度档位(只关心这三档; 具体数值由 material3-window-size-class 判定) */
enum class WidthClass { COMPACT, MEDIUM, EXPANDED }

/**
 * 当前窗口宽度档位。MainActivity 用官方 `calculateWindowSizeClass` 算好后放进这里,
 * 界面按档位决定列数/边距/是否分栏 —— 不针对某一个手机尺寸写死布局。
 */
val LocalWidthClass = staticCompositionLocalOf { WidthClass.COMPACT }
val LocalDeviceTarget = staticCompositionLocalOf { DeviceTarget.TEN_PRO }

/**
 * 工作区句柄: 设备切换与"这一份工程"的动作都要用它。
 *
 * 只给外壳与首页/制作页, 因为这三处才需要改工程; 数据页仍然读 [LocalDeviceTarget]。
 * 可空而不是造一个假工作区: 组件在没有宿主的场合(预览/单测)应当直接退成"不可切换",
 * 而不是拿一份状态全空的草稿去点。
 */
val LocalWorkspace = staticCompositionLocalOf<com.chaos.bandpack.ui.screen.StudioWorkspace?> { null }

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
