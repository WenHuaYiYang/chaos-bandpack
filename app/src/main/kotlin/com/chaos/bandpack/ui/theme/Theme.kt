package com.chaos.bandpack.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.platform.LocalContext

/** 当前风格。界面要分档处理时读它（例如取图标、算色场），不要各自去读 UiPrefs */
val LocalThemeStyle = compositionLocalOf { ThemeStyle.PAPER }

/**
 * 全应用主题。界面代码只取 `MaterialTheme.colorScheme / typography / shapes / motionScheme`
 * 与 [LocalPageTone]，不写死颜色、字号与圆角。
 *
 * 两档风格共用同一套接口，差别只在"怎么算"：
 *
 *   [ThemeStyle.PAPER]（默认）—— 参考图那套：冷灰底 `#F1F1F1` + 暖白卡 `#FCFBF9`
 *      + 蓝/鼠尾草/蜜桃三个粉彩强调 + MingCute 线性图标。颜色真值是从参考图里采样来的。
 *   [ThemeStyle.MD3] —— 上一版：品牌色板（或 Material You 动态取色）+ 整页色场。
 *
 * `MotionScheme.expressive()` 两档都用：动效这套跟风格无关，换的是视觉不是手感。
 */
@Composable
fun ChaosTheme(content: @Composable () -> Unit) {
    val style = UiPrefs.themeStyle
    val dark = when (UiPrefs.appearance) {
        Appearance.SYSTEM -> isSystemInDarkTheme()
        Appearance.LIGHT -> false
        Appearance.DARK -> true
    }
    val scheme = when (style) {
        ThemeStyle.PAPER -> if (dark) PaperPalette.Dark else PaperPalette.Light
        ThemeStyle.MD3 -> {
            if (UiPrefs.dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val ctx = LocalContext.current
                if (dark) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
            } else if (dark) {
                DarkScheme
            } else {
                LightScheme
            }
        }
    }
    MaterialExpressiveTheme(
        colorScheme = scheme,
        motionScheme = MotionScheme.expressive(),
        typography = ChaosTypography,
        shapes = if (style == ThemeStyle.PAPER) PaperPalette.Shapes else ChaosShapes,
    ) {
        CompositionLocalProvider(LocalThemeStyle provides style, content = content)
    }
}
