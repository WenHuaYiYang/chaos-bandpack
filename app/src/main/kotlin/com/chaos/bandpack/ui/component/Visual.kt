package com.chaos.bandpack.ui.component

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.chaos.bandpack.ui.theme.LocalPageTone
import com.chaos.bandpack.ui.theme.Spacing
import com.chaos.bandpack.ui.theme.tabular

/**
 * 视觉控件三件套。设计取向: **少文字、多控件** —— 人是视觉动物,
 * 一屏全是句子就读不下去。所以:
 *
 *   - 成片的"键 值"文字行 -> [StatChip](图标 + 大数字 + 小标签, 扫一眼就完);
 *   - "选好以后这里会出现……"这种解释句 -> [EmptyState](大图标 + 一句短标题 + 按钮);
 *   - 警告与错误 -> [HintBar](色底 + 图标, 这类文字**不能省**, 但要有容器而不是裸奔)。
 *
 * 注意: 可点元素的文字标签一律保留 —— 为了"看起来干净"把标签删掉是反模式,
 * 可用性会直接掉下来。这里砍掉的只有解释性散文。
 */

/**
 * 数值小票: 图标 + 值(强) + 标签(弱), **收成胶囊**。
 *
 * 参考图里同类信息("44.1 kHz · 320 kbps · MP3"那种)一律是一条胶囊而不是一块圆角矩形,
 * 胶囊在一堆圆角矩形之间也给了需要的形状对比。
 *
 * 底色不写死中性 `surfaceContainerHigh`, 也不直接用 `xxxContainer`: 前者在色场上读成灰块,
 * 后者在动态取色下可能相当深, 一屏摆五六张就把版面压死了(两种都在截图里出现过)。
 * 改成"本页色场往实色拉一点" —— 同色系、比底深一档, 深浅色与换壁纸都成立。
 * 需要额外强调时(错误、已选)由调用方显式传 container/content。
 */
@Composable
fun StatChip(
    icon: Painter,
    value: String,
    label: String,
    modifier: Modifier = Modifier,
    container: Color = lerp(LocalPageTone.current.field, LocalPageTone.current.deep, 0.10f),
    content: Color = LocalPageTone.current.onField,
) {
    val tone = LocalPageTone.current
    Surface(
        modifier = modifier,
        shape = CircleShape,
        color = container,
        contentColor = content,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = Spacing.m, vertical = Spacing.s),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = tone.muted,
                modifier = Modifier.size(22.dp),
            )
            Spacer(Modifier.width(Spacing.s))
            Column {
                Text(
                    value,
                    style = MaterialTheme.typography.titleSmall.tabular(),
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    label,
                    style = MaterialTheme.typography.labelSmall,
                    color = tone.muted,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/**
 * 空状态: 大号图标圆片 + 一句短标题 + 动作。用来替掉"还没有 X，去做 Y"这类整段说明。
 * 整块可点([onClick] 非空时), 这样"选文件"这件事在界面上是一大片目标而不是右下角一个小按钮。
 */
@Composable
fun EmptyState(
    icon: Painter,
    title: String,
    hint: String? = null,
    actionLabel: String,
    onAction: () -> Unit,
) {
    val tone = LocalPageTone.current
    Surface(
        onClick = onAction,
        shape = MaterialTheme.shapes.extraLarge,
        // 卡体取色场的同色系, 不用近白的 surfaceContainerLow: 近白大板落在色场上
        // 是一块"外来物", 而且它一屏往往还是最大的一块, 直接把色场压没了。
        color = tone.card,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Spacing.xl, vertical = Spacing.xxl),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                modifier = Modifier
                    .size(64.dp)
                    .clip(CircleShape)
                    .background(tone.capsule),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = tone.onField, modifier = Modifier.size(30.dp))
            }
            Spacer(Modifier.height(Spacing.m))
            Text(title, style = MaterialTheme.typography.titleMedium, color = tone.onField)
            if (hint != null) {
                Spacer(Modifier.height(Spacing.xs))
                Text(
                    hint,
                    style = MaterialTheme.typography.bodyMedium,
                    color = tone.muted,
                    textAlign = TextAlign.Center,
                    maxLines = 2,
                )
            }
            Spacer(Modifier.height(Spacing.l))
            // 空状态里的动作是这张页眼下唯一的主动作, 所以给它实色胶囊 ——
            // 同屏还有一枚禁用的导出胶囊, 两个都灰就没有主次了
            Row(
                Modifier
                    .clip(CircleShape)
                    .background(tone.deep)
                    .clickable(onClick = onAction)
                    .padding(horizontal = Spacing.xl, vertical = Spacing.m),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    actionLabel,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = tone.onDeep,
                )
            }
        }
    }
}

/** 提示条: 图标 + 一段必要的话。错误走 errorContainer, 常规提示走 tertiaryContainer。 */
@Composable
fun HintBar(
    icon: Painter,
    text: String,
    error: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    val container = if (error) scheme.errorContainer else scheme.tertiaryContainer
    val fg = if (error) scheme.onErrorContainer else scheme.onTertiaryContainer
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = container,
        contentColor = fg,
    ) {
        Row(
            modifier = Modifier.padding(Spacing.l),
            verticalAlignment = Alignment.Top,
        ) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(Spacing.m))
            Text(text, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

/** 一行小标题(节标题的轻量版): 用在色底小票上方, 代替整段说明。 */
@Composable
fun ChipRowLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(bottom = Spacing.s),
    )
}

/** 两个色块图例: 让"哪种格子是什么状态"用眼睛认, 不靠写一句话。 */
@Composable
fun LegendSwatch(
    label: String,
    swatch: @Composable () -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        swatch()
        Spacer(Modifier.width(Spacing.s))
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** 横向排列、放不下就换行的容器(小票条用)。 */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun ChipFlow(content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    androidx.compose.foundation.layout.FlowRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(Spacing.s),
        verticalArrangement = Arrangement.spacedBy(Spacing.s),
        content = content,
    )
}
