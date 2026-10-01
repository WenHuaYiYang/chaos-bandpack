package com.chaos.bandpack.ui.theme

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance

/**
 * 一页一套**色场**。两档风格各自算一套，界面只认这套字段。
 *
 * [ThemeStyle.PAPER]（默认）—— 参考图那套：**冷灰底 + 暖白卡**，靠明度与冷暖分层，
 *   色相只出现在小元素（头图圆片、按钮）上。所以 field 取 `background`（比卡片更暗更冷），
 *   card 取 `surface`（暖白），卡片**不再**按页面色相染。
 *
 * [ThemeStyle.MD3] —— 上一版：整页一个色相铺底，卡片是同色系再深一档。
 *   field/card/capsule 从 `surface` 往容器色插值（0.22 / 0.42 / 0.62）。
 *
 * 插值而不是直接铺 `xxxContainer`：动态取色下它可能相当深，铺满整屏正文压不住，
 * 而且换壁纸会连明度基调一起换掉。
 */
@Immutable
class PageTone(
    /** 整页底色 */
    val field: Color,
    /** 卡片与列表行 */
    val card: Color,
    /** 胶囊容器、更强的分组块 */
    val capsule: Color,
    /** 主行动作的填充（高饱和），以及它的正文色 */
    val deep: Color,
    val onDeep: Color,
    /** 色场上的正文与次要说明 */
    val onField: Color,
    val muted: Color,
    /** 这一页的识别色（容器色）与它的正文色，用在头图圆片与小徽标上 */
    val accent: Color,
    val onAccent: Color,
    val style: ThemeStyle,
) {
    /**
     * 卡片底色。两档风格在这里分道扬镳：
     *   PAPER —— 就是暖白（`card`），**不染**页面色相。参考图里的卡都是白的，
     *            颜色只出现在它内部的小元素上；染了反而失掉那套"纸感"。
     *   MD3   —— 参考图之外的上一版做法：从本行头图的颜色取一点混进卡片色，
     *            一列看下来同行之间有区别。
     */
    fun cardFor(tint: Color): Color = when (style) {
        ThemeStyle.PAPER -> card
        ThemeStyle.MD3 -> lerp(card, tint, 0.30f)
    }
}

/**
 * [seed] 取这一页的容器色，[deep] 取同一条线的实色。
 * 设置页没有自己的色相，传 `surfaceContainerHigh` 系列即可。
 */
@Composable
fun rememberPageTone(
    seed: Color,
    onSeed: Color,
    deep: Color,
    onDeep: Color,
): PageTone {
    val s = MaterialTheme.colorScheme
    val style = LocalThemeStyle.current
    return remember(s, seed, onSeed, deep, onDeep, style) {
        when (style) {
            ThemeStyle.PAPER -> PageTone(
                // 参考图的页底是冷灰、卡片是暖白 —— 卡片比页底**亮**，
                // 靠这一层明度差把卡片托起来，不靠阴影也不靠色相
                field = s.background,
                card = s.surface,
                capsule = s.surfaceContainerHigh,
                deep = s.primary,
                onDeep = s.onPrimary,
                onField = s.onBackground,
                muted = s.onSurfaceVariant,
                accent = seed,
                onAccent = onSeed,
                style = style,
            )
            ThemeStyle.MD3 -> PageTone(
                field = lerp(s.surface, seed, 0.22f),
                card = lerp(s.surface, seed, 0.42f),
                capsule = lerp(s.surface, seed, 0.62f),
                deep = deep,
                onDeep = onDeep,
                onField = s.onSurface,
                muted = s.onSurfaceVariant,
                accent = seed,
                onAccent = onSeed,
                style = style,
            )
        }
    }
}

/** 由外壳按当前去处提供，组件直接取，不再一层层传参数 */
val LocalPageTone = androidx.compose.runtime.compositionLocalOf<PageTone> {
    error("LocalPageTone 没被提供: 页面必须挂在 ChaosApp 的外壳里")
}

/**
 * 给定一块**背景色**，返回在它上面一定读得出来的前景色。
 *
 * 为什么需要：动态取色下 `secondaryContainer` 可能是浅色也可能是中深色，而它的配套
 * `onSecondaryContainer` 只保证在**它自己**上可读，一旦我们把容器色又跟别的颜色混过一次，
 * 那个保证就没了 —— 本项目在这里栽过两回（样张白底白字、四个格子全空）。
 *
 * 判据用相对亮度而不是"猜当前是深色还是浅色模式"。注意**不能**写成"暗底就用 `surface`
 * 当浅墨" —— 深色模式下 `surface` 自己就是暗的，那样等于暗底配暗字。所以先在 `surface`
 * 与 `onSurface` 两个角色里按亮度分出"本主题的浅墨与深墨"，再按背景亮度挑一个。
 */
fun Color.inkOn(s: ColorScheme): Color {
    val lightInk = if (s.surface.luminance() > s.onSurface.luminance()) s.surface else s.onSurface
    val darkInk = if (lightInk == s.surface) s.onSurface else s.surface
    return if (luminance() > 0.45f) darkInk else lightInk
}
