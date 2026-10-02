package com.chaos.bandpack.ui.screen

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll

import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chaos.bandpack.data.font.Charset
import com.chaos.bandpack.data.font.FontSubset
import com.chaos.bandpack.data.make.FontMake
import com.chaos.bandpack.data.make.PackMake
import com.chaos.bandpack.data.pack.FontPackBuilder
import com.chaos.bandpack.data.pack.ShellBuilder
import com.chaos.bandpack.data.pack.truncateBytes
import com.chaos.bandpack.data.pack.TitleText
import com.chaos.bandpack.ui.LocalWidthClass
import com.chaos.bandpack.ui.component.BandScreenContent
import com.chaos.bandpack.ui.component.BandScreenFrame
import com.chaos.bandpack.ui.component.ChipFlow
import com.chaos.bandpack.ui.component.ContentColumn
import com.chaos.bandpack.ui.component.EmptyState
import com.chaos.bandpack.ui.component.ExportPill
import com.chaos.bandpack.ui.component.HintBar
import com.chaos.bandpack.ui.component.MakerScaffold
import com.chaos.bandpack.ui.component.enterPageT
import com.chaos.bandpack.ui.component.SectionHeader
import com.chaos.bandpack.ui.component.StatChip
import com.chaos.bandpack.ui.theme.ChaosPalette
import com.chaos.bandpack.ui.theme.Spacing
import com.chaos.bandpack.ui.theme.enterLayer
import com.chaos.bandpack.ui.theme.tabular
import com.chaos.bandpack.ui.twoPane
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.chaos.bandpack.ui.theme.ChaosIcon
import com.chaos.bandpack.ui.theme.chaosIcon

/** 繁体覆盖到多少才算"这份字体真有繁体"（Big5 共 13053 字，七成以上才算像个繁体字库） */
private const val TRAD_COVER_OK = 9000

/**
 * 字体投递表盘制作页。
 *
 * 信息架构(用户进来的目的: 把一份字体变成能上手的包):
 *   ① 字体文件 —— 没选时是一整块可点的空状态; 选了以后是文件名 + 一排数据小票
 *   ② 参数     —— 短名 / 表盘名称 / 标题文字 / 表盘 ID / 字集 / 归一化
 *   ③ 预览     —— 高亮容器: 用产出字体本身渲染, 带字号滑杆
 *   ④ 将写入的包 —— 包号与体积(导出前最后一眼)
 * 主动作(导出)是右下角的扩展 FAB —— 底栏给了导航栏。宽屏下 ② ③ 左右分栏。
 *
 * 取向: **少文字、多控件**。统计一律走 [StatChip], 解释性散文删掉,
 * 但错误与限制提示([HintBar] / supportingText 里的计数)一律保留 —— 那是可用性。
 *
 * 工作区 [FontDraft] 由外壳记住: 这一页是底部导航栏的同级标签页, 切走再切回来不能把
 * 处理了几秒的字体和调好的参数丢掉。
 *
 * 纪律: 预览渲染的字体与打进包里的字体是**同一份字节**。
 */
@Composable
fun FontMakerScreen(draft: FontDraft, autoUri: android.net.Uri? = null, onAutoConsumed: () -> Unit = {}) {
    val ctx = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }

    // 转发到工作区: 读写本身就是快照状态, 所以下面的代码不必到处写 `draft.`
    var srcBytes by draft::srcBytes
    var srcName by draft::srcName
    var pre by draft::pre
    var srcErr by draft::srcErr

    var label by draft::label
    var packName by draft::packName
    var title by draft::title
    var pkgId by draft::pkgId
    var nameTouched by draft::nameTouched
    var titleTouched by draft::titleTouched

    var kind by draft::kind
    var normalize by draft::normalize

    var made by draft::made
    var busy by draft::busy
    var err by draft::err

    var pack by draft::pack
    var savedAs by draft::savedAs
    var previewSp by draft::previewSp

    fun syncDefaults(l: String) {
        if (!nameTouched) packName = "字:$l"
        if (!titleTouched) title = "字体投递 $l"
    }

    fun loadUri(uri: android.net.Uri) {
        scope.launch {
            err = null
            savedAs = null
            // 名字一律问 ContentResolver 要: content URI 的 lastPathSegment 往往是媒体库
            // 行号(例如 "1000000026"), 直接拿来显示等于给用户一串没意义的数字
            val name = withContext(Dispatchers.IO) {
                runCatching {
                    ctx.contentResolver.query(
                        uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null,
                    )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
                }.getOrNull()
            } ?: uri.lastPathSegment?.substringAfterLast('/') ?: "字体"
            val bytes = withContext(Dispatchers.IO) {
                runCatching { ctx.contentResolver.openInputStream(uri)!!.use { it.readBytes() } }
            }.getOrElse {
                srcErr = "读不到这个文件：${it.message}"
                return@launch
            }
            srcBytes = bytes
            srcName = name
            val check = withContext(Dispatchers.Default) { runCatching { FontMake.precheck(bytes) }.getOrNull() }
            pre = check
            srcErr = if (check == null) "这个文件不是 TrueType 字体（只支持 TTF/OTF 轮廓）" else null
            if (label.isBlank()) {
                label = name.substringBeforeLast('.').filter { c -> c.isLetterOrDigit() }.take(4)
                    .ifBlank { "font" }
            }
            syncDefaults(label)
        }
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) loadUri(uri)
    }

    // 外面送进来的文件(分享/打开) —— 只消费一次
    LaunchedEffect(autoUri) {
        autoUri?.let { loadUri(it) }
        if (autoUri != null) onAutoConsumed()
    }

    var toSave by draft::toSave
    val exporter = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/octet-stream")
    ) { uri ->
        // 字节先问中转站要: 去开系统保存界面那一段 Activity 允许被重建(转屏/内存回收),
        // 放在 state 里的字节会随重建一起丢, 那时这里静默 return —— 用户看到的就是
        // "选完文件啥也没发生"。取不到就明确报出来, 不许什么都不说。
        val pend = ExportPending.take()
        // SAF 回的 URI 里读不到可读的名字(lastPathSegment 往往是媒体库行号),
        // 所以用我们自己拼的那一个; 兜底再退账到 URI。
        val suggested = pend?.name ?: "chaos-fontpack-$label.bin"
        val data = pend?.bytes ?: toSave
        if (uri == null || data == null) {
            scope.launch { snackbar.showSnackbar("没有待写的包，请回到这一页再点一次导出") }
            return@rememberLauncherForActivityResult
        }
        scope.launch {
            val r = withContext(Dispatchers.IO) {
                runCatching { ctx.contentResolver.openOutputStream(uri)!!.use { it.write(data) } }
            }
            val name = suggested
            r.fold(
                onSuccess = {
                    savedAs = name
                    // 写盘成功要有触觉回执: 这一步之后用户就要离开 App 去侧载, 眼睛不在屏幕上
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                },
                onFailure = { savedAs = "写入失败：${it.message}" },
            )
            snackbar.showSnackbar(if (r.isSuccess) "已保存 $name" else "写入失败：${r.exceptionOrNull()?.message}")
        }
    }

    // 选项/源变化 → 重做(归一化 + 子集化)。防抖 300ms: 25MB 字体要几秒
    LaunchedEffect(srcBytes, kind, normalize) {
        val src = srcBytes ?: return@LaunchedEffect
        delay(300)
        busy = true
        err = null
        made = withContext(Dispatchers.Default) {
            runCatching { FontMake.build(ctx, src, FontSubset.Options(kind, normalize)) }
                .getOrElse {
                    err = it.message ?: it.toString()
                    null
                }
        }
        busy = false
    }

    // 参数齐了就实时打包: 导出前能看到最终包号与体积
    LaunchedEffect(made, label, packName, title, pkgId) {
        val m = made ?: run { pack = null; return@LaunchedEffect }
        if (label.isBlank() || packName.isBlank() || title.isBlank()) {
            pack = null
            return@LaunchedEffect
        }
        if (label.toByteArray(Charsets.UTF_8).size > 12) {
            pack = null
            return@LaunchedEffect
        }
        if (pkgId.isNotBlank() && pkgId.length != 12) {
            pack = null
            return@LaunchedEffect
        }
        delay(300)
        pack = withContext(Dispatchers.Default) {
            runCatching {
                PackMake.fontPack(
                    ctx,
                    FontPackBuilder.Inputs(
                        label = label,
                        packName = packName,
                        title = title,
                        pkgName = pkgId.ifBlank { null },
                        font = m.font,
                    ),
                )
            }.getOrElse {
                err = it.message ?: it.toString()
                null
            }
        }
    }

    val titleWarn = if (title.isBlank()) null else TitleText.validate(title)
    val wide = LocalWidthClass.current.twoPane

    MakerScaffold(
        title = "字体投递表盘",
        kicker = "系统美化",
        snackbar = snackbar,
    ) { padding, bar ->
        // 整页一次淡入上移。按分节挂会漏掉懒加载的那些节, 见 enterPageT 的注释。
        val pageT = enterPageT()
        Column(
            Modifier
                .fillMaxSize()
                .nestedScroll(bar.nestedScrollConnection)
                .padding(padding)
                .enterLayer(pageT)
                .verticalScroll(rememberScrollState()),
        ) {
            ContentColumn {
                // ① 字体文件: 没选的时候整块就是按钮, 不再配一句"选好以后这里会出现……"
                SectionHeader("字体文件", chaosIcon(ChaosIcon.SectionFont))
                val src = srcBytes
                if (src == null) {
                    EmptyState(
                        icon = chaosIcon(ChaosIcon.SectionFont),
                        title = "选一份字体",
                        hint = "TTF / OTF 轮廓字体",
                        actionLabel = "选择字体文件",
                        onAction = { picker.launch(arrayOf("*/*")) },
                    )
                    srcErr?.let {
                        Spacer(Modifier.height(Spacing.m))
                        HintBar(chaosIcon(ChaosIcon.Warning), it, error = true)
                    }
                } else {
                    SourceBlock(
                        fileName = srcName,
                        sizeBytes = src.size,
                        pre = pre,
                        err = srcErr,
                        onPick = { picker.launch(arrayOf("*/*")) },
                    )
                }

                AnimatedVisibility(visible = srcBytes != null, enter = fadeIn(), exit = fadeOut()) {
                    Column {
                        if (wide) {
                            // 宽屏: 左参数 右预览
                            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xxl)) {
                                Column(Modifier.weight(1f)) {
                                    SectionHeader("参数", chaosIcon(ChaosIcon.SectionParams))
                                    OptionsBlock(
                                        label, { v -> label = v.truncateBytes(FontPackBuilder.LABEL_BYTES); syncDefaults(label) },
                                        packName, { nameTouched = true; packName = it.truncateBytes(ShellBuilder.NAME_MAX - 1) },
                                        title, { titleTouched = true; title = it.take(24) },
                                        titleWarn, pkgId,
                                        { pkgId = it.filter { c -> c.isDigit() }.take(12) },
                                        kind, { kind = it }, normalize, { normalize = it },
                                    )
                                }
                                Column(Modifier.weight(1f)) {
                                    SectionHeader("预览", chaosIcon(ChaosIcon.FontSize))
                                    PreviewBlock(made, busy, kind, title, previewSp, { previewSp = it }, err = err)
                                }
                            }
                        } else {
                            SectionHeader("参数", chaosIcon(ChaosIcon.SectionParams))
                            OptionsBlock(
                                label, { v -> label = v.truncateBytes(FontPackBuilder.LABEL_BYTES); syncDefaults(label) },
                                packName, { nameTouched = true; packName = it.truncateBytes(ShellBuilder.NAME_MAX - 1) },
                                title, { titleTouched = true; title = it.take(24) },
                                titleWarn, pkgId,
                                { pkgId = it.filter { c -> c.isDigit() }.take(12) },
                                kind, { kind = it }, normalize, { normalize = it },
                            )
                            SectionHeader("预览", chaosIcon(ChaosIcon.FontSize))
                            PreviewBlock(made, busy, kind, title, previewSp, { previewSp = it }, err = err)
                        }

                        SectionHeader("将写入的包", chaosIcon(ChaosIcon.SectionPack))
                        PackBlock(pack, savedAs)
                    }
                }
                // 主动作: 高胶囊贴在内容流末尾, 不再浮在角上(浮着的 FAB 会永久盖住
                // 最后一个输入框)。上下各留一段整白, 让它是一块**独立的动作区**
                // 而不是贴在上一张卡下面的一条 —— 紧贴时它会读成卡片的一部分。
                Spacer(Modifier.height(Spacing.xxl))
                val p = pack
                ExportPill(
                    enabled = p != null,
                    busy = busy,
                    label = if (p == null) "导出 .bin"
                    else "导出 · %.2f MB".format(p.bytes.size / 1048576.0),
                    hint = exportBlockReason(srcBytes, made, busy, label, packName, title, pkgId, err, p),
                    // 尾随 lambda 会绑到最后那个参数(这里是 modifier), 所以 onClick 必须显式写
                    onClick = {
                        val r = p ?: return@ExportPill
                        ExportPending.put(r.bytes, "chaos-fontpack-$label.bin")
                        toSave = r.bytes
                        savedAs = null
                        // 系统没有一个 app 接这个 intent 时 launch 会直接抛,
                        // 在点击回调里抛就是闪退 —— 包住并给出可读的一条。
                        runCatching { exporter.launch("chaos-fontpack-$label.bin") }
                            .onFailure {
                                scope.launch { snackbar.showSnackbar("打不开保存界面：${it.message}") }
                            }
                    },
                )
                Spacer(Modifier.height(Spacing.xxl))
            }
        }
    }
}

/**
 * 导出按钮现在为什么点不了 —— 逐条翻译成人话。
 *
 * 这些分支过去一律只是把包置空, 界面上三个不同的原因长得一模一样(一圈灰描边),
 * 用户只能对着按钮反复点; 打包失败那条虽然有 [HintBar], 但它在半页之外的预览卡里。
 */
private fun exportBlockReason(
    srcBytes: ByteArray?,
    made: FontMake.Made?,
    busy: Boolean,
    label: String,
    packName: String,
    title: String,
    pkgId: String,
    err: String?,
    pack: FontPackBuilder.Result?,
): String? {
    val labelBytes = label.toByteArray(Charsets.UTF_8).size
    return when {
        srcBytes == null -> "先选一份字体文件"
        busy -> null
        made == null -> err?.let { "字体没处理出来：$it" } ?: "正在处理字体…"
        label.isBlank() -> "短名是空的"
        packName.isBlank() -> "表盘名称是空的"
        title.isBlank() -> "标题文字是空的"
        labelBytes > FontPackBuilder.LABEL_BYTES ->
            "短名 $labelBytes 字节，上限 ${FontPackBuilder.LABEL_BYTES}（中文最多 4 个字）"
        pkgId.isNotBlank() && pkgId.length != 12 ->
            "表盘 ID 要 12 位数字，现在是 ${pkgId.length} 位"
        pack == null -> err?.let { "打包失败：$it" } ?: "包还没准备好"
        else -> null
    }
}

// ===== 区块 =====

/** 已选源文件: 一行文件名 + 换文件按钮, 下面一排数据小票(不再写"字形多少、码位多少"的句子) */
@Composable
private fun SourceBlock(
    fileName: String,
    sizeBytes: Int,
    pre: FontMake.Precheck?,
    err: String?,
    onPick: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
        Surface(
            shape = MaterialTheme.shapes.large,
            color = MaterialTheme.colorScheme.surfaceContainerLow,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(
                Modifier.padding(Spacing.l),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier
                        .size(44.dp)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.primaryContainer),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        chaosIcon(ChaosIcon.SectionFont),
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
                Spacer(Modifier.width(Spacing.l))
                Text(
                    text = fileName,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Spacer(Modifier.width(Spacing.m))
                FilledTonalButton(onClick = onPick, shape = MaterialTheme.shapes.medium) {
                    Text("换一个")
                }
            }
        }
        when {
            err != null -> HintBar(chaosIcon(ChaosIcon.Warning), err, error = true)
            pre != null && !pre.ok -> HintBar(
                chaosIcon(ChaosIcon.Warning),
                "缺 ${pre.missingRequired} 个必需字符（${pre.sampleText}），手环上会显示成空白框。",
                error = true,
            )
            pre != null -> ChipFlow {
                StatChip(chaosIcon(ChaosIcon.Size), "%.2f MB".format(sizeBytes / 1048576.0), "源文件")
                StatChip(chaosIcon(ChaosIcon.Dashboard), "${pre.glyphs}", "字形")
                StatChip(chaosIcon(ChaosIcon.Tag), "${pre.cmapChars}", "码位")
                StatChip(chaosIcon(ChaosIcon.World), "${pre.traditional}", "繁体")
            }
        }
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun OptionsBlock(
    label: String,
    onLabel: (String) -> Unit,
    packName: String,
    onPackName: (String) -> Unit,
    title: String,
    onTitle: (String) -> Unit,
    titleWarn: String?,
    pkgId: String,
    onPkgId: (String) -> Unit,
    kind: Charset.Kind,
    onKind: (Charset.Kind) -> Unit,
    normalize: Boolean,
    onNormalize: (Boolean) -> Unit,
) {
    val labelBytes = label.toByteArray(Charsets.UTF_8).size
    val titleWidth = TitleText.width(title)
    val titleOver = titleWidth > TitleText.MAX_HALF
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
        OutlinedTextField(
            value = label,
            onValueChange = onLabel,
            label = { Text("短名") },
            supportingText = {
                Text(if (labelBytes > 12) "$labelBytes/12 · 超了" else "$labelBytes/12")
            },
            isError = labelBytes > 12,
            singleLine = true,
            shape = MaterialTheme.shapes.medium,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = packName,
            onValueChange = onPackName,
            label = { Text("表盘名称") },
            singleLine = true,
            shape = MaterialTheme.shapes.medium,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = title,
            onValueChange = onTitle,
            label = { Text("标题文字") },
            supportingText = {
                Text(
                    text = if (titleOver) "$titleWidth/${TitleText.MAX_HALF} · 超宽"
                    else "$titleWidth/${TitleText.MAX_HALF}",
                    color = if (titleOver) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            },
            isError = titleWarn != null && titleOver,
            singleLine = true,
            shape = MaterialTheme.shapes.medium,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = pkgId,
            onValueChange = onPkgId,
            label = { Text("表盘 ID") },
            placeholder = { Text("留空自动推导") },
            supportingText = {
                Text(
                    if (pkgId.isBlank()) "12 位数字，留空则按内容推导"
                    else if (pkgId.length != 12) "${pkgId.length}/12"
                    else "已固定，重投覆盖旧包",
                )
            },
            isError = pkgId.isNotBlank() && pkgId.length != 12,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            singleLine = true,
            shape = MaterialTheme.shapes.medium,
            modifier = Modifier.fillMaxWidth(),
        )

        // 字集: 字数直接进标签本身, 这样就不用再补一段解释两档差别的说明文字
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
            FilterChip(
                selected = kind == Charset.Kind.SIMPLIFIED,
                onClick = { onKind(Charset.Kind.SIMPLIFIED) },
                label = { Text("精简 ${Charset.required.size / 1000}k") },
                leadingIcon = {
                    val i = if (kind == Charset.Kind.SIMPLIFIED) chaosIcon(ChaosIcon.Check) else chaosIcon(ChaosIcon.Charset)
                    Icon(i, null, Modifier.size(16.dp))
                },
                shape = MaterialTheme.shapes.small,
            )
            FilterChip(
                selected = kind == Charset.Kind.WITH_TRADITIONAL,
                onClick = { onKind(Charset.Kind.WITH_TRADITIONAL) },
                label = { Text("繁体 +${Charset.big5.size / 1000}k") },
                leadingIcon = {
                    val i =
                        if (kind == Charset.Kind.WITH_TRADITIONAL) chaosIcon(ChaosIcon.Check) else chaosIcon(ChaosIcon.World)
                    Icon(i, null, Modifier.size(16.dp))
                },
                shape = MaterialTheme.shapes.small,
            )
        }

        // 归一化: 整行可点(控件而不是说明), 图标 + 一行短注 + 开关
        Surface(
            onClick = { onNormalize(!normalize) },
            shape = MaterialTheme.shapes.large,
            color = MaterialTheme.colorScheme.surfaceContainerLow,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(
                Modifier.padding(start = Spacing.l, end = Spacing.m, top = Spacing.m, bottom = Spacing.m),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    chaosIcon(ChaosIcon.LineHeight),
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                )
                Spacer(Modifier.width(Spacing.l))
                Column(Modifier.weight(1f)) {
                    Text("度量归一化", style = MaterialTheme.typography.bodyLarge)
                    Text(
                        "行高对齐系统字体 1.326em",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(checked = normalize, onCheckedChange = onNormalize)
            }
        }
    }
}

@OptIn(
    androidx.compose.material3.ExperimentalMaterial3Api::class,
    androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class,
)
@Composable
private fun PreviewBlock(
    made: FontMake.Made?,
    busy: Boolean,
    kind: Charset.Kind,
    title: String,
    previewSp: Float,
    onPreviewSp: (Float) -> Unit,
    err: String?,
) {
    if (busy || made == null) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            LoadingIndicator(modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(Spacing.m))
            Text(
                if (err != null) "处理失败" else "正在归一化并精简字集…",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (err != null) {
            Spacer(Modifier.height(Spacing.s))
            HintBar(chaosIcon(ChaosIcon.Warning), err, error = true)
        }
        return
    }
    val face = made.face
    val fam = face?.let { FontFamily(it) } ?: FontFamily.Default
    val rep = made.report
    // 繁体样本只在字体真有繁体字形时才画: 系统缺字会静默回退, 画出来是骗人的
    val tradOk = rep.traditional >= TRAD_COVER_OK

    // ① 上手效果: 设备外框里放**用户真正要写的那行标题**, 用产出字体渲染。
    //    字号固定成屏上那个大小, 所以标题超宽在这里就会自己折行 —— 比数数字直观。
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
        BandScreenFrame {
            BandScreenContent {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
                    Text(
                        title.ifBlank { "字体投递" },
                        style = TextStyle(
                            fontFamily = fam,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.SemiBold,
                            lineHeight = 20.sp,
                        ),
                        color = ChaosPalette.SCREEN_FG,
                    )
                    Text(
                        "永和九年 岁在癸丑",
                        style = TextStyle(fontFamily = fam, fontSize = 11.sp, lineHeight = 15.sp),
                        color = ChaosPalette.SCREEN_FG_DIM,
                    )
                }
            }
        }
    }
    Spacer(Modifier.height(Spacing.l))

    // ② 字体本身: 全宽样张, 字号由下面的滑杆驱动
    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = MaterialTheme.shapes.extraLarge,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            Modifier.padding(Spacing.xl),
            verticalArrangement = Arrangement.spacedBy(Spacing.m),
        ) {
            Text(
                "字体投递 花朝粗",
                style = TextStyle(
                    fontFamily = fam,
                    fontSize = previewSp.sp,
                    fontWeight = FontWeight.SemiBold,
                    lineHeight = (previewSp * 1.35).sp,
                ),
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                "永和九年，岁在癸丑。群贤毕至，少长咸集。",
                style = TextStyle(
                    fontFamily = fam,
                    fontSize = (previewSp * 0.72).sp,
                    lineHeight = (previewSp * 1.05).sp,
                ),
                color = MaterialTheme.colorScheme.onSurface,
            )
            if (kind == Charset.Kind.WITH_TRADITIONAL && tradOk) {
                Text(
                    "繁體：們 為 國 學 臺 龍 數 據",
                    style = TextStyle(
                        fontFamily = fam,
                        fontSize = (previewSp * 0.72).sp,
                        lineHeight = (previewSp * 1.05).sp,
                    ),
                    color = MaterialTheme.colorScheme.onSurface,
                )
            }
            Text(
                "0123456789 ABC abc ！？，。·—",
                style = TextStyle(
                    fontFamily = fam,
                    fontSize = (previewSp * 0.62).sp,
                    lineHeight = (previewSp * 0.95).sp,
                ),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            // 字号滑杆: 样张大小是这一屏用户唯一会想自己拧的控件, 不给说明只给滑杆
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    chaosIcon(ChaosIcon.FontSize),
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(18.dp),
                )
                Slider(
                    value = previewSp,
                    onValueChange = onPreviewSp,
                    valueRange = 16f..40f,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    "${previewSp.toInt()}",
                    style = MaterialTheme.typography.labelLarge.tabular(),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.End,
                    modifier = Modifier.width(32.dp),
                )
            }
        }
    }
    if (face == null) {
        Spacer(Modifier.height(Spacing.s))
        HintBar(
            chaosIcon(ChaosIcon.Warning),
            "本机渲染不了这份产出（字体已生成，只是预览不可用）。",
            error = true,
        )
    }

    Spacer(Modifier.height(Spacing.l))
    // 统计一律走小票: 体积 / 字形 / 行高比 / 覆盖 / 繁体。句子删掉, 数字留在原地。
    ChipFlow {
        StatChip(chaosIcon(ChaosIcon.Size), "%.2f MB".format(rep.outBytes / 1048576.0), "产出")
        StatChip(chaosIcon(ChaosIcon.Dashboard), "${rep.outGlyphs}", "字形 / 源 ${rep.srcGlyphs}")
        rep.metrics?.let { m ->
            StatChip(chaosIcon(ChaosIcon.Height), "%.3f→%.3f".format(m.ratioBefore, m.ratioAfter), "行高比")
        }
        StatChip(chaosIcon(ChaosIcon.Checklist), "${rep.cmapChars}", "覆盖字")
        StatChip(
            chaosIcon(ChaosIcon.World),
            "${rep.traditional}",
            "繁体",
            container = if (tradOk || kind != Charset.Kind.WITH_TRADITIONAL) {
                MaterialTheme.colorScheme.surfaceContainerHigh
            } else {
                MaterialTheme.colorScheme.errorContainer
            },
            content = if (tradOk || kind != Charset.Kind.WITH_TRADITIONAL) {
                MaterialTheme.colorScheme.onSurface
            } else {
                MaterialTheme.colorScheme.onErrorContainer
            },
        )
    }
    if (kind == Charset.Kind.WITH_TRADITIONAL && !tradOk) {
        Spacer(Modifier.height(Spacing.m))
        HintBar(
            chaosIcon(ChaosIcon.Warning),
            "这份字体只有 ${rep.traditional} 个繁体字（Big5 共 ${Charset.big5.size}），" +
                "保留繁体档对它作用有限 —— 缺的字在手环上显示成空白。",
            error = true,
        )
    }
}

@Composable
private fun PackBlock(pack: FontPackBuilder.Result?, savedAs: String?) {
    if (pack == null) {
        Text(
            "填齐短名、表盘名称与标题后出包。",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        return
    }
    Column {
        ChipFlow {
            StatChip(chaosIcon(ChaosIcon.Pin), pack.pkgName, "表盘 ID")
            StatChip(chaosIcon(ChaosIcon.Size), "%.2f MB".format(pack.bytes.size / 1048576.0), "包体积")
            StatChip(chaosIcon(ChaosIcon.SectionParams), pack.packName, "表盘名称")
        }
        if (savedAs != null) {
            Spacer(Modifier.height(Spacing.m))
            HintBar(chaosIcon(ChaosIcon.TaskOk), "已保存：$savedAs")
        }
    }
}
