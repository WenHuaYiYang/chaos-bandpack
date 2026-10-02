package com.chaos.bandpack.ui.screen

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Slider
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.chaos.bandpack.BuildConfig
import com.chaos.bandpack.data.Assets
import com.chaos.bandpack.data.font.Charset
import com.chaos.bandpack.data.icon.IconSpec
import com.chaos.bandpack.ui.component.ChipFlow
import com.chaos.bandpack.ui.component.ContentColumn
import com.chaos.bandpack.ui.component.LicensesDialog
import com.chaos.bandpack.ui.component.PrivacyPolicyDialog
import com.chaos.bandpack.ui.component.MakerScaffold
import com.chaos.bandpack.ui.component.SectionHeader
import com.chaos.bandpack.ui.component.StatChip
import com.chaos.bandpack.ui.theme.Appearance
import com.chaos.bandpack.ui.theme.LocalPageTone
import com.chaos.bandpack.ui.theme.Spacing
import com.chaos.bandpack.ui.theme.ThemeStyle
import com.chaos.bandpack.ui.theme.UiPrefs
import com.chaos.bandpack.ui.theme.enterLayer
import com.chaos.bandpack.ui.theme.enterT
import com.chaos.bandpack.ui.theme.rememberEnterStep
import com.chaos.bandpack.ui.theme.tabular
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import com.chaos.bandpack.ui.theme.ChaosIcon
import com.chaos.bandpack.ui.theme.chaosIcon

/**
 * 设置页。首页原来那条挤在页脚上面的外观条搬到这里, 首页因此回到"只管分诊"的样子。
 *
 * 三节: **外观**(主题 + 壁纸取色) / **制作默认值**(字集档 + 归一化 + 预览字号) /
 * **关于**(读真实素材得到的包号与体积, 不写死数字)。
 *
 * 每节是一行行"图标徽标 + 标题 + 说明 + 控件"的设置行: 左侧徽标用品牌那套圆角多边形
 * (饼干 / 六边形), 让这一页跟首页的视觉语言接得上。控件一律是真控件 —— 分段按钮、开关、
 * 滑杆、chip, 而不是让人读一段话去猜。
 */
@Composable
fun SettingsScreen() {
    val ctx = LocalContext.current
    val snackbar = remember { SnackbarHostState() }
    var about by remember { mutableStateOf<Assets.About?>(null) }

    LaunchedEffect(Unit) {
        about = withContext(Dispatchers.IO) { Assets.about(ctx) }
    }

    MakerScaffold(title = "设置", kicker = "Chaos", snackbar = snackbar) { padding, bar ->
        Column(
            Modifier
                .fillMaxSize()
                .nestedScroll(bar.nestedScrollConnection)
                .padding(padding)
                .verticalScroll(rememberScrollState()),
        ) {
            ContentColumn {
                // 逐段放行: 一块一块淡入上移, 而不是一整页同时蹦出来
                val step = rememberEnterStep(8)
                val s = MaterialTheme.colorScheme

                // ---- 外观: 主题行 / 分段控件块 / 壁纸取色行。
                // 每张卡独立圆角、行间留缝（同参考图），不做连续叠——见 SettingRow 的注释。
                SectionHeader("外观", chaosIcon(ChaosIcon.Theme))
                SettingGroup {
                    SettingRow(
                        shown = step > 0,
                        icon = chaosIcon(ChaosIcon.Theme),
                        container = s.primaryContainer,
                        onContainer = s.onPrimaryContainer,
                        title = "主题",
                        hint = "强制浅色或深色, 也可以继续跟随系统",
                    )
                    SettingBlock(shown = step > 1) { AppearanceSegments() }
                    // 界面风格: 默认那套（参考图）/ 上一版 MD3。两套共用同一份接口,
                    // 所以切换只是换"怎么算颜色与形状", 界面代码一行都不分支。
                    SettingRow(
                        shown = step > 1,
                        icon = chaosIcon(ChaosIcon.Style),
                        container = s.secondaryContainer,
                        onContainer = s.onSecondaryContainer,
                        title = "界面风格",
                        hint = "默认的纸感风格，或上一版 MD3",
                    )
                    SettingBlock(shown = step > 1) { StyleSegments() }
                    // 壁纸取色**只对 MD3 档起作用**（默认那套的配色是固定的纸感色板），
                    // 所以在默认档下不摆出来 —— 摆一个按了没反应的开关比不摆更糟
                    if (UiPrefs.themeStyle == ThemeStyle.MD3) {
                        SettingRow(
                            shown = step > 2,
                            icon = chaosIcon(ChaosIcon.Palette),
                            container = s.tertiaryContainer,
                            onContainer = s.onTertiaryContainer,
                            title = "壁纸取色",
                            hint = "开则随壁纸，关则用品牌色",
                            control = {
                                Switch(
                                    checked = UiPrefs.dynamicColor,
                                    onCheckedChange = { UiPrefs.setDynamicColor(it) },
                                )
                            },
                        )
                    }
                    // 底栏文字: 默认只有图标(参照深墨胶囊图), 要看名字再打开
                    SettingRow(
                        shown = step > 2,
                        icon = chaosIcon(ChaosIcon.Home),
                        container = s.primaryContainer,
                        onContainer = s.onPrimaryContainer,
                        title = "底栏文字",
                        hint = "在底部导航栏显示各页名称",
                        control = {
                            Switch(
                                checked = UiPrefs.navLabels,
                                onCheckedChange = { UiPrefs.setNavLabels(it) },
                            )
                        },
                    )
                }

                // ---- 制作默认值: 字集行 / chip 块 / 归一化行 / 字号行 / 滑杆块
                SectionHeader("制作默认值", chaosIcon(ChaosIcon.Tune))
                SettingGroup {
                    SettingRow(
                        shown = step > 3,
                        icon = chaosIcon(ChaosIcon.Charset),
                        container = s.secondaryContainer,
                        onContainer = s.onSecondaryContainer,
                        title = "字集",
                        hint = "新建字体包时的起点，制作页上随时可改",
                    )
                    SettingBlock(shown = step > 4) { KindChips() }
                    SettingRow(
                        shown = step > 5,
                        icon = chaosIcon(ChaosIcon.LineHeight),
                        container = s.secondaryContainer,
                        onContainer = s.onSecondaryContainer,
                        title = "度量归一化",
                        hint = "行高对齐系统字体 1.326em",
                        control = {
                            Switch(
                                checked = UiPrefs.defaultNormalize,
                                onCheckedChange = { UiPrefs.setDefaultNormalize(it) },
                            )
                        },
                    )
                    SettingRow(
                        shown = step > 6,
                        icon = chaosIcon(ChaosIcon.FontSize),
                        container = s.secondaryContainer,
                    onContainer = s.onSecondaryContainer,
                    title = "预览字号",
                    hint = "样张默认大小",
                )
                    SettingBlock(shown = step > 7) { PreviewSpSlider() }
                }

                SectionHeader("关于", chaosIcon(ChaosIcon.SectionAbout))
                AboutBlock(about, shown = step > 7)
                Spacer(Modifier.height(Spacing.xxxl))
            }
        }
    }
}

/**
 * 一行设置：圆形头图 + 标题 + 说明 + 右侧控件。
 *
 * 用官方的 [ListItem]，不再自己拼"Surface + Row + 两段文字 + Spacer"。三条理由：
 *   1. 内边距、头图与文字之间的间距、文字样式走官方 token，不会跟系统其它列表长得不一样；
 *   2. 四路文字色**每一路都显式给** —— 容器色是我们自己的色场，默认那套是配 colorScheme 的，
 *      混着用会读不出来（同 inkOn 那条教训）；
 *   3. 用**默认形状**（四角全圆），行与行之间留缝。
 *
 * 关于**不**用 `segmentedShapes` 做连续叠：试过，实测三块高度 65 / 73 / 84dp，
 * 叠缝处两个小圆角对顶还挤出一个"腰"（左边缘内缩 10px），整叠读起来是锯齿。
 * 那个函数要求组内各项**等高、内边距同一套**；而这一页混着单行、双行说明和控件块，
 * 高度天然不齐。参考图里的行也是**分开的独立圆角卡 + 留缝**，只有最底下一对才是并排的。
 */
@Composable
private fun SettingRow(
    shown: Boolean,
    icon: Painter,
    container: Color,
    onContainer: Color,
    title: String,
    hint: String,
    control: @Composable (() -> Unit)? = null,
) {
    val t = enterT(shown)
    val tone = LocalPageTone.current
    // **逐行不同底色**: 行的底色不是一律 tone.card, 而是从**这一行自己的头图色**里取一点
    // 混进来 —— 参考图里那几行分别是薰衣草 / 奶油 / 粉, 同族但各有区别, 一列看下来才不闷。
    // 混的比例压得很低(0.30), 保证 onField 的对比度不被搞坏。
    val rowColor = remember(tone.card, container) { lerp(tone.card, container, 0.30f) }
    ListItem(
        modifier = Modifier.fillMaxWidth().enterLayer(t),
        leadingContent = {
            // 头图用**正圆**，与参考里每个条目的 logo 一致；图标色显式配 onContainer，
            // 不写就继承 onSurface(深色)，落在中深色容器上几乎看不见
            Box(
                Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(container),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = onContainer, modifier = Modifier.size(20.dp))
            }
        },
        trailingContent = control,
        supportingContent = {
            Text(hint, style = MaterialTheme.typography.labelMedium)
        },
        // **必须显式给形状**。`ListItem` 的默认形状来自 `ListTokens.ItemContainerExpressiveShape`
        // = `CornerExtraSmall`（源码实测），落到我们主题里就是 extraSmall 那几个 dp ——
        // 实测渲染出来约 2.9dp, 几乎是方角。而这一页其它卡和 App 里别的卡都是 extraLarge(28dp),
        // 于是同一组里出现两种圆角语言, 看着就是"圆角很难看"。
        // 统一到 App 那一套。
        shapes = ListItemDefaults.shapes(shape = MaterialTheme.shapes.extraLarge),
        colors = ListItemDefaults.colors(
            containerColor = rowColor,
            contentColor = tone.onField,
            leadingContentColor = onContainer,
            supportingContentColor = tone.muted,
            trailingContentColor = tone.onField,
        ),
        content = {
            Text(
                title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
            )
        },
    )
}

/**
 * 整行控件（分段按钮 / 一排 chip / 滑杆）。
 *
 * **不再给它一张卡**：原来控件块与行一样是通栏卡，于是"没有右侧控件的行 + 控件块"
 * 变成连着两块同色、各自半空的板，整页读起来就是一堵大板墙（用户说难看就是这个）。
 * 参考图里的行根本没有"卡下面再挂一个控件"这种结构。
 *
 * 现在的做法是让控件**落在色场上**，左边距与行的头图对齐（`ListItemStartPadding = 16dp`），
 * 于是它读起来像"上一行的补充控件"而不是另一张卡。整页因此少掉三块板。
 */
@Composable
private fun SettingBlock(
    shown: Boolean,
    content: @Composable () -> Unit,
) {
    val t = enterT(shown)
    Box(
        Modifier
            .fillMaxWidth()
            .enterLayer(t)
            .padding(start = Spacing.l, end = Spacing.xs, top = Spacing.xs),
    ) { content() }
}

/** 一组设置：组内每张卡留 [Spacing.s] 的缝，与参考图一样是"分开的独立卡" */
@Composable
private fun SettingGroup(content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(Spacing.s),
        content = content,
    )
}

/**
 * 通用分段胶囊: **一条胶囊里装几个 pill**, 选中那块是一个**滑过去**的实心胶囊。
 *
 * 不用 `SingleChoiceSegmentedButtonRow`: 它是被这套设计语言替代掉的旧组件
 * (分段之间靠分隔线切开, 在色场上读成一条灰条), 而且等宽会把"浅色"这种两字标签拉得很空。
 *
 * 动效是这个控件的关键, 缺了它切换就是"两块颜色瞬间互换", 一眼很廉价:
 *   - 指示块**位移**走空间 spring(可打断、有回弹);
 *   - 颜色**不参与**位移的弹性曲线 —— 颜色用空间 spring 会冲过目标色再回弹。
 */
@Composable
private fun SegmentedCapsule(
    labels: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
) {
    val tone = LocalPageTone.current
    val haptics = LocalHapticFeedback.current
    val gap = Spacing.xs
    // 同心圆角: 内圆角半径 **必须**等于外圆角半径减内缩(20 - 6 = 14)。
    // 之前外壳和指示块都是胶囊(CircleShape), 这个关系根本表达不出来 ——
    // 两个胶囊套在一起, 四角处的间隙会忽宽忽窄, 看着就是"脏"。
    val inset = 6.dp
    val trackShape = RoundedCornerShape(20.dp)
    val pillShape = RoundedCornerShape(14.dp)

    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            // 轨道用**容器色**而不是"底色上叠 10% 白/黑": 后者在浅灰底上几乎没形,
            // 读起来像一块脏印子。容器色才让它是一只实实在在的控件。
            .clip(trackShape)
            .background(tone.capsule)
            .padding(inset),
    ) {
        val n = labels.size
        val itemW = (maxWidth - gap * (n - 1)) / n
        val trackH = 40.dp
        val x by animateDpAsState(
            targetValue = (itemW + gap) * selectedIndex,
            animationSpec = MaterialTheme.motionScheme.defaultSpatialSpec(),
            label = "segX",
        )
        Box(
            Modifier
                .offset(x = x)
                .width(itemW)
                .height(trackH)
                .clip(pillShape)
                .background(tone.deep),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
            labels.forEachIndexed { i, label ->
                val sel = i == selectedIndex
                Box(
                    Modifier
                        .width(itemW)
                        .height(trackH)
                        .clip(pillShape)
                        .clickable {
                            if (!sel) {
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                onSelect(i)
                            }
                        }
                        .semantics { role = Role.Tab },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        label,
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = if (sel) FontWeight.Bold else FontWeight.Medium,
                        color = if (sel) tone.onDeep else tone.muted,
                    )
                }
            }
        }
    }
}

@Composable
private fun AppearanceSegments() {
    val labels = listOf("跟随系统", "浅色", "深色")
    SegmentedCapsule(labels, Appearance.entries.indexOf(UiPrefs.appearance)) { i ->
        UiPrefs.setAppearance(Appearance.entries[i])
    }
}

@Composable
private fun StyleSegments() {
    val labels = listOf("默认", "MD3")
    SegmentedCapsule(labels, ThemeStyle.entries.indexOf(UiPrefs.themeStyle)) { i ->
        UiPrefs.setThemeStyle(ThemeStyle.entries[i])
    }
}

@Composable
private fun KindChips() {
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
        FilterChip(
            selected = UiPrefs.defaultKind == Charset.Kind.SIMPLIFIED,
            onClick = { UiPrefs.setDefaultKind(Charset.Kind.SIMPLIFIED) },
            label = { Text("精简 ${Charset.required.size / 1000}k") },
            leadingIcon = { Icon(chaosIcon(ChaosIcon.Charset), null, Modifier.size(16.dp)) },
            // 胶囊: 与主题那组同一种形状, 不再是一堆圆角矩形
            shape = CircleShape,
        )
        FilterChip(
            selected = UiPrefs.defaultKind == Charset.Kind.WITH_TRADITIONAL,
            onClick = { UiPrefs.setDefaultKind(Charset.Kind.WITH_TRADITIONAL) },
            label = { Text("繁体 +${Charset.big5.size / 1000}k") },
            leadingIcon = { Icon(chaosIcon(ChaosIcon.World), null, Modifier.size(16.dp)) },
            shape = CircleShape,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PreviewSpSlider() {
    var v by remember { mutableStateOf(UiPrefs.defaultPreviewSp) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Slider(
            value = v,
            onValueChange = { v = it },
            onValueChangeFinished = { UiPrefs.setDefaultPreviewSp(v) },
            valueRange = 16f..40f,
            modifier = Modifier.weight(1f),
        )
        Spacer(Modifier.width(Spacing.m))
        Text(
            "${v.toInt()}",
            style = MaterialTheme.typography.labelLarge.tabular(),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(28.dp),
        )
    }
}

/** 关于: 数字全部从素材现读, 不写死(写死就会和主包漂移) */
@Composable
private fun AboutBlock(about: Assets.About?, shown: Boolean) {
    val t = enterT(shown)
    val tone = LocalPageTone.current
    var showLicenses by remember { mutableStateOf(false) }
    var showPrivacy by remember { mutableStateOf(false) }
    Surface(
        shape = MaterialTheme.shapes.extraLarge,
        color = tone.card,
        modifier = Modifier
            .fillMaxWidth()
            .enterLayer(t),
    ) {
        Column(
            Modifier.padding(Spacing.l),
            verticalArrangement = Arrangement.spacedBy(Spacing.m),
        ) {
            Text(
                "Chaos 投递包制作台",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = tone.onField,
            )
            Text(
                "为小米手环 10 Pro（固件 3.101.043）制作字体与桌面图标投递包。",
                style = MaterialTheme.typography.bodyMedium,
                color = tone.muted,
            )
            // 数字不再排成一串小票, 而是**两张并排的半宽卡** —— 参考图末排那种"裂成两半"
            // 的排法: 一行里放两个同级事实, 一眼扫完, 也不再是清一色的通栏块。
            val facts = buildList {
                about?.let {
                    add(Triple(chaosIcon(ChaosIcon.Pin), it.mainPkg, "主包包号"))
                    add(Triple(chaosIcon(ChaosIcon.Chip), "%.0f KB".format(it.koBytes / 1024.0), "内核模块"))
                    add(Triple(chaosIcon(ChaosIcon.Tag), "%.0f KB".format(it.iconBytes / 1024.0), "应用图标"))
                    add(
                        Triple(
                            chaosIcon(ChaosIcon.Grid),
                            // 系统原图标是逆向固件得来的、不可再分发, 所以公开构建里就是空的
                            if (it.stockIcons == 0) "未内置"
                            else "${it.stockIcons}/${IconSpec.SLOTS.size}",
                            "系统原图标",
                        ),
                    )
                }
                add(Triple(chaosIcon(ChaosIcon.Flask), "${IconSpec.CANVAS}²", "图标画布"))
                add(Triple(chaosIcon(ChaosIcon.Verified), BuildConfig.VERSION_NAME, "App 版本"))
            }
            facts.chunked(2).forEach { pair ->
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.m)) {
                    pair.forEach { (icon, value, label) ->
                        StatCard(icon, value, label, Modifier.weight(1f))
                    }
                    // 奇数个时补一个等宽的空位, 免得最后一张卡被拉成整宽
                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                }
            }

            // 两处"别人的东西"都必须在界面上说清: MiSans 的许可要求"在软件中特别注明",
            // 而"原图"槽位显示的是从小米固件里解出来的图标, 不注明就会被当成自有素材。
            // 许可与第三方声明的全文放在弹层里(文本由构建期从仓库同步进 assets)。
            Text(
                "预览图使用小米 MiSans 字体渲染。「原图」槽位显示的是从小米固件资源包里解出的" +
                    "手环应用图标，只作本地对照。本应用按 AGPL-3.0 发布，第三方组件各有各的许可。",
                style = MaterialTheme.typography.bodySmall,
                color = tone.muted,
            )
            TextButton(
                onClick = { showLicenses = true },
                modifier = Modifier.align(Alignment.Start),
            ) {
                Text("开源许可与第三方声明")
            }
            TextButton(
                onClick = { showPrivacy = true },
                modifier = Modifier.align(Alignment.Start),
            ) {
                Text("隐私政策")
            }
        }
    }

    if (showLicenses) LicensesDialog(onDismiss = { showLicenses = false })
    if (showPrivacy) PrivacyPolicyDialog(onDismiss = { showPrivacy = false })
}

/** 半宽事实卡: 圆形图标 + 值(强) + 标签(弱) */
@Composable
private fun StatCard(
    icon: Painter,
    value: String,
    label: String,
    modifier: Modifier = Modifier,
) {
    val tone = LocalPageTone.current
    Row(
        modifier = modifier
            .clip(MaterialTheme.shapes.large)
            .background(tone.capsule)
            .padding(horizontal = Spacing.m, vertical = Spacing.s),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.s),
    ) {
        Icon(icon, contentDescription = null, tint = tone.muted, modifier = Modifier.size(20.dp))
        Column {
            Text(
                value,
                style = MaterialTheme.typography.titleSmall.tabular(),
                fontWeight = FontWeight.Bold,
                color = tone.onField,
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
