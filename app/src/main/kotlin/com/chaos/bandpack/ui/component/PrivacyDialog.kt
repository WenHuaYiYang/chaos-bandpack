package com.chaos.bandpack.ui.component

import android.app.Activity
import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.graphics.drawable.toBitmap
import com.chaos.bandpack.ui.theme.LocalPageTone
import com.chaos.bandpack.ui.theme.Spacing
import com.chaos.bandpack.ui.theme.rememberPageTone

/**
 * 隐私政策:首启同意页 + 随时回看弹层。
 *
 * 为什么做成"全屏门"而不是普通弹窗:工信部规范要求首启先告知并取得同意才能用;
 * 政策全文直接渲染在页里(不跳外部链接 —— 本应用没有网络权限, 也不该有)。
 * 同意记录在 UiPrefs(privacy_agreed_v1), 键名带版本, 政策大改时升版本重新征求。
 *
 * 为什么这里要**自己提供 LocalPageTone**:同意门挂在 ChaosApp 外壳之外, 外壳发给各页的
 * tone 到不了这里; 而本项目组件(MarkdownText 等)都会读 tone。所以按设置页那套"中性色场"
 * 造一份提供下去 —— 同意门的长相与设置页一致, 组件也都能工作。
 */

/** 政策全文从 assets 读(构建期从仓库根 PRIVACY_POLICY.md 同步, 不存第二份拷贝) */
private fun loadPrivacyPolicy(ctx: Context): String =
    runCatching {
        ctx.assets.open("legal/privacy_policy.md").bufferedReader().use { it.readText() }
    }.getOrElse {
        // 万一资产缺失: 把最要紧的三句直接给用户, 不能让"看不到政策"卡死首启
        "隐私政策全文加载失败，要点如下：" +
            "本应用不联网（未申请网络权限）、不申请任何 Android 权限、不收集任何个人信息；" +
            "你选择的文件只在本机处理，导出的文件由你自行管理；卸载即删除全部本地数据。"
    }

/** 首启同意页。未同意前 [ChaosApp] 不渲染任何业务界面。 */
@Composable
fun PrivacyConsentGate(
    onAgree: () -> Unit,
) {
    val ctx = LocalContext.current
    val policy = remember { loadPrivacyPolicy(ctx) }
    var declined by remember { mutableStateOf(false) }

    val s = MaterialTheme.colorScheme
    val tone = rememberPageTone(s.surfaceContainerHigh, s.onSurface, s.primary, s.onPrimary)
    CompositionLocalProvider(LocalPageTone provides tone) {
        if (declined) {
            // 拒绝页: 不能用, 但随时可以回看政策再同意; 退出走 finishAffinity。
            // 视觉贴应用的纸感语言: 冷灰底 + 暖白卡, 图标砖用真 launcher 图标。
            val iconBitmap = remember {
                runCatching {
                    ctx.packageManager.getApplicationIcon(ctx.packageName)
                        .toBitmap(192, 192).asImageBitmap()
                }.getOrNull()
            }
            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                Column(
                    Modifier
                        .fillMaxSize()
                        .windowInsetsPadding(WindowInsets.safeDrawing)
                        .padding(Spacing.xxl),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Surface(
                        shape = androidx.compose.foundation.shape.RoundedCornerShape(26.dp),
                        color = tone.card,
                        border = androidx.compose.foundation.BorderStroke(
                            1.5.dp, MaterialTheme.colorScheme.outlineVariant,
                        ),
                        shadowElevation = 2.dp,
                        modifier = Modifier.size(112.dp),
                    ) {
                        iconBitmap?.let {
                            androidx.compose.foundation.Image(
                                bitmap = it,
                                contentDescription = null,
                                modifier = Modifier.padding(16.dp),
                            )
                        }
                    }
                    Spacer(Modifier.height(Spacing.l))
                    Surface(
                        shape = androidx.compose.foundation.shape.RoundedCornerShape(28.dp),
                        color = tone.card,
                        shadowElevation = 2.dp,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(
                            Modifier.padding(horizontal = Spacing.xxl, vertical = Spacing.xl),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Text(
                                "未同意《隐私政策》",
                                style = MaterialTheme.typography.headlineSmall,
                                fontWeight = FontWeight.Bold,
                                color = tone.onField,
                            )
                            Spacer(Modifier.height(Spacing.s))
                            Text(
                                "本应用需要你同意《隐私政策》后才能使用。\n你可以随时重新查看并同意。",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                textAlign = TextAlign.Center,
                            )
                            Spacer(Modifier.height(Spacing.xl))
                            Button(
                                onClick = { declined = false },
                                modifier = Modifier.fillMaxWidth(),
                            ) { Text("重新查看政策") }
                            Spacer(Modifier.height(Spacing.s))
                            OutlinedButton(
                                onClick = { (ctx as? Activity)?.finishAffinity() },
                                modifier = Modifier.fillMaxWidth(),
                            ) { Text("退出应用") }
                        }
                    }
                }
            }
        } else {
            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
                Column(
                    Modifier
                        .fillMaxSize()
                        .windowInsetsPadding(WindowInsets.safeDrawing)
                        .padding(horizontal = Spacing.l, vertical = Spacing.l),
                ) {
                    // 头部: 图标砖 + 欢迎语。裸文字标题太素, 品牌脸面用与拒绝页同一块"砖"
                    val iconBitmap = remember {
                        runCatching {
                            ctx.packageManager.getApplicationIcon(ctx.packageName)
                                .toBitmap(192, 192).asImageBitmap()
                        }.getOrNull()
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Surface(
                            shape = androidx.compose.foundation.shape.RoundedCornerShape(20.dp),
                            color = tone.card,
                            border = androidx.compose.foundation.BorderStroke(
                                1.5.dp, MaterialTheme.colorScheme.outlineVariant,
                            ),
                            shadowElevation = 2.dp,
                            modifier = Modifier.size(64.dp),
                        ) {
                            iconBitmap?.let {
                                androidx.compose.foundation.Image(
                                    bitmap = it,
                                    contentDescription = null,
                                    modifier = Modifier.padding(10.dp),
                                )
                            }
                        }
                        Spacer(Modifier.width(Spacing.l))
                        Column {
                            Text(
                                "欢迎使用",
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                "Chaos 制作台",
                                style = MaterialTheme.typography.titleLarge,
                                fontWeight = FontWeight.Bold,
                            )
                        }
                    }

                    Spacer(Modifier.height(Spacing.m))

                    // 政策全文: 可滚动, Markdown 渲染(与许可页同一套组件)。
                    // 要点卡不要了 —— 政策全文就在下面, 重复堆文字反而是负担。
                    Surface(
                        shape = MaterialTheme.shapes.large,
                        color = tone.card,
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth(),
                    ) {
                        Column(
                            Modifier
                                .verticalScroll(rememberScrollState())
                                .padding(Spacing.l),
                        ) {
                            MarkdownText(src = policy)
                        }
                    }

                    Spacer(Modifier.height(Spacing.m))
                    Row(Modifier.fillMaxWidth()) {
                        OutlinedButton(
                            onClick = { declined = true },
                            modifier = Modifier.weight(1f),
                        ) { Text("不同意") }
                        Spacer(Modifier.width(Spacing.m))
                        Button(
                            onClick = onAgree,
                            modifier = Modifier.weight(2f),
                        ) { Text("同意并继续") }
                    }
                    Spacer(Modifier.height(Spacing.s))
                    Text(
                        "点击「同意并继续」即表示你已阅读并同意《隐私政策》全部内容。",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

/** 设置页随时回看的政策全文(挂在 ChaosApp 外壳之内, tone 由外壳提供) */
@Composable
fun PrivacyPolicyDialog(
    onDismiss: () -> Unit,
) {
    val ctx = LocalContext.current
    val tone = LocalPageTone.current
    val policy = remember { loadPrivacyPolicy(ctx) }

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
                            "隐私政策",
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                            color = tone.onField,
                        )
                    }
                    TextButton(onClick = onDismiss) { Text("关闭") }
                }
                androidx.compose.material3.HorizontalDivider(Modifier.padding(vertical = Spacing.s))

                Column(
                    Modifier
                        .weight(1f)
                        .verticalScroll(rememberScrollState()),
                ) {
                    MarkdownText(src = policy)
                }
            }
        }
    }
}
