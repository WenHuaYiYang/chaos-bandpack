package com.chaos.bandpack.ui.theme

import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color

/**
 * 品牌回退色板（Android 12 以下, 或用户关掉动态取色时用）。
 *
 * **不是手调的近似值**: 由官方 material-color-utilities 算法从品牌种子
 * `#2A82E4`（chaos.png 主蓝）生成, TonalSpot 方案 / 对比度 0 / SPEC_2021。
 * 生成入口见 `ColorSchemeGenerationTest`（重跑它把打印结果贴回本文件即可, 运行时不依赖该库）。
 *
 * 用色纪律: 颜色必须承担语义 ——
 *   primary 用于主操作、选中态
 *   secondary 用于字体线（入口徽标 / 次级容器）
 *   tertiary 用于图标线
 *   error 用于失败与警告
 *   其余层级一律走 surfaceContainer 五档, 不逐组件换色、不用渐变。
 */
object ChaosPalette {
    const val SEED = 0xFF2A82E4

    /**
     * 预览里画的是**设备屏幕**，不是 App 自己的界面，所以不参与主题取色：
     * 手环是 OLED，屏幕黑底与浅色/深色模式无关，跟着 App 变色反而不像那块屏。
     */
    val SCREEN_BLACK = Color(0xFF000000)
    val SCREEN_FG = Color(0xFFFFFFFF)
    val SCREEN_FG_DIM = Color(0xB3FFFFFF)
}

/** 完整角色集, 与 ColorScheme 一一对应(缺哪个补哪个, 不让默认值悄悄接管) */
internal val LightScheme = lightColorScheme(
    primary = Color(0xFF3D5F90),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFD5E3FF),
    onPrimaryContainer = Color(0xFF234776),
    secondary = Color(0xFF555F71),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFD9E3F8),
    onSecondaryContainer = Color(0xFF3D4758),
    tertiary = Color(0xFF6E5676),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFFF8D8FF),
    onTertiaryContainer = Color(0xFF553F5D),
    error = Color(0xFFBA1A1A),
    onError = Color(0xFFFFFFFF),
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF93000A),
    background = Color(0xFFF9F9FF),
    onBackground = Color(0xFF191C20),
    surface = Color(0xFFF9F9FF),
    onSurface = Color(0xFF191C20),
    surfaceVariant = Color(0xFFE0E2EC),
    onSurfaceVariant = Color(0xFF43474E),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFF3F3FA),
    surfaceContainer = Color(0xFFEDEDF4),
    surfaceContainerHigh = Color(0xFFE7E8EE),
    surfaceContainerHighest = Color(0xFFE1E2E9),
    outline = Color(0xFF74777F),
    outlineVariant = Color(0xFFC4C6CF),
    inverseSurface = Color(0xFF2E3035),
    inverseOnSurface = Color(0xFFF0F0F7),
    inversePrimary = Color(0xFFA6C8FF),
    scrim = Color(0xFF000000),
)

internal val DarkScheme = darkColorScheme(
    primary = Color(0xFFA6C8FF),
    onPrimary = Color(0xFF03305F),
    primaryContainer = Color(0xFF234776),
    onPrimaryContainer = Color(0xFFD5E3FF),
    secondary = Color(0xFFBDC7DC),
    onSecondary = Color(0xFF273141),
    secondaryContainer = Color(0xFF3D4758),
    onSecondaryContainer = Color(0xFFD9E3F8),
    tertiary = Color(0xFFDBBDE2),
    onTertiary = Color(0xFF3E2846),
    tertiaryContainer = Color(0xFF553F5D),
    onTertiaryContainer = Color(0xFFF8D8FF),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
    errorContainer = Color(0xFF93000A),
    onErrorContainer = Color(0xFFFFDAD6),
    background = Color(0xFF111318),
    onBackground = Color(0xFFE1E2E9),
    surface = Color(0xFF111318),
    onSurface = Color(0xFFE1E2E9),
    surfaceVariant = Color(0xFF43474E),
    onSurfaceVariant = Color(0xFFC4C6CF),
    surfaceContainerLowest = Color(0xFF0C0E13),
    surfaceContainerLow = Color(0xFF191C20),
    surfaceContainer = Color(0xFF1D2024),
    surfaceContainerHigh = Color(0xFF282A2F),
    surfaceContainerHighest = Color(0xFF32353A),
    outline = Color(0xFF8D9199),
    outlineVariant = Color(0xFF43474E),
    inverseSurface = Color(0xFFE1E2E9),
    inverseOnSurface = Color(0xFF2E3035),
    inversePrimary = Color(0xFF3D5F90),
    scrim = Color(0xFF000000),
)
