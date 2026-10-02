package com.chaos.bandpack.ui.component

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chaos.bandpack.data.markdown.MdBlock
import com.chaos.bandpack.data.markdown.MdInline
import com.chaos.bandpack.data.markdown.parseInlines
import com.chaos.bandpack.data.markdown.parseMarkdown
import com.chaos.bandpack.ui.theme.LocalPageTone
import com.chaos.bandpack.ui.theme.Spacing

/**
 * 一小把 Markdown 的 Compose 渲染, 只服务于应用内的许可与声明文本。
 *
 * 取舍是**保守**: 认不出来的写法按正文原样显示, 不在渲染侧做发挥。解析交给
 * [parseMarkdown], 这里只管排版; 颜色一律从 [LocalPageTone] 与 MaterialTheme 取,
 * 跟着现有主题走。
 *
 * 解析失败([parseMarkdown] 抛了)时整段退成**等宽原文**: 第三方许可的正文一个字符都
 * 不许变, 宁可显示得难看, 也不能不显示。回退入口在 [MarkdownText]。
 */
@Composable
fun MarkdownBlocks(
    blocks: List<MdBlock>,
    modifier: Modifier = Modifier,
) {
    // 点击链接会调 LocalUriHandler, 换掉它就把整棵子树的"开链接"行为收住了:
    // 只放行 http/https, javascript: / file: 之类一律不开。
    val safe = rememberSafeUriHandler()
    val linkColor = MaterialTheme.colorScheme.primary
    CompositionLocalProvider(LocalUriHandler provides safe) {
        Column(
            modifier = modifier,
            verticalArrangement = Arrangement.spacedBy(Spacing.m),
        ) {
            blocks.forEach { block ->
                when (block) {
                    is MdBlock.Heading -> MdHeading(block, linkColor)
                    is MdBlock.Paragraph -> MdParagraph(block.inlines, linkColor)
                    is MdBlock.ListBlock -> MdList(block, linkColor)
                    is MdBlock.Quote -> MdQuote(block, linkColor)
                    is MdBlock.CodeBlock -> MdCode(block)
                    is MdBlock.Table -> MdTable(block, linkColor)
                    MdBlock.Divider -> HorizontalDivider(Modifier.padding(vertical = Spacing.s))
                }
            }
        }
    }
}

/**
 * 一段 Markdown 文本: 解析 + 渲染, 解析失败自动退回原文。
 *
 * [monospace] 用于本来就不是 Markdown 的许可正文(.txt): 那种本来就不需要渲染,
 * 但必须保持逐字原样, 用等宽加上横竖滚动读起来才不别扭。
 */
@Composable
fun MarkdownText(
    src: String,
    modifier: Modifier = Modifier,
    monospace: Boolean = false,
) {
    val blocks = remember(src) { runCatching { parseMarkdown(src) }.getOrNull() }
    val tone = LocalPageTone.current
    if (blocks == null || monospace) {
        // 回退 / 非 Markdown: 原文逐字显示, 代码块左右可滑, 整块跟着页面滚
        if (monospace) {
            Text(
                src,
                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 16.sp, fontFamily = FontFamily.Monospace),
                color = tone.onField,
                softWrap = false,
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
            )
        } else {
            Text(src, style = MaterialTheme.typography.bodyLarge.copy(fontSize = 18.sp, lineHeight = 30.sp), color = tone.onField, modifier = modifier)
        }
        return
    }
    MarkdownBlocks(blocks, modifier)
}

@Composable
private fun rememberSafeUriHandler(): UriHandler {
    val ctx = LocalContext.current
    return remember(ctx) {
        object : UriHandler {
            override fun openUri(uri: String) {
                val parsed = runCatching { Uri.parse(uri) }.getOrNull() ?: return
                val scheme = parsed.scheme?.lowercase() ?: return
                if (scheme != "http" && scheme != "https") return
                val intent = Intent(Intent.ACTION_VIEW, parsed)
                    .addCategory(Intent.CATEGORY_BROWSABLE)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                runCatching { ctx.startActivity(intent) }
            }
        }
    }
}

@Composable
private fun MdHeading(block: MdBlock.Heading, linkColor: Color) {
    val tone = LocalPageTone.current
    val (style, top) = when (block.level) {
        1 -> MaterialTheme.typography.headlineSmall.copy(fontSize = 30.sp, lineHeight = 38.sp) to Spacing.xl
        2 -> MaterialTheme.typography.titleLarge.copy(fontSize = 26.sp, lineHeight = 34.sp) to Spacing.l
        3 -> MaterialTheme.typography.titleLarge.copy(fontSize = 22.sp, lineHeight = 30.sp) to Spacing.m
        else -> MaterialTheme.typography.titleMedium.copy(fontSize = 20.sp, lineHeight = 28.sp) to Spacing.s
    }
    Text(
        text = buildAnnotated(block.inlines, linkColor),
        style = style,
        fontWeight = FontWeight.Bold,
        color = tone.onField,
        modifier = Modifier.padding(top = top),
    )
}

@Composable
private fun MdParagraph(inlines: List<MdInline>, linkColor: Color) {
    val tone = LocalPageTone.current
    Text(buildAnnotated(inlines, linkColor), style = MaterialTheme.typography.bodyLarge.copy(fontSize = 18.sp, lineHeight = 30.sp), color = tone.onField)
}

@Composable
private fun MdList(block: MdBlock.ListBlock, linkColor: Color) {
    val tone = LocalPageTone.current
    val parsed = remember(block) { block.items.map { parseInlines(it.text) } }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        block.items.forEachIndexed { idx, item ->
            Row(Modifier.padding(start = Spacing.l * (item.depth + 1))) {
                Text(
                    if (block.ordered) "${block.startAt + idx}. " else "• ",
                    style = MaterialTheme.typography.bodyLarge,
                    color = tone.onField,
                )
                Text(
                    buildAnnotated(parsed[idx], linkColor),
                    style = MaterialTheme.typography.bodyLarge,
                    color = tone.onField,
                )
            }
        }
    }
}

@Composable
private fun MdQuote(block: MdBlock.Quote, linkColor: Color) {
    val tone = LocalPageTone.current
    Surface(
        shape = RoundedCornerShape(Spacing.s),
        color = tone.capsule,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row {
            // 竖线是引用唯一的标记; 正文用弱色, 别让引用比正文还抢眼
            Spacer(Modifier.width(2.dp).background(tone.accent))
            Column(
                Modifier.padding(start = Spacing.m, end = Spacing.s, top = Spacing.s, bottom = Spacing.s),
                verticalArrangement = Arrangement.spacedBy(Spacing.xs),
            ) {
                block.paragraphs.forEach {
                    Text(
                        buildAnnotated(it, linkColor),
                        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 18.sp, lineHeight = 30.sp),
                        color = tone.muted,
                    )
                }
            }
        }
    }
}

@Composable
private fun MdCode(block: MdBlock.CodeBlock) {
    val tone = LocalPageTone.current
    Surface(
        shape = RoundedCornerShape(Spacing.s),
        color = tone.capsule,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(
            block.code,
            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 16.sp, fontFamily = FontFamily.Monospace),
            color = tone.onField,
            softWrap = false,
            modifier = Modifier
                .horizontalScroll(rememberScrollState())
                .padding(Spacing.m),
        )
    }
}

@Composable
private fun MdTable(block: MdBlock.Table, linkColor: Color) {
    val tone = LocalPageTone.current
    val cols = block.header.size
    Column(Modifier.fillMaxWidth()) {
        Row {
            block.header.forEachIndexed { i, cell ->
                Text(
                    buildAnnotated(cell, linkColor),
                    style = MaterialTheme.typography.bodyMedium.copy(fontSize = 16.sp),
                    fontWeight = FontWeight.Bold,
                    color = tone.onField,
                    modifier = Modifier.weight(1f).padding(end = if (i == cols - 1) 0.dp else Spacing.s),
                )
            }
        }
        HorizontalDivider(Modifier.padding(vertical = Spacing.xs))
        block.rows.forEach { row ->
            Row(Modifier.padding(bottom = Spacing.xs)) {
                for (i in 0 until cols) {
                    Text(
                        buildAnnotated(row.getOrNull(i) ?: emptyList(), linkColor),
                        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 16.sp),
                        color = tone.muted,
                        modifier = Modifier.weight(1f).padding(end = if (i == cols - 1) 0.dp else Spacing.s),
                    )
                }
            }
        }
    }
}

@Composable
private fun buildAnnotated(inlines: List<MdInline>, linkColor: Color): AnnotatedString {
    val linkStyle = SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline)
    return remember(inlines, linkColor) {
        buildAnnotatedString { appendInlines(inlines, linkStyle) }
    }
}

private fun AnnotatedString.Builder.appendInlines(inlines: List<MdInline>, linkStyle: SpanStyle) {
    for (i in inlines) {
        when (i) {
            is MdInline.Text -> append(i.text)
            is MdInline.CodeSpan -> withStyle(SpanStyle(fontFamily = FontFamily.Monospace)) { append(i.code) }
            is MdInline.Strong -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { appendInlines(i.children, linkStyle) }
            is MdInline.Emphasis -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { appendInlines(i.children, linkStyle) }
            is MdInline.Link -> {
                pushStyle(linkStyle)
                withLink(LinkAnnotation.Url(i.url)) { appendInlines(i.children, linkStyle) }
                pop()
            }
        }
    }
}
