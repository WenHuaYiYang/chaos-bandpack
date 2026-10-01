package com.chaos.bandpack.ui.theme

import com.materialkolor.dynamiccolor.ColorSpec
import com.materialkolor.dynamiccolor.DynamicColor
import com.materialkolor.dynamiccolor.MaterialDynamicColors
import com.materialkolor.hct.Hct
import com.materialkolor.scheme.DynamicScheme
import com.materialkolor.scheme.SchemeTonalSpot
import org.junit.Test

/**
 * 品牌回退色板的**生成器**（不是断言测试）。
 *
 * 为什么要有这个文件: `Color.kt` 里那两套静态色板不是手调的近似值, 而是用官方
 * material-color-utilities 算法（MaterialKolor 的 KMP 移植）从品牌种子色
 * `#2A82E4`（chaos.png 的主蓝）算出来的 —— TonalSpot 方案、对比度 0、SPEC_2021。
 * 换品牌色/换方案时重跑这个测试, 把打印结果贴回 `Color.kt` 即可, 不引入运行时依赖。
 *
 * 运行: `./gradlew :app:testDebugUnitTest --tests '*ColorSchemeGenerationTest*' -i`
 */
class ColorSchemeGenerationTest {

    @Test
    fun `打印 Chaos 品牌的完整色板`() {
        val seed = 0xFF2A82E4.toInt()
        for (dark in listOf(false, true)) {
            val scheme = SchemeTonalSpot(
                Hct.fromInt(seed),
                dark,
                0.0,
                ColorSpec.SpecVersion.SPEC_2021,
                DynamicScheme.Platform.PHONE,
            )
            val m = MaterialDynamicColors()
            println("===== ${if (dark) "DARK" else "LIGHT"} (seed 0x2A82E4) =====")
            fun p(name: String, c: DynamicColor) {
                println("%-22s Color(0x%08X)".format(name, c.getArgb(scheme)))
            }
            p("primary", m.primary())
            p("onPrimary", m.onPrimary())
            p("primaryContainer", m.primaryContainer())
            p("onPrimaryContainer", m.onPrimaryContainer())
            p("secondary", m.secondary())
            p("onSecondary", m.onSecondary())
            p("secondaryContainer", m.secondaryContainer())
            p("onSecondaryContainer", m.onSecondaryContainer())
            p("tertiary", m.tertiary())
            p("onTertiary", m.onTertiary())
            p("tertiaryContainer", m.tertiaryContainer())
            p("onTertiaryContainer", m.onTertiaryContainer())
            p("error", m.error())
            p("onError", m.onError())
            p("errorContainer", m.errorContainer())
            p("onErrorContainer", m.onErrorContainer())
            p("background", m.background())
            p("onBackground", m.onBackground())
            p("surface", m.surface())
            p("onSurface", m.onSurface())
            p("surfaceVariant", m.surfaceVariant())
            p("onSurfaceVariant", m.onSurfaceVariant())
            p("surfaceContainerLowest", m.surfaceContainerLowest())
            p("surfaceContainerLow", m.surfaceContainerLow())
            p("surfaceContainer", m.surfaceContainer())
            p("surfaceContainerHigh", m.surfaceContainerHigh())
            p("surfaceContainerHighest", m.surfaceContainerHighest())
            p("outline", m.outline())
            p("outlineVariant", m.outlineVariant())
            p("inverseSurface", m.inverseSurface())
            p("inverseOnSurface", m.inverseOnSurface())
            p("inversePrimary", m.inversePrimary())
            p("scrim", m.scrim())
        }
    }
}
