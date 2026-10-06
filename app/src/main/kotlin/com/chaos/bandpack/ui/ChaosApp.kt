package com.chaos.bandpack.ui

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape

import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
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
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.chaos.bandpack.data.Incoming
import com.chaos.bandpack.data.displayNameOf
import com.chaos.bandpack.ui.screen.StudioWorkspace
import com.chaos.bandpack.ui.component.StudioToolbar
import com.chaos.bandpack.ui.component.FloatingDeviceSwitcher
import com.chaos.bandpack.ui.screen.FontDraft
import com.chaos.bandpack.ui.screen.FontMakerScreen
import com.chaos.bandpack.ui.screen.HomeScreen
import com.chaos.bandpack.ui.screen.IconDraft
import com.chaos.bandpack.ui.screen.IconMakerScreen
import com.chaos.bandpack.ui.screen.SettingsScreen
import com.chaos.bandpack.ui.theme.ChaosTheme
import com.chaos.bandpack.ui.theme.LocalPageTone
import com.chaos.bandpack.ui.theme.PageTone
import com.chaos.bandpack.ui.theme.Spacing
import com.chaos.bandpack.ui.theme.UiPrefs
import com.chaos.bandpack.ui.theme.rememberPageTone
import com.chaos.bandpack.ui.theme.ChaosIcon
import com.chaos.bandpack.ui.theme.chaosIcon

/** 四个同级去处, 用枚举当路由(只有两层, 不值得引 navigation-compose) */
enum class Dest { HOME, FONT, ICON, SETTINGS }

/**
 * 应用外壳: 整页色场 + 浮动胶囊导航(首页 / 字体 / 图标 / 设置) + 内容区。
 *
 * 为什么是标签页而不是"首页推二级页": 两条制作线是同级入口, 用户会在它们之间来回对照
 * (比如先看图标包多大, 再回来看字体包)。标签页带来一个必须解决的真问题 ——
 * **切走再切回来不能丢工作区**, 所以 [FontDraft] / [IconDraft] 提到这里记住。
 *
 * 色场由这里按去处算一份([PageTone])并从 [LocalPageTone] 发下去: 页面自己不再挑颜色,
 * 也不会出现"这页灰底那页白底"。色场画在最外层且吃满整屏, 系统栏下面同样是这个颜色。
 *
 * 系统栏的顶部内边距由这里的外层 Scaffold 吃一次, 里面的页面不再自己加 safeDrawing,
 * 否则顶部会空出一大条。
 */
@Composable
fun ChaosApp() {
    ChaosTheme {
        val ctx = LocalContext.current
        var dest by remember { mutableStateOf(Dest.HOME) }
        val fontDraft = remember { FontDraft() }
        val iconDraft = remember { IconDraft() }
        val workspace = remember { StudioWorkspace(iconDraft, fontDraft) }
        // 外面送进来的文件(分享/打开): 按类型直接切到对应标签页
        var incoming by remember { mutableStateOf<Uri?>(null) }
        var incomingPack by remember { mutableStateOf<Uri?>(null) }

        LaunchedEffect(Incoming.sequence) {
            val source = Incoming.take() ?: return@LaunchedEffect
            val u = source.uri
            val mime = runCatching { ctx.contentResolver.getType(u) }.getOrNull()
            val name = displayNameOf(ctx, u)
            val kind = Incoming.kindOf(u, mime, name) ?: Incoming.kindOf(u, source.mime, name)
            when (kind) {
                Incoming.Kind.FONT -> { incoming = u; dest = Dest.FONT }
                Incoming.Kind.IMAGE -> { incoming = u; dest = Dest.ICON }
                Incoming.Kind.PACK -> { incomingPack = u }
                null -> { /* 认不出是什么, 留在首页让用户自己选 */ }
            }
        }

        // 系统返回: 不在首页就先回首页(标签之间返回不等于退出)
        BackHandler(enabled = dest != Dest.HOME) { dest = Dest.HOME }

        // 每个去处一条色相: 首页 primary、字体 secondary、图标 tertiary、设置中性。
        // 四条制作线一眼分得清, 不用看标题。
        val s = MaterialTheme.colorScheme
        val tone: PageTone = when (dest) {
            Dest.HOME -> rememberPageTone(s.primaryContainer, s.onPrimaryContainer, s.primary, s.onPrimary)
            Dest.FONT -> rememberPageTone(s.secondaryContainer, s.onSecondaryContainer, s.secondary, s.onSecondary)
            Dest.ICON -> rememberPageTone(s.tertiaryContainer, s.onTertiaryContainer, s.tertiary, s.onTertiary)
            Dest.SETTINGS -> rememberPageTone(s.surfaceContainerHigh, s.onSurface, s.primary, s.onPrimary)
        }
        // 切标签时底色跟着换。颜色**必须**走 effects spring —— 空间 spring 带阻尼不足,
        // 颜色会冲过目标值再回弹, 看着就是闪一下。
        val field by animateColorAsState(
            tone.field,
            MaterialTheme.motionScheme.defaultEffectsSpec(),
            label = "field",
        )

        CompositionLocalProvider(LocalPageTone provides tone, LocalDeviceTarget provides workspace.device) {
            // 色场画在最外层且吃满整屏: 状态栏与导航条下面也是这个颜色, 不是白边
            Box(Modifier.fillMaxSize().background(field)) {
                Scaffold(
                    containerColor = Color.Transparent,
                    topBar = {
                        StudioToolbar(workspace, incomingPack, { incomingPack = null }) { project ->
                            dest = if (project.icons?.images?.isNotEmpty() == true) Dest.ICON else Dest.FONT
                        }
                    },
                    bottomBar = { NavCapsule(dest) { dest = it } },
                ) { bar ->
                    Box(Modifier.fillMaxSize().padding(bar)) {
                        // 动效方案在组合期读出来: 转场 lambda 不是 @Composable 作用域, 读不到 MaterialTheme
                        val motion = MaterialTheme.motionScheme
                        val spatial = motion.defaultSpatialSpec<IntOffset>()
                        val spatialFast = motion.fastSpatialSpec<IntOffset>()
                        val effects = motion.defaultEffectsSpec<Float>()
                        val effectsFast = motion.fastEffectsSpec<Float>()

                        AnimatedContent(
                            targetState = dest,
                            // 共享轴: 往右切标签从左往右滑入, 切回去反向。位移用 spatial spring
                            // (可打断、有回弹), 透明度用 effects spring。全程没有一处写死时长。
                            transitionSpec = {
                                val dir = if (targetState.ordinal > initialState.ordinal) 1 else -1
                                (
                                    slideInHorizontally(spatial) { w -> dir * w / 6 } +
                                        fadeIn(effects)
                                    ).togetherWith(
                                    slideOutHorizontally(spatialFast) { w -> -dir * w / 10 } +
                                        fadeOut(effectsFast)
                                )
                            },
                            label = "dest",
                        ) { d ->
                            when (d) {
                                Dest.HOME -> HomeScreen(
                                    onFont = { dest = Dest.FONT },
                                    onIcon = { dest = Dest.ICON },
                                )
                                Dest.FONT -> FontMakerScreen(
                                    draft = fontDraft,
                                    autoUri = incoming,
                                    onAutoConsumed = { incoming = null },
                                )
                                Dest.ICON -> IconMakerScreen(
                                    draft = iconDraft,
                                    autoUri = incoming,
                                    onAutoConsumed = { incoming = null },
                                )
                                Dest.SETTINGS -> SettingsScreen()
                            }
                        }
                        FloatingDeviceSwitcher(workspace)
                    }
                }
            }
        }
    }
}

/**
 * 浮动导航条 —— 参考图的**形状**, 全 App 的**配色**: 一条卡片色的大圆角条浮在色场上,
 * 选中项是一块**几乎占满一格**的本页主色圆角块, 图标反白; 没选中就是 muted 的线性图标。
 *
 * 配色与全 App 统一: 底 = [PageTone.card]（色场上的卡片色）,
 * 指示块 = [PageTone.deep]（本页主色实色）+ 反白图标(onDeep), 没选中走 muted。
 * 只取参考图的**形状**(大指示块占满一格、图标居中), 不取它的深墨底。
 *
 * 文字默认不显示(参考图没有); 设置页"底栏文字"开关打开后才加一行小字,
 * 指示块随之加高把图标和文字一起包住。内圆角按"外圆角减内缩"取(同心圆角,
 * 与设置页 SegmentedCapsule 同一条规则), 不然四角间隙忽宽忽窄。
 */
@Composable
private fun NavCapsule(dest: Dest, onSelect: (Dest) -> Unit) {
    val tone = LocalPageTone.current
    val haptics = LocalHapticFeedback.current
    val showLabels = UiPrefs.navLabels

    val track = tone.card
    val thumb = tone.deep
    val idle = tone.muted
    val active = tone.onDeep

    Box(
        Modifier
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.navigationBars)
            .padding(horizontal = Spacing.l, vertical = Spacing.s),
    ) {
        // 外层固定大圆角(24dp)而不是全圆: 全圆套全圆会把指示块逼成药丸形。
        // 内块 18dp = 外 24 - 间隙 6: 块撑满整格后四向间隙一致, 两段弧平行同心。
        // 弧不能更大: 窄屏一格 ~87dp、块 87x58, 弧一大四边全是弧就成"豆"了;
        // 18dp 留出明显平直边, 才是"圆角方块"。
        BoxWithConstraints(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(24.dp))
                .background(track)
                .padding(6.dp),
        ) {
            val n = NavEntry.entries.size
            val gap = 6.dp
            // 块**撑满整格**(不再横向缩进): 之前块两侧各缩 12dp, 水平间隙 12 ≠
            // 垂直间隙 6, 选中首/尾格时块的直边对着条的弧, 两段弧对不齐 ——
            // 用户要的"放宽、跟外面的弧统一"就是这个。撑满后四向间隙都是
            // 外层 padding 的 6dp, 内角 18 = 外角 24 - 6, 弧处处平行同心。
            val itemW = (maxWidth - gap * (n - 1)) / n
            val thumbW = itemW
            // 文字开关切换时底栏要有动画反馈: 高度走空间 spring,
            // 文字在下面用竖直展开 + 淡入接住, 同时到位才不突兀。
            // 圆角与高度无关固定档, 与外层保持"外 24 / 内 18"的同心差。
            val thumbH by animateDpAsState(
                targetValue = if (showLabels) 58.dp else 48.dp,
                animationSpec = MaterialTheme.motionScheme.defaultSpatialSpec(),
                label = "navThumbH",
            )
            val thumbShape = RoundedCornerShape(18.dp)
            val selIdx = NavEntry.entries.indexOfFirst { it.dest == dest }.coerceAtLeast(0)
            val x by animateDpAsState(
                targetValue = (itemW + gap) * selIdx + (itemW - thumbW) / 2,
                animationSpec = MaterialTheme.motionScheme.defaultSpatialSpec(),
                label = "navX",
            )
            Box(
                Modifier
                    .align(Alignment.TopStart)
                    .offset(x = x)
                    .size(thumbW, thumbH)
                    .clip(thumbShape)
                    .background(thumb),
            )
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(gap),
            ) {
                NavEntry.entries.forEach { item ->
                    val sel = dest == item.dest
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                        modifier = Modifier
                            .weight(1f)
                            .height(thumbH)
                            .clip(thumbShape)
                            .clickable(
                                onClick = {
                                    if (!sel) {
                                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                        onSelect(item.dest)
                                    }
                                },
                            )
                            // TalkBack: 报成标签而不是一个普通按钮; 无文字模式下
                            // 图标的 contentDescription 就是唯一可读的名字
                            .semantics { role = Role.Tab },
                    ) {
                        Icon(
                            chaosIcon(item.icon),
                            contentDescription = item.label,
                            tint = if (sel) active else idle,
                            modifier = Modifier.size(24.dp),
                        )
                        // 文字的来去交给 AnimatedVisibility: visible 由开关驱动,
                        // 进出两个方向都有动画(写在外层 if 里退出时会被直接移除, 动画播不出来)。
                        // 竖直展开/收起(尺寸走空间 spring) + 淡入淡出(透明度走 effects spring);
                        // 竖直方向而不是整体缩放, 收起时文字是"缩回指示块里"而不是"被压扁"。
                        AnimatedVisibility(
                            visible = showLabels,
                            enter = fadeIn(MaterialTheme.motionScheme.defaultEffectsSpec()) +
                                expandVertically(MaterialTheme.motionScheme.defaultSpatialSpec()),
                            exit = fadeOut(MaterialTheme.motionScheme.fastEffectsSpec()) +
                                shrinkVertically(MaterialTheme.motionScheme.fastSpatialSpec()),
                        ) {
                            Text(
                                item.label,
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = if (sel) FontWeight.Bold else FontWeight.Medium,
                                color = if (sel) active else idle,
                                modifier = Modifier.padding(top = 3.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

/**
 * 导航栏的三项定义。顺序跟路由枚举的顺序一致, 转场方向也按它算。
 *
 * 这里存的是**语义图标 key** 而不是画好的 `Painter`: `chaosIcon` 是 @Composable 的
 * (要读当前风格), 而枚举常量在类初始化时求值, 那里没有组合上下文。
 * 画的时候再解析, 换风格时图标才会跟着换。
 */
private enum class NavEntry(
    val dest: Dest,
    val icon: ChaosIcon,
    val label: String,
) {
    Home(Dest.HOME, ChaosIcon.Home, "首页"),
    Font(Dest.FONT, ChaosIcon.Font, "字体"),
    Icon(Dest.ICON, ChaosIcon.Grid, "图标"),
    Settings(Dest.SETTINGS, ChaosIcon.Settings, "设置"),
}
