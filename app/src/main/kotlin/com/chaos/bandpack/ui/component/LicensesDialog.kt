package com.chaos.bandpack.ui.component

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
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

                LazyColumn(
                    Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(Spacing.l),
                ) {
                    items(sections.size) { i ->
                        val (title, body) = sections[i]
                        Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                            Text(
                                title,
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Bold,
                                color = tone.onField,
                            )
                            Text(
                                body,
                                style = MaterialTheme.typography.bodySmall,
                                color = tone.muted,
                            )
                        }
                    }
                }
            }
        }
    }
}

private fun assetText(ctx: Context, path: String): String =
    runCatching { ctx.assets.open(path).use { String(it.readBytes(), Charsets.UTF_8) } }.getOrNull()
        ?: "（许可文本缺失: $path —— 构建时没同步进来）"

private fun loadLicenses(ctx: Context): List<Pair<String, String>> = listOf(
    "本应用（Chaos 制作台）" to
        "源码按 AGPL-3.0 发布，GNU 官方文本逐字未改（仓库根 LICENSE）。\n" +
        "本应用在本地为小米手环 10 Pro 制作字体与图标投递包：不联网、不上传、不采集任何数据。",
    "使用了 MiSans 字体" to
        "本应用在软件中特别注明：预览图使用小米的 MiSans 字体（MiSans-Regular 的\n" +
        "GB2312+ASCII 子集）渲染。MiSans 及其子集文件不在本应用的 AGPL-3.0 授权范围内，\n" +
        "完全受《MiSans 字体知识产权许可协议》约束（全文见下一节）。",
    "第三方组件与许可（全文）" to assetText(ctx, "legal/THIRD_PARTY_NOTICES.md"),
    "MiSans 字体知识产权许可协议" to assetText(ctx, "legal/third_party/MiSans-LICENSE.txt"),
    "MingCute 图标（Apache-2.0）" to assetText(ctx, "licenses/mingcute-LICENSE.txt"),
    "MingCute NOTICE" to assetText(ctx, "licenses/mingcute-NOTICE.txt"),
)
