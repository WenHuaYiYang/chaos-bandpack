package com.chaos.bandpack.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * 新主题（默认）的色板与形状。
 *
 * 颜色不是拍的，是**从用户给的参考图里采样出来的**（取众数，避开照片与抗锯齿边）：
 *
 *   页底   #F1F1F1  冷灰
 *   卡片   #FCFBF9  暖白 —— 注意不是纯白，比页底暖
 *   蓝     #4890CC  柔和的中蓝（主色）
 *   鼠尾草 #7E9C90  低饱和绿（次色）
 *   蜜桃   #D89C84  陶土/蜜桃（第三色）
 *
 * 这套的骨架与 MD3 那套**不一样**：MD3 档是"整页色场 + 同色系卡片"，
 * 这里是"冷灰底 + 暖白卡 + 粉彩强调"，靠明度与冷暖分层而不是靠色相铺底。
 * 所以两者共用同一份 `ColorScheme` 接口，但角色的取值逻辑不同。
 *
 * 强调色在正文/图标上要压深一档才够对比度（采样的原值都偏浅，直接当 primary 用会读不清），
 * 所以每个强调色给"实色"与"容器色"两档：实色用于图标与文字，容器色用于底衬。
 */
object PaperPalette {

    // ---- 采样原值（参考图） ----
    val Page: Color = Color(0xFFF1F1F1)
    val Card: Color = Color(0xFFFCFBF9)
    val Blue: Color = Color(0xFF4890CC)
    val Sage: Color = Color(0xFF7E9C90)
    val Peach: Color = Color(0xFFD89C84)

    // ---- 深色档：把上面三个强调色提亮降饱和，底换成暖黑 ----
    private val PageDark: Color = Color(0xFF121212)
    private val CardDark: Color = Color(0xFF1D1C1B)
    private val BlueDark: Color = Color(0xFF9CC7EC)
    private val SageDark: Color = Color(0xFFAEC7BC)
    private val PeachDark: Color = Color(0xFFE8BCA8)

    val Light: ColorScheme = lightColorScheme(
        primary = Color(0xFF3E86C4),
        onPrimary = Color(0xFFFFFFFF),
        primaryContainer = Color(0xFFDCEBFA),
        onPrimaryContainer = Color(0xFF0E2C44),

        secondary = Color(0xFF5F7F73),
        onSecondary = Color(0xFFFFFFFF),
        secondaryContainer = Color(0xFFDCE8E3),
        onSecondaryContainer = Color(0xFF1B2C26),

        tertiary = Color(0xFFB87A5F),
        onTertiary = Color(0xFFFFFFFF),
        tertiaryContainer = Color(0xFFF7E3DA),
        onTertiaryContainer = Color(0xFF3D2418),

        error = Color(0xFFB3261E),
        onError = Color(0xFFFFFFFF),
        errorContainer = Color(0xFFF9DEDC),
        onErrorContainer = Color(0xFF410E0B),

        background = Page,
        onBackground = Color(0xFF1C1B1A),
        surface = Card,
        onSurface = Color(0xFF1C1B1A),
        surfaceVariant = Color(0xFFE9E6E2),
        onSurfaceVariant = Color(0xFF4A4744),
        outline = Color(0xFF8A8580),
        outlineVariant = Color(0xFFDCD8D3),

        // 五档容器：暖中性阶梯（参考图里卡片是暖白、页底是冷灰，这里是中间那几档）
        surfaceContainerLowest = Color(0xFFFFFFFF),
        surfaceContainerLow = Color(0xFFF7F5F3),
        surfaceContainer = Color(0xFFF2F0EE),
        surfaceContainerHigh = Color(0xFFECE9E6),
        surfaceContainerHighest = Color(0xFFE6E3DF),
    )

    val Dark: ColorScheme = darkColorScheme(
        primary = BlueDark,
        onPrimary = Color(0xFF0B2438),
        primaryContainer = Color(0xFF1E4A6B),
        onPrimaryContainer = Color(0xFFD3E7F8),

        secondary = SageDark,
        onSecondary = Color(0xFF17251F),
        secondaryContainer = Color(0xFF324A41),
        onSecondaryContainer = Color(0xFFDCE8E3),

        tertiary = PeachDark,
        onTertiary = Color(0xFF33201A),
        tertiaryContainer = Color(0xFF5A3B2C),
        onTertiaryContainer = Color(0xFFF7E3DA),

        error = Color(0xFFF2B8B5),
        onError = Color(0xFF601410),
        errorContainer = Color(0xFF8C1D18),
        onErrorContainer = Color(0xFFF9DEDC),

        background = PageDark,
        onBackground = Color(0xFFEDE9E6),
        surface = CardDark,
        onSurface = Color(0xFFEDE9E6),
        surfaceVariant = Color(0xFF3A3835),
        onSurfaceVariant = Color(0xFFB6B0AA),
        outline = Color(0xFF8A8580),
        outlineVariant = Color(0xFF43403D),

        surfaceContainerLowest = Color(0xFF0D0D0C),
        surfaceContainerLow = Color(0xFF1A1918),
        surfaceContainer = Color(0xFF201F1E),
        surfaceContainerHigh = Color(0xFF2A2928),
        surfaceContainerHighest = Color(0xFF353331),
    )

    /**
     * 形状：参考图的卡圆角比 MD3 档更收一点（大卡约 22~24dp），整体是"软而不圆"。
     * 不做成 pill —— 满屏 pill 会把界面变软糖，那是另一套语言。
     */
    val Shapes: Shapes = Shapes(
        extraSmall = RoundedCornerShape(8.dp),
        small = RoundedCornerShape(12.dp),
        medium = RoundedCornerShape(16.dp),
        large = RoundedCornerShape(20.dp),
        extraLarge = RoundedCornerShape(24.dp),
    )
}
