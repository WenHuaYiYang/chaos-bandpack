package com.chaos.bandpack.ui.screen

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions

import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Surface
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.chaos.bandpack.data.displayNameOf
import com.chaos.bandpack.data.icon.IconConvert
import com.chaos.bandpack.data.DeviceTarget
import com.chaos.bandpack.ui.LocalDeviceTarget
import com.chaos.bandpack.data.icon.PortableIcons
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import com.chaos.bandpack.data.icon.IconSpec
import com.chaos.bandpack.data.make.IconMake
import com.chaos.bandpack.data.make.PackMake
import com.chaos.bandpack.data.pack.Cipk
import com.chaos.bandpack.data.pack.IconPackBuilder
import com.chaos.bandpack.data.pack.ShellBuilder
import com.chaos.bandpack.data.pack.truncateBytes
import com.chaos.bandpack.data.pack.TitleText
import com.chaos.bandpack.ui.LocalWidthClass
import com.chaos.bandpack.ui.component.ExportPill
import com.chaos.bandpack.ui.component.ChipFlow
import com.chaos.bandpack.ui.component.HintBar
import com.chaos.bandpack.ui.component.LegendSwatch
import com.chaos.bandpack.ui.component.MakerScaffold
import com.chaos.bandpack.ui.component.enterPageT
import com.chaos.bandpack.ui.component.SectionHeader
import com.chaos.bandpack.ui.component.StatChip
import com.chaos.bandpack.ui.gridColumns
import com.chaos.bandpack.ui.pagePadding
import com.chaos.bandpack.ui.theme.LocalPageTone
import com.chaos.bandpack.ui.theme.Spacing
import com.chaos.bandpack.ui.theme.enterLayer
import com.chaos.bandpack.ui.theme.tabular
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.chaos.bandpack.ui.theme.ChaosIcon
import com.chaos.bandpack.ui.theme.chaosIcon

/**
 * 图标投递表盘制作页。
 *
 * 信息架构: ① 槽位网格(主信息: 哪些改了、哪些保持原样) → ② 表盘参数 → ③ 将写入的包。
 * 规则(与手环侧一致): **空槽不进包** —— 手环上继续用系统原图标, 界面上把原图标调暗显示当参照。
 * 取向: 少文字多控件 —— 顶部用"已选进度条 + 两格图例"说明状态,
 * 清空走图标按钮, 产出统计走 [StatChip]; 可点元素的标签一律保留。
 * 交互: 点槽位选图, 已选格右上角小叉清空; 主动作是右下角的扩展 FAB(底栏给了导航栏);
 * 瞬时反馈走 Snackbar。工作区 [IconDraft] 由外壳记住, 切走再切回来已选的图还在。
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun IconMakerScreen(draft: IconDraft, autoUri: android.net.Uri? = null, onAutoConsumed: () -> Unit = {}) {
    val ctx = LocalContext.current
    val device = LocalDeviceTarget.current
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    val width = LocalWidthClass.current

    // 转发到工作区: 这一页是底部导航栏的同级标签页, 切走再回来不能丢已选的图
    var picked by draft::picked
    var short by draft::short
    var packName by draft::packName
    var title by draft::title
    var pkgId by draft::pkgId
    var nameTouched by draft::nameTouched
    var titleTouched by draft::titleTouched

    var busy by draft::busy
    var pack by draft::pack

    var toSave by draft::toSave
    var savedAs by draft::savedAs
    var pendingStem by draft::pendingStem
    var group by draft::group
    val slots = IconSpec.all(device)
    val chosen = picked.keys.count { IconSpec.stemOf(it, device) != null }
    val omitted = picked.keys.filter { IconSpec.stemOf(it, device) == null && !(it == "ctrl_dnd" && device == DeviceTarget.TEN_PRO && "ctrl_disturb" in picked) }
    LaunchedEffect(device) { if (IconSpec.slots(group, device).isEmpty()) group = IconSpec.Group.DESKTOP }

    fun tell(text: String) {
        scope.launch { snackbar.showSnackbar(text) }
    }

    fun loadInto(stem: String, uri: android.net.Uri) {
        scope.launch {
            busy = true
            val r = try {
                withContext(Dispatchers.Default) {
                    runCatching { IconMake.convert(ctx, uri, requireNotNull(IconSpec.stemOf(stem, device))) }
                }
            } finally { busy = false }
            r.fold(
                onSuccess = { res ->
                    picked = picked + (stem to res.bytes)
                    haptics.performHapticFeedback(HapticFeedbackType.ContextClick)
                    val label = IconSpec.stemOf(stem, device)?.label ?: stem
                    tell("「$label」已处理：内容占比 %.0f%%".format(res.report.coverage * 100))
                },
                onFailure = { e ->
                    tell(
                        when (e) {
                            is IconConvert.Blank -> "这张图整幅都是透明的，换一张"
                            is IconConvert.NoPlate -> e.message ?: "这张图没有底板"
                            else -> "处理失败：${e.message}"
                        }
                    )
                },
            )
        }
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val stem = pendingStem
        pendingStem = null
        if (uri != null && stem != null) loadInto(stem, uri)
    }

    /**
     * 批量导入: 一次多选图片, **按文件名落到对应槽位**。
     *
     * 匹配规则只有两条, 都可预测:
     *   1. 文件名去掉扩展名后与槽位的英文名相同(不分大小写) —— `weather.png` 落"天气";
     *   2. 或与该槽位的**中文显示名**相同 —— `天气.png` 也落"天气"。
     *
     * 认不出来的**不硬塞**: 塞进空格只会让用户事后一个个翻出来改, 不如直接报数让他改文件名。
     * 同一槽位被多张命中时报告重名，保留该槽原先的选择。
     * 单张失败(全透明 / 没有底板)**不影响其它张** —— 逐张收集, 不整批中断。
     */
    fun loadMany(uris: List<android.net.Uri>) {
        if (uris.isEmpty()) return
        scope.launch {
            busy = true
            val res = try { withContext(Dispatchers.IO) {
                val next = picked.toMutableMap()
                var ok = 0
                var unmatched = 0
                val bad = mutableListOf<String>()
                val names = uris.map { it to stemForName(ctx, it, device) }
                val duplicates = IconSpec.duplicateStems(names.map { it.second })
                for ((u, name) in names) {
                    val stem = name ?: run { unmatched++; continue }
                    if (stem in duplicates) { bad += "重名: ${IconSpec.stemOf(stem, device)?.label}"; continue }
                    runCatching { IconMake.convert(ctx, u, requireNotNull(IconSpec.stemOf(stem, device))) }
                        .onSuccess { next[stem] = it.bytes; ok++ }
                        .onFailure { bad += (IconSpec.stemOf(stem, device)?.label ?: stem) }
                }
                BatchImport(next, ok, unmatched, bad)
            } } finally { busy = false }
            picked = res.picked
            if (res.ok > 0) haptics.performHapticFeedback(HapticFeedbackType.ContextClick)
            tell(
                buildString {
                    append("导入 ${res.ok} 张")
                    if (res.unmatched > 0) append("，${res.unmatched} 张文件名对不上")
                    if (res.bad.isNotEmpty()) append("，${res.bad.size} 张重名或不合适：${res.bad.take(3).joinToString()}")
                },
            )
        }
    }

    val batchPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments()
    ) { uris -> loadMany(uris) }

    val exporter = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/octet-stream")
    ) { uri ->
        // 同字体页: 字节挂在中转站上, 去开系统保存界面那一段 Activity 允许被重建。
        // 取不到就明说, 不许静默 return —— 那种失败在界面上表现为"点了导出没反应"。
        val pend = ExportPending.take()
        val suggested = pend?.name ?: "chaos-iconpack-${device.id}-$short.bin"
        val data = pend?.bytes ?: toSave
        if (uri == null || data == null) {
            tell("没有待写的包，请回到这一页再点一次导出")
            return@rememberLauncherForActivityResult
        }
        scope.launch {
            val r = withContext(Dispatchers.IO) {
                runCatching { ctx.contentResolver.openOutputStream(uri)!!.use { it.write(data) } }
            }
            r.fold(
                onSuccess = {
                    savedAs = suggested
                    tell("已保存 ${savedAs}")
                },
                onFailure = { tell("写入失败：${it.message}") },
            )
        }
    }

    // 外面分享进来的图片: 放进第一个空格。用完让上层清掉 URI, 免得在另一页被重复消费
    LaunchedEffect(autoUri) {
        val u = autoUri ?: return@LaunchedEffect
        val stem = IconSpec.slots(group, device).firstOrNull { !picked.containsKey(it.stem) }?.stem
        if (stem != null) loadInto(stem, u)
        onAutoConsumed()
    }

    // 参数变化就重打包(图标包很便宜), 导出前就能看到张数/体积/包号
    LaunchedEffect(picked, short, packName, title, pkgId, device) {
        pack = null
        savedAs = null
        if (picked.isEmpty() || short.isBlank() || packName.isBlank() || title.isBlank()) {
            pack = null
            return@LaunchedEffect
        }
        if (pkgId.isNotBlank() && pkgId.length != 12) {
            pack = null
            return@LaunchedEffect
        }
        delay(250)
        pack = withContext(Dispatchers.Default) {
            runCatching {
                PackMake.iconPack(
                    ctx,
                    IconPackBuilder.Inputs(
                        short = short,
                        packName = packName,
                        title = title,
                        pkgName = pkgId.ifBlank { null },
                        icons = PortableIcons.forTarget(picked, device).icons,
                    ),
                    device = device,
                )
            }.getOrElse {
                tell(it.message ?: "打包失败")
                null
            }
        }
    }

    MakerScaffold(
        title = "图标投递表盘",
        kicker = "${device.label} · ${device.firmware}",
        snackbar = snackbar,
    ) { padding, bar ->
        // 整页一次淡入上移。按分节挂会漏掉懒加载的那些节, 见 enterPageT 的注释。
        val pageT = enterPageT()
        LazyVerticalGrid(
            columns = GridCells.Fixed(width.gridColumns),
            modifier = Modifier
                .fillMaxSize()
                .nestedScroll(bar.nestedScrollConnection)
                .padding(padding)
                .enterLayer(pageT),
            contentPadding = PaddingValues(
                start = width.pagePadding,
                end = width.pagePadding,
                bottom = Spacing.xxl,
            ),
            horizontalArrangement = Arrangement.spacedBy(Spacing.m),
            verticalArrangement = Arrangement.spacedBy(Spacing.m),
        ) {
            // ---- 槽位网格 ----
            item(span = { GridItemSpan(maxLineSpan) }) {
                Column {
                    val tone = LocalPageTone.current
                    val s = MaterialTheme.colorScheme
                    SectionHeader("图标槽位", chaosIcon(ChaosIcon.Grid))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(
                                "已选 $chosen / ${slots.size}",
                                style = MaterialTheme.typography.titleLarge.tabular(),
                                fontWeight = FontWeight.Bold,
                                color = tone.onField,
                            )
                            Spacer(Modifier.height(Spacing.s))
                            // 0 张时只画轨道: LinearProgressIndicator 在 progress=0 会留下一个
                            // 圆头小点, 看着像渲染坏了
                            if (picked.isEmpty()) {
                                Box(
                                    Modifier
                                        .fillMaxWidth()
                                        .height(6.dp)
                                        .clip(CircleShape)
                                        .background(lerp(tone.field, tone.onField, 0.14f)),
                                )
                            } else {
                                LinearProgressIndicator(
                                    progress = { chosen / slots.size.toFloat() },
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(6.dp)
                                        .clip(CircleShape),
                                    color = MaterialTheme.colorScheme.primary,
                                    trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                                )
                            }
                        }
                        // 批量导入: 一次多选, 按文件名落到对应槽位(见 loadMany 的注释)。
                        // 这是个"猜不到"的动作, 所以给图标**加文字**, 不做成光秃秃的图标按钮。
                        Row(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(tone.capsule)
                                .clickable(enabled = !busy) { batchPicker.launch(arrayOf("image/*")) }
                                .padding(horizontal = Spacing.m, vertical = Spacing.s),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
                        ) {
                            Icon(
                                chaosIcon(ChaosIcon.Image),
                                contentDescription = null,
                                tint = tone.onField,
                                modifier = Modifier.size(18.dp),
                            )
                            Text(
                                "批量导入",
                                style = MaterialTheme.typography.labelLarge,
                                fontWeight = FontWeight.Bold,
                                color = tone.onField,
                            )
                        }
                        IconButton(
                            onClick = {
                                // 一键清空全部是危险操作: 不弹确认框打断, 但必须能撤销
                                val backup = picked
                                pack = null
                                picked = emptyMap()
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                scope.launch {
                                    val r = snackbar.showSnackbar(
                                        message = "已清空 ${backup.size} 张",
                                        actionLabel = "撤销",
                                    )
                                    if (r == SnackbarResult.ActionPerformed) picked = backup
                                }
                            },
                            enabled = picked.isNotEmpty() && !busy,
                        ) {
                            Icon(
                                chaosIcon(ChaosIcon.DeleteSweep),
                                contentDescription = "全部清空",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    Spacer(Modifier.height(Spacing.l))
                    // 图例: 两种格子长什么样用眼睛认, 不写"空槽保留系统原图标"那句话。
                    // 底色必须与 SlotCell 用同一条算式, 不然图例与实物对不上。
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xl)) {
                        LegendSwatch("已换") { LegendBox(lerp(tone.field, tone.deep, 0.18f)) }
                        LegendSwatch("原图") { LegendBox(lerp(tone.field, s.surface, 0.5f)) }
                    }
                    // 空槽里那张图不是本应用画的: 它是手环原本的图标, 从固件资源包里解出来的。
                    // 出处写在图例下面一句话说清, 免得被当成自有素材(授权限制见开源许可页)。
                    Text(
                        "空槽保留系统图标；批量导入重名时请加分类，例如「控制中心_勿扰」。",
                        style = MaterialTheme.typography.labelSmall,
                        color = tone.muted,
                        modifier = Modifier.padding(top = Spacing.s),
                    )
                }
            }

            item(span = { GridItemSpan(maxLineSpan) }) {
                Column {
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
                        IconSpec.Group.entries.filter { IconSpec.slots(it, device).isNotEmpty() }.forEach { entry ->
                            FilterChip(
                                selected = group == entry,
                                onClick = { group = entry },
                                label = { Text(entry.label) },
                            )
                        }
                    }
                    Text(
                        if (group == IconSpec.Group.DESKTOP) {
                            if (device == DeviceTarget.TEN_PRO) "112 × 112 · 日程与日历分别选择，日历使用静态图"
                            else "100 × 100 · 9 Pro 桌面素材"
                        }
                        else "按槽位尺寸适配 · 保留透明边缘" + if (group == IconSpec.Group.CONTROL) " · 勿扰共用一张图" else "",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            items(IconSpec.slots(group, device), key = { it.stem }) { slot ->
                SlotCell(
                    label = slot.label,
                    selected = picked[slot.stem],
                    stock = if (picked.containsKey(slot.stem) || device == DeviceTarget.NINE_PRO) null else IconMake.stockIcon(ctx, slot.stem),
                    group = slot.group,
                    onClick = {
                        if (!busy) {
                            pendingStem = slot.stem
                            picker.launch(arrayOf("image/*"))
                        }
                    },
                    onClear = {
                        if (!busy) {
                            pack = null
                            picked = picked - slot.stem
                            tell("「${slot.label}」已清空，将使用系统原图标")
                        }
                    },
                )
            }

            // ---- 参数 ----
            item(span = { GridItemSpan(maxLineSpan) }) {
                Column {
                    SectionHeader("表盘参数", chaosIcon(ChaosIcon.SectionParams))
                    ParamsBlock(
                        short, { v ->
                            short = v.filter { c -> c.code in 0x21..0x7E }.take(12)
                            if (!nameTouched) packName = "图标:$short"
                            if (!titleTouched) title = "图标投递 $short"
                        },
                        packName, { nameTouched = true; packName = it.truncateBytes(ShellBuilder.NAME_MAX - 1) },
                        title, { titleTouched = true; title = it.take(24) },
                        pkgId, { v -> pkgId = v.filter { it.isDigit() }.take(12) },
                    )
                }
            }

            // ---- 产出 ----
            item(span = { GridItemSpan(maxLineSpan) }) {
                Column {
                    SectionHeader("将写入的包", chaosIcon(ChaosIcon.SectionPack))
                    if (omitted.isNotEmpty()) {
                        Text("${device.label} 不支持以下素材，本次不导出，工程仍保留：" + omitted.joinToString { PortableIcons.label(it) },
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(Spacing.m))
                    }
                    if (device == DeviceTarget.NINE_PRO) Text("先安装 9 Pro Chaos v2.1；投递包导入到空槽位。仅适配 3.1.187，尚无真机验证。",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    val p = pack
                    if (p == null) {
                        Text(
                            "选了图之后这里出包号与体积。",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else {
                        ChipFlow {
                            StatChip(chaosIcon(ChaosIcon.Pin), p.pkgName, "表盘 ID")
                            StatChip(chaosIcon(ChaosIcon.Grid), "$chosen", "已选槽位")
                            StatChip(chaosIcon(ChaosIcon.Image), "${p.iconCount}", "入包文件")
                            StatChip(
                                chaosIcon(ChaosIcon.Size),
                                "%.2f MB".format(p.bytes.size / 1048576.0),
                                "包体积",
                            )
                            StatChip(
                                chaosIcon(ChaosIcon.Dashboard),
                                "${slots.size - chosen}",
                                "保持原图",
                                container = MaterialTheme.colorScheme.surfaceContainerHigh,
                                content = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (savedAs != null) {
                            Spacer(Modifier.height(Spacing.m))
                            HintBar(chaosIcon(ChaosIcon.TaskOk), "已保存：$savedAs")
                        }
                    }
                    Spacer(Modifier.height(Spacing.xxl))
                    // 主动作: 高胶囊贴在内容流末尾, 不浮在角上(浮着的 FAB 会压住网格
                    // 那一格的标签)。上下各留一段整白, 让它是一块独立的动作区。
                    val pp = pack
                    ExportPill(
                        enabled = pp != null,
                        busy = busy,
                        label = if (pp == null) "导出 .bin"
                        else "导出 ${device.label} · $chosen 槽",
                        hint = exportBlockReason(picked, busy, short, packName, title, pkgId, pp, device),
                        // 尾随 lambda 会绑到最后那个参数(这里是 modifier), onClick 必须显式写
                        onClick = {
                            val r = pp ?: return@ExportPill
                            ExportPending.put(r.bytes, "chaos-iconpack-${device.id}-$short.bin")
                            toSave = r.bytes
                            savedAs = null
                            runCatching { exporter.launch("chaos-iconpack-${device.id}-$short.bin") }
                                .onFailure { tell("打不开保存界面：${it.message}") }
                        },
                    )
                    Spacer(Modifier.height(Spacing.xxxl))
                }
            }
        }
    }
}

/**
 * 槽位两态**只靠底色深浅分**, 不画描边: 参考图里没有一格带边框的网格, 描边在色场上
 * 会读成"一堆空框", 而且 35 格一起铺满就是这张页最难看的来源。
 *   未选 —— 色场往 surface 拉一半的淡面板, 里面是系统原图标(降透明度, 表示"这是现状")
 *   已选 —— 色场往本页实色拉一点的色面板, 右上角一枚实心圆徽标负责"清空这一格"
 * 图标占格子 85%(四周留气口)。选中/清空时图标轻轻弹一下(fast spatial spring)。
 */
@Composable
private fun SlotCell(
    label: String,
    selected: ByteArray?,
    stock: ImageBitmap?,
    group: IconSpec.Group,
    onClick: () -> Unit,
    onClear: () -> Unit,
) {
    val tone = LocalPageTone.current
    val s = MaterialTheme.colorScheme
    val img = remember(selected) { IconMake.previewOf(selected) }
    val haptics = LocalHapticFeedback.current
    val pop by animateFloatAsState(
        targetValue = if (selected != null) 1f else 0.9f,
        animationSpec = MaterialTheme.motionScheme.fastSpatialSpec(),
        label = "slotPop",
    )
    val isSel = selected != null
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(modifier = Modifier.fillMaxWidth()) {
            Surface(
                onClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.ContextClick)
                    onClick()
                },
                shape = MaterialTheme.shapes.large,
                color = if (isSel) lerp(tone.field, tone.deep, 0.18f)
                else if (stock != null && group == IconSpec.Group.CONTROL) Color(0xFF202024)
                else lerp(tone.field, s.surface, 0.5f),
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(1f)
                    // TalkBack: 读出槽位名与状态, 否则只会念一句"按钮"
                    .semantics(mergeDescendants = true) {
                        contentDescription = "$label，${if (isSel) "已选图" else "未选，保持系统原图标"}，点击选择图片"
                    },
            ) {
                Box(Modifier.padding(Spacing.s), contentAlignment = Alignment.Center) {
                    when {
                        img != null -> CellImage(img, alpha = 1f, scale = pop)
                        stock != null -> CellImage(stock, alpha = 0.7f, scale = 1f)
                        else -> Icon(
                            chaosIcon(ChaosIcon.Image),
                            contentDescription = null,
                            tint = tone.muted,
                            modifier = Modifier.size(26.dp),
                        )
                    }
                }
            }
            if (isSel) {
                Surface(
                    onClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.ContextClick)
                        onClear()
                    },
                    shape = CircleShape,
                    color = tone.deep,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .size(32.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            chaosIcon(ChaosIcon.Close),
                            contentDescription = "清空这一格",
                            tint = tone.onDeep,
                            modifier = Modifier.size(16.dp),
                        )
                    }
                }
            }
        }
        Spacer(Modifier.height(Spacing.xs))
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = if (isSel) tone.onField else tone.muted,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun CellImage(bmp: ImageBitmap, alpha: Float, scale: Float) {
    androidx.compose.foundation.Image(
        bitmap = bmp,
        contentDescription = null,
        contentScale = ContentScale.Fit,
        modifier = Modifier
            .fillMaxSize(SLOT_ICON_SCALE)
            .graphicsLayer {
                this.alpha = alpha
                scaleX = scale
                scaleY = scale
            },
    )
}

/** 图例小格: 与槽位同一套底色(都不带描边), 缩到 26dp */
@Composable
private fun LegendBox(fill: Color) {
    Surface(
        shape = MaterialTheme.shapes.small,
        color = fill,
        modifier = Modifier.size(26.dp),
    ) {}
}

/** 槽位里图标的显示比例(比最初那版小 15%) */
private const val SLOT_ICON_SCALE = 0.85f

@Composable
private fun ParamsBlock(
    short: String,
    onShort: (String) -> Unit,
    packName: String,
    onPackName: (String) -> Unit,
    title: String,
    onTitle: (String) -> Unit,
    pkgId: String,
    onPkgId: (String) -> Unit,
) {
    val device = LocalDeviceTarget.current
    Column(
        modifier = Modifier.widthIn(max = Spacing.contentMaxWidth),
        verticalArrangement = Arrangement.spacedBy(Spacing.m),
    ) {
        OutlinedTextField(
            value = short,
            onValueChange = onShort,
            label = { Text("短名") },
            supportingText = { Text("${short.length}/12") },
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
                val w = TitleText.width(title)
                val over = w > TitleText.MAX_HALF
                Text(
                    text = if (over) "$w/${TitleText.MAX_HALF} · 超宽" else "$w/${TitleText.MAX_HALF}",
                    color = if (over) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            },
            isError = TitleText.validate(title)?.contains("太宽") == true,
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
                    else if (device == DeviceTarget.NINE_PRO) "已固定；9 Pro 写入空槽，同名包须另取短名"
                    else "已固定，重投覆盖旧包",
                )
            },
            isError = pkgId.isNotBlank() && pkgId.length != 12,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            singleLine = true,
            shape = MaterialTheme.shapes.medium,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** [loadMany] 的结果: 新的一批图 + 三种去向的计数与名单 */
private class BatchImport(
    val picked: Map<String, ByteArray>,
    val ok: Int,
    val unmatched: Int,
    /** 认出了槽位但图不合适的那几张的**中文名**, 报给用户看 */
    val bad: List<String>,
)

/**
 * 把选中的文件名对到一个槽位上, 对不上返回 null。
 *
 * 只认两种: 英文槽位名(不分大小写) 或 中文显示名。两种都是**精确**匹配 ——
 * 这里不做模糊匹配: 猜错会把图塞进用户没想改的槽位, 而他未必立刻发现。
 */
private fun stemForName(ctx: android.content.Context, uri: android.net.Uri, device: DeviceTarget): String? =
    displayNameOf(ctx, uri)?.let { stemForFileName(it, device) }

/**
 * 文件名 -> 槽位名。抽成**纯函数**是为了能上 JVM 单测: 拿到 Context 的那半截
 * (查 DISPLAY_NAME) 没法在单测里跑, 而"名字怎么算对得上"恰恰是最容易写错的地方。
 */
internal fun stemForFileName(fileName: String, device: DeviceTarget = DeviceTarget.TEN_PRO): String? {
    val base = fileName.substringBeforeLast('.').trim()
    if (base.isEmpty()) return null
    return IconSpec.matchName(base, device)?.stem
}

/**
 * 导出按钮现在为什么点不了。与字体页同一套写法: 过去这些分支一律只把包置空,
 * 界面上什么都不说, 用户只能对着一圈灰描边反复点。
 */
private fun exportBlockReason(
    picked: Map<String, ByteArray>,
    busy: Boolean,
    short: String,
    packName: String,
    title: String,
    pkgId: String,
    pack: IconPackBuilder.Result?,
    device: DeviceTarget = DeviceTarget.TEN_PRO,
): String? {
    val shortBytes = short.toByteArray(Charsets.UTF_8).size
    return when {
        picked.isEmpty() -> "至少往一个槽位里放一张图标"
        busy -> null
        short.isBlank() -> "包短名是空的"
        shortBytes > IconPackBuilder.SHORT_BYTES ->
            "包短名 $shortBytes 字节，上限 ${IconPackBuilder.SHORT_BYTES}"
        device == DeviceTarget.TEN_PRO && short.any { it.code <= 0x20 || it.code >= 0x7F } -> "包短名只能用可打印 ASCII，不支持中文"
        packName.isBlank() -> "表盘名称是空的"
        title.isBlank() -> "标题文字是空的"
        pkgId.isNotBlank() && pkgId.length != 12 ->
            "表盘 ID 要 12 位数字，现在是 ${pkgId.length} 位"
        pack == null -> "包还没准备好（打包失败会在顶部提示）"
        else -> null
    }
}
