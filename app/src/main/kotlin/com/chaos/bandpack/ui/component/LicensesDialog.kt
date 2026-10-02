package com.chaos.bandpack.ui.component

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.chaos.bandpack.BuildConfig
import com.chaos.bandpack.ui.theme.LocalPageTone
import com.chaos.bandpack.ui.theme.Spacing

/**
 * 开源许可页。
 *
 * 为什么必须在**应用里**有这一页, 而不是只写进仓库: MiSans 的许可要求"在软件中特别注明
 * 使用了 MiSans 字体" —— 只写在 GitHub 上对已经装了 App 的人不算履行。所以这一页列出
 * 本应用自有的 AGPL-3.0 声明与全部第三方条目, 文本直接从打包进来的 assets 读
 * (构建期从仓库根的 `THIRD_PARTY_NOTICES.md` 与 `third_party/` 同步, 不存第二份拷贝)。
 *
 * 显示规则: Markdown 的(`.md`)按格式渲染, 否则按**等宽原文**逐字显示 —— 第三方许可的
 * 正文一个字都不许变, 渲染不了也得原样给它看。两条自有声明是手写的 Markdown;
 * 资产里的三份许可文件也不是全 Markdown, 所以按是否 URL 结尾区分, 不走"试着渲染一下"。
 */
@Composable
fun LicensesDialog(onDismiss: () -> Unit) {
    val ctx = LocalContext.current
    val sections = remember { loadLicenses(ctx) }
    val tone = LocalPageTone.current

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(
            shape = MaterialTheme.shapes.extraLarge,
            color = tone.card,
            modifier = Modifier
                .fillMaxSize()
                .padding(Spacing.m),
        ) {
            Column(Modifier.padding(Spacing.l)) {
                Row(
                    Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            "开源许可",
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                            color = tone.onField,
                        )
                        Text(
                            "Chaos 制作台 ${BuildConfig.VERSION_NAME}",
                            style = MaterialTheme.typography.labelMedium,
                            color = tone.muted,
                        )
                    }
                    TextButton(onClick = onDismiss) { Text("关闭") }
                }
                HorizontalDivider(Modifier.padding(vertical = Spacing.s))

                // 条目多且长, 一律交给 LazyColumn —— 只有真 need 到的部分会组合
                LazyColumn(
                    Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(Spacing.xl),
                ) {
                    items(sections) { section -> LicenseSection(section) }
                }
            }
        }
    }
}

@Composable
private fun LicenseSection(section: License) {
    val tone = LocalPageTone.current
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
        Text(
            section.title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            color = tone.onField,
        )
        MarkdownText(
            src = section.body,
            monospace = !section.markdown,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

private data class License(
    val title: String,
    val body: String,
    /** Markdown 走渲染; 不是的话走等宽原文 */
    val markdown: Boolean,
)

/** 自有声明: Markdown, 我们自己的话, 怎么改都行 */
private val OWN_NOTICE = """
本应用的源码按 **AGPL-3.0** 发布，GNU 官方文本逐字未改（仓库根 `LICENSE`）。

本应用在本地为小米手环 10 Pro 制作字体与桌面图标投递包：**不联网、不上传、不采集**任何数据。
""".trimIndent()

/** MiSans 的"在软件中注明"那句话, 必须在界面上, 不能只在仓库里 */
private val MISANS_NOTICE = """
本应用在软件中特别注明：**预览图使用了小米的 MiSans 字体**（MiSans-Regular 的 GB2312 + ASCII 子集）。

MiSans 及其子集文件**不在**本应用的 AGPL-3.0 授权范围内，完全受《MiSans 字体知识产权许可协议》约束（全文见后）。
""".trimIndent()

private fun assetText(ctx: Context, path: String): String =
    runCatching { ctx.assets.open(path).use { String(it.readBytes(), Charsets.UTF_8) } }.getOrNull()
        ?: "（许可文本缺失: $path —— 构建时没同步进来）"

/**
 * 取 Markdown 的第一个一级标题当条目标题, 正文去掉标题那一行。
 *
 * 资产文件本来就有自己的 `# 第三方组件与许可`, 外面再写一遍标题就成了两行一样的
 * 大字 —— 让文件自己说它叫什么。没有一级标题时保持原样。
 */
private fun fromMarkdown(raw: String): License {
    val lines = raw.split('\n')
    if (lines.firstOrNull()?.startsWith("# ") == true) {
        return License(lines.first().removePrefix("# ").trim(), lines.drop(1).joinToString("\n").trimStart(), true)
    }
    return License("第三方组件与许可", raw, true)
}

private fun loadLicenses(ctx: Context): List<License> = listOf(
    License("本应用（Chaos 制作台）", OWN_NOTICE, true),
    License("使用了 MiSans 字体", MISANS_NOTICE, true),
    fromMarkdown(assetText(ctx, "legal/THIRD_PARTY_NOTICES.md")),
    // 三份许可原文都不是 Markdown, 一律逐字显示
    License("MiSans 字体知识产权许可协议", assetText(ctx, "legal/third_party/MiSans-LICENSE.txt"), false),
    License("MingCute 图标（Apache-2.0）", assetText(ctx, "licenses/mingcute-LICENSE.txt"), false),
    License("MingCute NOTICE", assetText(ctx, "licenses/mingcute-NOTICE.txt"), false),
)
