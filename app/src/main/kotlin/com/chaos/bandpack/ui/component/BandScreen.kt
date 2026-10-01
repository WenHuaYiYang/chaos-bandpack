package com.chaos.bandpack.ui.component

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.unit.dp
import com.chaos.bandpack.ui.theme.ChaosPalette

/**
 * 手环屏幕的**设备外框**, 用来把预览画成"上手后的样子", 而不是一个带边框的文本框。
 *
 * 表体走 `surfaceContainer`(是 App 里的一个物体, 该跟着主题), 屏幕走纯黑
 * (见 [ChaosPalette.SCREEN_BLACK]: OLED 黑底不随深浅色模式变, 跟着变反而不像那块屏)。
 *
 * 比例按小米手环 10 Pro 那条长圆角屏近似, 是**示意**不是像素级还原 ——
 * 目的是让人看清字在屏上有多大、图标排下来是什么密度。
 */
@Composable
fun BandScreenFrame(
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    val caseShape: Shape = RoundedCornerShape(40.dp)
    val screenShape: Shape = RoundedCornerShape(32.dp)
    Box(
        modifier = modifier
            .width(152.dp)
            .aspectRatio(0.76f)
            .clip(caseShape)
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .padding(9.dp)
            .clip(screenShape)
            .background(ChaosPalette.SCREEN_BLACK),
        contentAlignment = Alignment.Center,
        content = content,
    )
}

/** 屏幕内容通用容器: 铺满 + 内边距, 前景用屏幕白而不是主题色 */
@Composable
fun BandScreenContent(content: @Composable BoxScope.() -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp, vertical = 14.dp),
        contentAlignment = Alignment.TopStart,
        content = content,
    )
}
