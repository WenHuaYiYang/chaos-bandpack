package com.chaos.bandpack.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * 字阶: 以 M3 默认字阶为骨架, 只改**四处**有明确理由的地方, 不整表重写:
 *   1. displaySmall / headlineSmall / titleLarge 收字重与字距 —— 页面标题的"强调"靠字重,
 *      不靠继续放大字号(过大的标题是最典型的 AI UI 特征);
 *   2. 中文行高: body 两档统一 1.5 倍字号(M3 默认按拉丁文排版, 中文会挤);
 *   3. label 两档加字距: 小号全大写/短标签的可读性;
 *   4. 数字: 见 [tabular] —— 统计值一律等宽数字, 保证两列对齐。
 */
internal val ChaosTypography: Typography = Typography().let { b ->
    b.copy(
        displaySmall = b.displaySmall.copy(
            fontWeight = FontWeight.SemiBold,
            letterSpacing = (-0.4).sp,
        ),
        headlineSmall = b.headlineSmall.copy(fontWeight = FontWeight.SemiBold),
        titleLarge = b.titleLarge.copy(
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.sp,
        ),
        titleMedium = b.titleMedium.copy(fontWeight = FontWeight.Medium),
        bodyLarge = b.bodyLarge.copy(lineHeight = 25.sp),
        bodyMedium = b.bodyMedium.copy(lineHeight = 21.sp),
        bodySmall = b.bodySmall.copy(lineHeight = 17.sp),
        labelLarge = b.labelLarge.copy(
            fontWeight = FontWeight.Medium,
            letterSpacing = 0.5.sp,
        ),
        labelSmall = b.labelSmall.copy(letterSpacing = 0.4.sp),
    )
}

/** 等宽数字(+ 表格数字特性): 统计值用它, 数字列才对得齐 */
fun TextStyle.tabular(): TextStyle = copy(fontFeatureSettings = "tnum")
