package com.chaos.bandpack.ui.component

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MediumTopAppBar
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.TopAppBarScrollBehavior
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chaos.bandpack.ui.LocalWidthClass
import com.chaos.bandpack.ui.pagePadding
import com.chaos.bandpack.ui.theme.LocalPageTone
import com.chaos.bandpack.ui.theme.Spacing
import com.chaos.bandpack.ui.theme.enterLayer
import com.chaos.bandpack.ui.theme.enterT
import com.chaos.bandpack.ui.theme.rememberAnimationsEnabled
import kotlinx.coroutines.delay
import com.chaos.bandpack.ui.theme.ChaosIcon
import com.chaos.bandpack.ui.theme.chaosIcon

/**
 * 制作页(标签页)的统一外壳: **Medium** 顶栏(滚动折叠) + 内容区 + Snackbar。
 *
 * 顶栏变体按页面层级选: 首页是落地页没有顶栏, 两个制作页用 Medium —— 大标题把"我在哪"
 * 一眼说清, 滚起来再让位给内容。加了底部导航栏之后它们是**同级标签页**, 所以顶栏
 * 不再有返回箭头(返回箭头意味着"这是一条推出来的路径")。
 *
 * 顶栏与本页都不画底色: 色场由外壳(ChaosApp)画在最外层, 这里透明浮在上面。
 * 标题改成"kicker + 超大字"两行, 与首页那套开场同一个语法。
 *
 * **主动作不再是浮动 FAB**: 参考图里主行动作一律是又高又宽、贴着内容宽度的填充胶囊,
 * 而且放在内容流里而不是浮在角上。浮动 FAB 还有个实打实的毛病 —— 滚动时会压住
 * 网格那一格的标签, 所以这里改成 [ExportPill] 由各页自己放进内容末尾。
 *
 * 系统栏由外层 `ChaosApp` 的 Scaffold 吃一次, 这里 `contentWindowInsets = 0` 不再重复吃。
 *
 * [content] 会拿到 [TopAppBarScrollBehavior]; 里面的可滚动容器必须挂上
 * `Modifier.nestedScroll(behavior.nestedScrollConnection)`, 否则顶栏不会折叠。
 *
 * 瞬时反馈(处理结果/错误)走 Snackbar, 不再往页面里塞提示文字。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MakerScaffold(
    title: String,
    kicker: String,
    snackbar: SnackbarHostState = remember { SnackbarHostState() },
    actions: @Composable () -> Unit = {},
    content: @Composable (PaddingValues, TopAppBarScrollBehavior) -> Unit,
) {
    val tone = LocalPageTone.current
    val behavior = TopAppBarDefaults.enterAlwaysScrollBehavior(rememberTopAppBarState())
    Scaffold(
        containerColor = Color.Transparent,
        contentWindowInsets = WindowInsets(0),
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            MediumTopAppBar(
                title = {
                    Column {
                        Text(
                            kicker,
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Medium,
                            letterSpacing = 2.5.sp,
                            color = tone.muted,
                        )
                        Spacer(Modifier.height(Spacing.xs))
                        Text(
                            title,
                            style = MaterialTheme.typography.headlineLarge,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            color = tone.onField,
                        )
                    }
                },
                actions = { actions() },
                scrollBehavior = behavior,
                colors = TopAppBarDefaults.mediumTopAppBarColors(
                    containerColor = Color.Transparent,
                    scrolledContainerColor = Color.Transparent,
                ),
            )
        },
        content = { padding -> content(padding, behavior) },
    )
}

/**
 * 导出主按钮: **高胶囊 + 贴内容宽度**, 放在内容流末尾而不是浮在角上。
 *
 * material3 alpha 的组件里 `Button` 没有 `enabled` 之外的好办法表达"忙", 所以禁用态与
 * 加载态自己画: 禁用换中性底并把 `disabled` 写进语义让 TalkBack 也报出来;
 * 忙时图标位换成加载指示 —— 加载态必须有, 不能只把按钮变灰。
 * 标签里带上体积/张数, 导出前最后一眼就能确认"这是哪个包、多大"。
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun ExportPill(
    enabled: Boolean,
    label: String,
    busy: Boolean = false,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tone = LocalPageTone.current
    val live = enabled && !busy
    val haptics = LocalHapticFeedback.current
    // 按压态从 InteractionSource 读, 不自己存布尔: 手滑出边界时 interactionSource 会自己收
    val interaction = remember { MutableInteractionSource() }
    val isPressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (live && isPressed) 0.975f else 1f,
        animationSpec = MaterialTheme.motionScheme.fastSpatialSpec(),
        label = "pillPress",
    )
    Row(
        modifier = modifier
            .fillMaxWidth()
            .graphicsLayer { scaleX = scale; scaleY = scale }
            .clip(CircleShape)
            // 禁用态**不填色**, 只留一圈极淡的描边: 填了色它就是全屏最重的一块,
            // 偏偏它还是不可用的 —— 分量与可用性反了。空状态里那个实色按钮才是主次。
            .background(if (live) tone.deep else Color.Transparent)
            .border(
                width = if (live) 0.dp else 1.dp,
                color = if (live) Color.Transparent else lerp(tone.field, tone.muted, 0.35f),
                shape = CircleShape,
            )
            .then(
                if (live) {
                    Modifier.clickable(interactionSource = interaction) {
                        haptics.performHapticFeedback(HapticFeedbackType.ContextClick)
                        onClick()
                    }
                } else {
                    // semantics 里 disabled 是个函数不是属性: 只在禁用时挂
                    Modifier.semantics { disabled() }
                },
            )
            .padding(horizontal = Spacing.xl, vertical = Spacing.l),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.s, Alignment.CenterHorizontally),
    ) {
        // 前景色只在这一处声明, 图标/加载指示/文字全从 LocalContentColor 取。
        // 之前只给文字写了色、图标没跟着, 在实色底上就是一枚黑图标(实测)。
        val fg = if (live) tone.onDeep else tone.muted
        CompositionLocalProvider(LocalContentColor provides fg) {
            if (busy) LoadingIndicator(modifier = Modifier.size(20.dp))
            else Icon(chaosIcon(ChaosIcon.Save), contentDescription = null)
            Text(
                label,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

/**
 * 分节标题。放在内容**外面**(M3 列表的层级写法): 标题负责分组, 内容不用卡片也能分开,
 * 这样"卡 + 卡 + 卡"就消失了, 页面靠排版而不是靠容器切分。
 *
 * 带 [icon] 时左边给一枚同色系圆片徽标 —— 纯文字的小节标题在色场上是一排同样重量的
 * 灰字, 整页读起来就"素"; 徽标给了每一节一个彩色锚点, 滚动时也更抓得住位置。
 * 图标一律用平台自带的 Material 图标, 不自己画符号。
 */
@Composable
fun SectionHeader(text: String, icon: Painter? = null) {
    val tone = LocalPageTone.current
    Row(
        modifier = Modifier.padding(
            start = Spacing.xs,
            top = Spacing.xxl,
            bottom = Spacing.m,
        ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.s),
    ) {
        if (icon != null) {
            Box(
                modifier = Modifier
                    .size(28.dp)
                    .clip(CircleShape)
                    .background(tone.capsule),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = tone.onField, modifier = Modifier.size(16.dp))
            }
        }
        Text(
            text,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.Bold,
            color = tone.onField,
        )
    }
}

/**
 * 制作页的整体入场进度。用法是 `val t = enterPageT()` 之后把 `.enterLayer(t)` 挂到
 * **页面最外层那个容器**上。
 *
 * 为什么是整页一层而不是按分节错峰: 图标页的正文是 `LazyVerticalGrid`, 下面的分节要滚到
 * 才会被组合 —— 挂在分节上的话, 首屏之外那几节根本没有动画, 表现出来就是"只有第一节在弹"。
 * 挂在整页容器上一次解决, 滚下去的内容自然就在那儿, 不用再补一次动画。
 * 不做逐条目入场: 图标页有 35 格, 逐格入场会拖到下个世纪。
 *
 * 状态放在 Composable 里、返回一个 Float, **不能**做成 @Composable 的 Modifier 工厂 ——
 * 那等价于已废弃的 Modifier.composed, 修饰符链一重建 LaunchedEffect 就重启, 元素会卡在
 * alpha=0(本项目在设置页整页空白上栽过一次)。
 */
@Composable
fun enterPageT(): Float {
    val animate = rememberAnimationsEnabled()
    var shown by remember { mutableStateOf(!animate) }
    LaunchedEffect(animate) { if (animate) shown = true }
    return enterT(shown)
}

/**
 * 内容列: 宽屏下把内容卡在 [Spacing.contentMaxWidth] 内居中 —— 平板上一行文字拉满
 * 整屏是典型的"网页感", Android 应用的正文阅读宽度要有上限。
 */
@Composable
fun ContentColumn(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    val pad = LocalWidthClass.current.pagePadding
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Column(
            modifier = Modifier
                .widthIn(max = Spacing.contentMaxWidth)
                .fillMaxWidth()
                .padding(horizontal = pad),
            content = content,
        )
    }
}

