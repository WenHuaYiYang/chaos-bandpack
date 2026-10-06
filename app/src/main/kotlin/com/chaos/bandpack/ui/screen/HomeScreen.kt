package com.chaos.bandpack.ui.screen

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll

import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.colorResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chaos.bandpack.R
import com.chaos.bandpack.ui.LocalDeviceTarget
import com.chaos.bandpack.data.icon.IconSpec
import com.chaos.bandpack.data.make.IconMake
import com.chaos.bandpack.ui.component.ContentColumn
import com.chaos.bandpack.ui.theme.LocalPageTone
import com.chaos.bandpack.ui.theme.Spacing
import com.chaos.bandpack.ui.theme.enterLayer
import com.chaos.bandpack.ui.theme.enterT
import com.chaos.bandpack.ui.theme.inkOn
import com.chaos.bandpack.ui.theme.rememberEnterStep
import com.chaos.bandpack.ui.theme.ChaosIcon
import com.chaos.bandpack.ui.theme.chaosIcon

/**
 * 首页只做一件事: 选一条制作线。
 *
 * 版式照的是"编辑式开场": 整页一块色场(由外壳按去处算好发下来, 这里不自己挑底色),
 * 页首是**超大字 + 小 kicker + 右侧一片大圆**, 三样不在一条中轴上, 四周留白给足;
 * 往下才是两块制作卡。没有"怎么用"三段话 —— 图已经把话说明白了。
 *
 * 强调只给两处(页首那组, 以及两块卡各自的容器色), 其余全是同色系深浅与排版。
 * 系统栏由外层 ChaosApp 的 Scaffold 统一吃, 这里不再自己加 safeDrawing。
 */
@Composable
fun HomeScreen(onFont: () -> Unit, onIcon: () -> Unit) {
    val device = LocalDeviceTarget.current
    val tone = LocalPageTone.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
    ) {
        ContentColumn {
            Spacer(Modifier.height(Spacing.xxxl))
            Opening()
            Spacer(Modifier.height(Spacing.xxl))
            IconCollage()
            Spacer(Modifier.height(Spacing.xxl))

            // 两块卡 + 流程胶囊共用一个窄宽容器: 横屏/平板上整行拉到 720dp 会让色底空成
            // 一片(视觉区只有一百多 dp 高), 版式就散了 —— 横屏截图里真出现过
            NarrowCentered {
                // 逐段放行: 左卡 → 右卡 → 流程胶囊
                val step = rememberEnterStep(3)
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.m)) {
                    MakerTile(
                        shown = step > 0,
                        modifier = Modifier.weight(1f),
                        container = MaterialTheme.colorScheme.secondaryContainer,
                        title = "字体投递",
                        desc = "归一化 · 精简字集",
                        onClick = onFont,
                        visual = { FontSpecimen(it) },
                    )
                    MakerTile(
                        shown = step > 1,
                        modifier = Modifier.weight(1f),
                        container = MaterialTheme.colorScheme.tertiaryContainer,
                        title = "图标投递",
                        desc = "${IconSpec.all(device).size} 槽 · 桌面与系统图标",
                        onClick = onIcon,
                        visual = { StockIconMosaic(it) },
                    )
                }
                Spacer(Modifier.height(Spacing.xxl))
                FlowSteps(shown = step > 2)
            }

            Text(
                text = "Chaos · 为小米手环 ${device.label} 制作投递包",
                style = MaterialTheme.typography.labelSmall,
                color = tone.muted,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = Spacing.xxxl, bottom = Spacing.xxl),
            )
        }
    }
}

/**
 * 页首: 左边文字、右边圆片, 故意不对称。
 *
 * 标题走 displayMedium 加粗, 并且**主动断成两行** —— 超大字占住左上角是这套版式的主体,
 * 一行放不下时断行比缩字号有效(缩了就没有那个分量了)。
 * 上面那行小字是 kicker: 品牌拉丁名 + 大字距, 与下面的中文大字形成字号与字距的双重对比。
 */
@Composable
private fun Opening() {
    val tone = LocalPageTone.current
    val step = rememberEnterStep(2)

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.xl),
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                text = "C H A O S",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Medium,
                letterSpacing = 3.sp,
                color = tone.muted,
                modifier = Modifier.enterLayer(enterT(step > 0)),
            )
            Spacer(Modifier.height(Spacing.s))
            Text(
                text = "制作\n投递包",
                style = MaterialTheme.typography.displayMedium,
                fontWeight = FontWeight.Bold,
                lineHeight = 46.sp,
                color = tone.onField,
                modifier = Modifier.enterLayer(enterT(step > 1)),
            )
        }
        BrandDisc()
    }
}

/**
 * 散落图标拼贴: 用**真实的系统原图标**摆一片形状各异的浮块。
 *
 * 参考图里页首下面那一片散落的封面是整屏的视觉重心, 而且每个封面用的遮罩形状都不一样
 * (圆、胶囊、斜置方圆形、花形) —— 这就是"形状对比"最直接的用法。这里照同样的做法:
 * 取几张设备上真有的系统原图标, 各自套一个不同的遮罩、给一点旋转、错开高度。
 * 内容是**真的**(用户看到的就是能替换掉的那些图), 不是占位涂鸦。
 *
 * 入场逐个错峰: 一块一块浮上来并轻微放大(空间 spring)。数量与 [rememberEnterStep] 对齐。
 */
@Composable
private fun IconCollage() {
    val ctx = LocalContext.current
    val s = MaterialTheme.colorScheme
    val tone = LocalPageTone.current
    val step = rememberEnterStep(ITEMS.size)
    val bits = remember(ctx) {
        ITEMS.map { runCatching { IconMake.stockIcon(ctx, it.stem) }.getOrNull() }
    }
    // 浮块底板: 比色场亮一档的干净面, 让原图标自己的配色成为画面里的彩色
    val plate = lerp(tone.card, s.surface, 0.45f)

    Box(
        Modifier
            .fillMaxWidth()
            .height(212.dp),
        contentAlignment = Alignment.Center,
    ) {
        ITEMS.forEachIndexed { i, it ->
            val t = enterT(step > i)
            val pop by animateFloatAsState(
                targetValue = if (step > i) 1f else 0.82f,
                animationSpec = MaterialTheme.motionScheme.defaultSpatialSpec(),
                label = "bit$i",
            )
            Box(
                modifier = Modifier
                    .align(it.align)
                    .offset(x = it.dx, y = it.dy)
                    .rotate(it.rot)
                    .size(it.size)
                    // 缩放、透明度、位移、投影**必须在同一个 graphicsLayer 里**:
                    // 之前拆成两层(外层缩放/透明度、内层 shadow), 缩放动画走完时内层被
                    // 当成空操作优化掉, 投影就跟着没了 —— 表现就是"弹出时有阴影, 弹完
                    // 阴影突然消失"。合成一层之后投影和内容永远同生同灭。
                    .graphicsLayer {
                        scaleX = pop
                        scaleY = pop
                        alpha = t
                        translationY = (1f - t) * 24f * density
                        shadowElevation = 4.dp.toPx()
                        shape = it.shape
                        clip = true
                    }
                    .background(plate),
                contentAlignment = Alignment.Center,
            ) {
                val bmp = bits[i]
                if (bmp != null) {
                    Image(
                        bitmap = bmp,
                        contentDescription = null,
                        contentScale = ContentScale.Fit,
                        // 图标占盘子 0.84: 盘子要紧贴着图标的轮廓, 只当一圈描边用。
                        // 原来留 0.66, 盘子比图标大出一圈, 读起来是"两张不搭的形状叠在一起"。
                        modifier = Modifier.fillMaxSize(0.84f),
                    )
                }
            }
        }
    }
}

/** 一块浮块: 用哪张原图标、什么形状、摆哪儿、转多少度 */
private class CollageBit(
    val stem: String,
    val shape: androidx.compose.ui.graphics.Shape,
    val size: Dp,
    val align: Alignment,
    val dx: Dp = 0.dp,
    val dy: Dp = 0.dp,
    val rot: Float = 0f,
)

// 顶层常量, 所以形状只能用裸值 —— 这里不能调 MaterialTheme。
//
// 形状只用**圆和大圆角方**两种, 不再上九边饼干那类异形: 这些系统原图标自己的图形就是
// 圆的, 异形盘子套一个圆图标 = 两个不同轮廓叠在一起, 看着像画歪了(截图里就是这个效果)。
// 大小与旋转已经够制造错落, 形状再乱就是噪声。
private val ITEMS = listOf(
    CollageBit("music", CircleShape, 92.dp, Alignment.TopStart, dx = 4.dp, dy = 10.dp, rot = -8f),
    CollageBit("weather", RoundedCornerShape(34.dp), 104.dp, Alignment.TopCenter, dy = (-8).dp, rot = 5f),
    CollageBit("alarm", CircleShape, 88.dp, Alignment.TopEnd, dx = (-2).dp, dy = 30.dp, rot = -4f),
    CollageBit("heartrate", CircleShape, 84.dp, Alignment.BottomStart, dx = 30.dp, dy = (-8).dp, rot = 7f),
    CollageBit("camera", CircleShape, 76.dp, Alignment.BottomEnd, dx = (-24).dp, rot = -10f),
)

/**
 * 品牌圆片就是**桌面上那个图标本身**, 不是"照着它再画一个"。
 *
 * 画法只有一条规则, 而且这条规则就是启动器的规则: adaptive-icon 的画布是 108dp,
 * 启动器只画中间 **72dp** 的遮罩区。所以圆片直径取遮罩区那么大, 图按 108/72 即 1.5 倍
 * 直径铺上去再裁圆 —— 首页看到的就是遮罩边界内的那一块, 与装机后桌面**恒等**。
 * 这里不出现任何与素材填充率挂钩的数字: 之前那版拿一个写死的 dp 去凑图元占画布的比例,
 * 素材一缩就对不上(用户就是这么看出"不统一"的)。要调大小只改 [disc] 一个数。
 *
 *   1. 取 `ic_launcher_foreground` 而不是 `ic_launcher` —— 后者在 v26+ 命中
 *      `mipmap-anydpi-v26/ic_launcher.xml`(adaptive-icon), `painterResource` 只认
 *      VectorDrawable 和位图, 直接抛 IllegalArgumentException(真机崩过一次);
 *   2. 白底取 `@color/ic_launcher_background`, 与装机图标的背景层同一个值;
 *   3. 白圆贴在浅色场上会糊, 用**投影**抬起来, 不描边(描边就成占位头像了);
 *   4. 入场用**空间** spring 从 0.86 放大到位 —— 尺寸可以带阻尼回弹, 颜色与透明度不行。
 */
@Composable
private fun BrandDisc() {
    val disc = 104.dp
    val shown = rememberEnterStep(1) > 0
    val grow by animateFloatAsState(
        targetValue = if (shown) 1f else 0.86f,
        animationSpec = MaterialTheme.motionScheme.defaultSpatialSpec(),
        label = "disc",
    )
    Box(
        modifier = Modifier
            .size(disc)
            .graphicsLayer { scaleX = grow; scaleY = grow }
            .shadow(elevation = 10.dp, shape = CircleShape)
            .clip(CircleShape)
            .background(colorResource(R.color.ic_launcher_background)),
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painter = painterResource(R.mipmap.ic_launcher_foreground),
            contentDescription = "Chaos",
            // 必须 requiredSize —— size() 会被父级(圆片)的最大约束夹回去,
            // 图就缩成"整张 108 画布塞进圆里", 图元反而比桌面小一大截。
            modifier = Modifier.requiredSize(disc * 1.5f),
            contentScale = ContentScale.Fit,
        )
    }
}

/**
 * 制作线大卡: 上面一块**另一条色相**的视觉区(这块卡在干什么, 用图说),
 * 下面标题 + 一行短说明。整卡可点, 按压时轻微回缩。
 *
 * 卡体用色场同色系(tone.card), 视觉区才用该条线的容器色 —— 参考图里那组云端串流卡
 * 就是这么分的: 底是灰紫, 卡片各带一点紫、一点奶油、一点粉。
 */
@Composable
private fun MakerTile(
    shown: Boolean,
    modifier: Modifier,
    container: Color,
    title: String,
    desc: String,
    onClick: () -> Unit,
    visual: @Composable (TileInk) -> Unit,
) {
    val tone = LocalPageTone.current
    val s = MaterialTheme.colorScheme
    // 视觉区**不能**直接铺容器色: 动态取色下 secondaryContainer 可能是中深色, 铺成一大块
    // 就成糊在色场上的灰板(前两版截图就是这样)。参考图里大色块一律是淡彩, 饱和色只留给
    // 小元素 —— 所以把容器色往 surface 拉一半以上: 浅色模式下变淡彩, 深色模式下变深调,
    // 两种都读得通; 色相还在, 两条线的区分靠它。墨色再按亮度反推, 不会再出现白底白字。
    val ink = remember(tone, container, s) {
        val area = lerp(container, s.surface, 0.58f)
        val fg = area.inkOn(s)
        TileInk(area, fg, lerp(area, fg, 0.10f))
    }
    var pressed by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val enter = enterT(shown)
    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.97f else 1f,
        animationSpec = MaterialTheme.motionScheme.fastSpatialSpec(),
        label = "tilePress",
    )
    Column(
        modifier = modifier
            .enterLayer(enter)
            .graphicsLayer { scaleX = scale; scaleY = scale }
            .clip(MaterialTheme.shapes.extraLarge)
            .background(tone.card)
            .clickable(onClickLabel = "打开") {
                haptics.performHapticFeedback(HapticFeedbackType.ContextClick)
                onClick()
            }
            .padding(Spacing.m),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(116.dp)
                .clip(MaterialTheme.shapes.large)
                .background(ink.area)
                // 视觉区是装饰: TalkBack 不该把"永 A 字 01"当内容念出来
                .clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) { visual(ink) }
        Spacer(Modifier.height(Spacing.m))
        Text(
            title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = tone.onField,
        )
        Text(
            desc,
            style = MaterialTheme.typography.labelSmall,
            color = tone.muted,
            maxLines = 1,
        )
        Spacer(Modifier.height(Spacing.xs))
    }
}

/**
 * 字体卡的视觉区: 2x2 活字样本, 格子收成**方块圆角**; 右边图标卡的格子收成**圆**。
 * 两块卡同构但形状不同 —— 对上才像一套设计, 完全一样就重复了。
 */
@Composable
private fun FontSpecimen(ink: TileInk) {
    val cells = listOf("永" to 26.sp, "A" to 24.sp, "字" to 22.sp, "01" to 16.sp)
    MosaicFrame(ink, MaterialTheme.shapes.large) { i ->
        Text(
            cells[i].first,
            fontSize = cells[i].second,
            fontWeight = if (i % 2 == 0) FontWeight.Medium else FontWeight.Bold,
            color = ink.fg,
            maxLines = 1,
        )
    }
}

/** 图标卡的视觉区: 2x2 真实系统原图标, 格子收成圆 —— 桌面图标本来就是圆的 */
@Composable
private fun StockIconMosaic(ink: TileInk) {
    val ctx = LocalContext.current
    val cells = remember(ctx) {
        listOf("activities", "alarm", "camera", "heartrate").map { IconMake.stockIcon(ctx, it) }
    }
    MosaicFrame(ink, CircleShape) { i ->
        val bmp: ImageBitmap? = cells[i]
        if (bmp != null) {
            Image(
                bitmap = bmp,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.padding(Spacing.s),
            )
        } else {
            Icon(
                chaosIcon(ChaosIcon.Dashboard),
                contentDescription = null,
                tint = ink.fg,
                modifier = Modifier.size(22.dp),
            )
        }
    }
}

/**
 * 两卡共用的 2x2 格子框。
 *
 * 格底**不写死浅色**: 动态取色下容器色可能是中深色, 拿 surfaceContainerLowest 当格底
 * 配 onXxxContainer 当字色, 用错一次就是白底白字(截图里真出现过)。
 * 改成"在该条线自己的容器色上往 on 色挪 12%" —— 同色系里深一档, 读起来像一个凹下去的井,
 * 深浅色与换壁纸都成立, 也不会串到页面色场的另一个色相上去。
 */
@Composable
private fun MosaicFrame(ink: TileInk, cellShape: Shape, content: @Composable (Int) -> Unit) {
    Column(
        modifier = Modifier.size(100.dp),
        verticalArrangement = Arrangement.spacedBy(Spacing.s),
    ) {
        repeat(2) { r ->
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
                repeat(2) { c ->
                    Box(
                        modifier = Modifier
                            .size(46.dp)
                            .clip(cellShape)
                            .background(ink.cell),
                        contentAlignment = Alignment.Center,
                    ) { content(r * 2 + c) }
                }
            }
        }
    }
}

/** 一块制作卡视觉区要用的三种墨色, 由 [MakerTile] 一次算好传进去 */
@Immutable
private class TileInk(val area: Color, val fg: Color, val cell: Color)

/**
 * 流程三步: 节点头 + 细连线。
 *
 * 原来是"一条胶囊里装三个一模一样的圆" —— 三个同尺寸同色的圆既没有先后也没有主次,
 * 读起来就是三块灰饼(用户直接说丑)。流程条要传达的是**方向**: 所以第一步用实色圆起头,
 * 后面两步退成浅底, 中间拉一条细线把方向连起来。胶囊那层容器也就没必要了。
 */
@Composable
private fun FlowSteps(shown: Boolean) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .enterLayer(enterT(shown)),
        verticalAlignment = Alignment.Top,
    ) {
        FlowNode(chaosIcon(ChaosIcon.Download), "备素材", lead = true)
        FlowRail()
        FlowNode(chaosIcon(ChaosIcon.Tune), "出包")
        FlowRail()
        FlowNode(chaosIcon(ChaosIcon.Send), "投递")
    }
}

@Composable
private fun FlowNode(icon: Painter, label: String, lead: Boolean = false) {
    val tone = LocalPageTone.current
    Column(
        modifier = Modifier.width(84.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.s),
    ) {
        Box(
            modifier = Modifier
                .size(52.dp)
                .clip(CircleShape)
                .background(if (lead) tone.deep else tone.card),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = if (lead) tone.onDeep else tone.onField,
                modifier = Modifier.size(24.dp),
            )
        }
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = if (lead) FontWeight.Bold else FontWeight.Medium,
            color = if (lead) tone.onField else tone.muted,
        )
    }
}

/** 两步之间的细连线, 顶边对齐到节点头的圆心高度 */
@Composable
private fun RowScope.FlowRail() {
    val tone = LocalPageTone.current
    Box(
        Modifier
            .weight(1f)
            .padding(top = 25.dp, start = Spacing.xs, end = Spacing.xs)
            .height(2.dp)
            .clip(CircleShape)
            .background(lerp(tone.field, tone.onField, 0.16f)),
    )
}

/**
 * 窄宽居中容器: 首页这两块卡是"图 + 两个短标签", 横向拉宽只会拉长空色底而不是更多信息,
 * 所以比正文阅读宽度(720)再收一档。
 */
@Composable
private fun NarrowCentered(content: @Composable ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Column(
            modifier = Modifier.widthIn(max = 520.dp),
            content = content,
        )
    }
}
