package com.chaos.bandpack.ui.component

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chaos.bandpack.data.DeviceTarget
import com.chaos.bandpack.data.icon.IconSpec
import com.chaos.bandpack.ui.theme.ChaosIcon
import com.chaos.bandpack.ui.theme.ChaosPalette
import com.chaos.bandpack.ui.theme.LocalPageTone
import com.chaos.bandpack.ui.theme.Spacing
import com.chaos.bandpack.ui.theme.chaosIcon

/** 已选图标在这台设备上还剩多少能导出, 剩下的留在工程里等切回去 */
private fun deviceStats(target: DeviceTarget, picked: Set<String>): Pair<Int, Int> {
    val count = picked.count { IconSpec.stemOf(it, target) != null }
    val retained = picked.count { key ->
        IconSpec.stemOf(key, target) == null &&
            !(key == "ctrl_dnd" && "ctrl_disturb" in picked && target == DeviceTarget.TEN_PRO)
    }
    return count to retained
}

/**
 * 设备选择面板。首页那对卡与制作页顶栏的芯片开的是同一份, 切换规则只在这里写一遍。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeviceSheet(
    visible: Boolean,
    current: DeviceTarget,
    enabled: Boolean,
    picked: Set<String>,
    onSelect: (DeviceTarget) -> Unit,
    onDismiss: () -> Unit,
) {
    if (!visible) return
    ModalBottomSheet(onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(
            Modifier.fillMaxWidth().widthIn(max = Spacing.contentMaxWidth)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.xxl).padding(bottom = Spacing.xxl),
            verticalArrangement = Arrangement.spacedBy(Spacing.l),
        ) {
            Text("选择制作设备", style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold)
            Text("切换导出规格，已选图标和字体会保留。",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            DeviceTarget.entries.forEach { target ->
                val (count, retained) = deviceStats(target, picked)
                DeviceOption(target, target == current, enabled, count, retained, picked.isNotEmpty()) {
                    onSelect(target)
                    onDismiss()
                }
            }
            Text("目标设备没有对应槽位的图标仍保留在工程里，切回原设备可继续使用。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun DeviceOption(
    target: DeviceTarget,
    isSelected: Boolean,
    enabled: Boolean,
    count: Int,
    retained: Int,
    hasIcons: Boolean,
    onSelect: () -> Unit,
) {
    val colors = MaterialTheme.colorScheme
    Surface(
        onClick = onSelect,
        enabled = enabled,
        modifier = Modifier.fillMaxWidth().semantics {
            role = Role.RadioButton
            selected = isSelected
        },
        shape = MaterialTheme.shapes.extraLarge,
        color = if (isSelected) colors.secondaryContainer else colors.surfaceContainer,
        contentColor = if (isSelected) colors.onSecondaryContainer else colors.onSurface,
        border = BorderStroke(1.dp, if (isSelected) colors.secondary else colors.outlineVariant),
    ) {
        Row(
            Modifier.padding(Spacing.l),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.l),
        ) {
            BandBadge(target, isSelected, colors.secondary, colors.surfaceContainerHighest)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text("小米手环 ${target.label}", style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold)
                Text("固件 ${target.firmware}", style = MaterialTheme.typography.bodySmall)
                if (hasIcons) Text(
                    if (retained == 0) "当前图标可导出 $count 张" else "可导出 $count 张 · $retained 张保留在工程",
                    style = MaterialTheme.typography.bodySmall,
                )
                if (target == DeviceTarget.NINE_PRO) Text("社区移植 · 设备端尚无真机验证",
                    style = MaterialTheme.typography.labelSmall, color = colors.onSurfaceVariant)
            }
            RadioButton(selected = isSelected, onClick = null, enabled = enabled)
        }
    }
}

/**
 * 一枚手环外形的徽标: 壳体 + 那块纯黑屏, 屏上写型号。
 *
 * 用真外形而不拿一枚通用图标顶, 是因为这一处回答的是"给哪台做" —— 形状自己就在答题。
 * 屏一律纯黑、字一律屏幕白(同 [ChaosPalette] 的口径): 跟着深浅色模式翻就不是那块屏了,
 * 而深色模式下的浅字才读得通。
 */
@Composable
private fun BandBadge(target: DeviceTarget, selected: Boolean, caseOn: Color, caseOff: Color) {
    val grown by animateFloatAsState(
        targetValue = if (selected) 1f else 0.94f,
        animationSpec = MaterialTheme.motionScheme.fastSpatialSpec(),
        label = "bandBadge",
    )
    Box(
        Modifier
            .size(width = 42.dp, height = 56.dp)
            .graphicsLayer { scaleX = grown; scaleY = grown }
            .clip(RoundedCornerShape(16.dp))
            .background(if (selected) caseOn else caseOff)
            .padding(4.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(ChaosPalette.SCREEN_BLACK),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            if (target == DeviceTarget.TEN_PRO) "10" else "9",
            style = MaterialTheme.typography.labelLarge,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            color = ChaosPalette.SCREEN_FG,
        )
    }
}

/**
 * 制作页顶栏的设备芯片: 把"我在给哪台做"这行说明变成入口。
 *
 * 放顶栏而不是再给一枚浮标, 依据是 M3 对 FAB 的两条限制 —— 承载"更适合工具栏的控件"要
 * 用工具栏, 且同一个动作不该在别处已有入口时再用 FAB 重复一遍。这里原本就在顶栏的
 * kicker 文字上, 只是它以前只是字, 点不动。
 */
@Composable
fun DeviceKickerChip(
    label: String,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    val tone = LocalPageTone.current
    Row(
        Modifier
            .clip(CircleShape)
            .background(if (enabled) tone.capsule else lerp(tone.capsule, tone.field, 0.6f))
            .semantics { contentDescription = "切换制作设备，当前 $label" }
            .clickable(enabled = enabled, onClickLabel = "切换设备", onClick = onClick)
            .padding(start = 10.dp, end = 12.dp, top = 4.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(
            chaosIcon(ChaosIcon.Chip),
            contentDescription = null,
            tint = if (enabled) tone.deep else tone.muted,
            modifier = Modifier.size(16.dp),
        )
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Medium,
            letterSpacing = 1.5.sp,
            color = if (enabled) tone.onField else tone.muted,
            maxLines = 1,
        )
    }
}

/**
 * 首页的设备选择: 两张并排的可选卡, 选中那张换成本页识别色并把勾浮出来。
 *
 * 设备是**工程属性**而不是这一屏的动作, 所以它是内容里的一对卡, 不再飘在屏幕中间:
 * M3 对 FAB 的口径是"本屏最重要的那一个动作", 并且要求不适合放进工具栏的控件别拿 FAB
 * 承载、别用 FAB 重复一个别处已经有的动作。之前那个可拖动、忙时变灰、四屏都悬在中间的
 * 气泡三条都撞上了。
 */
@Composable
fun DeviceChoiceRow(
    current: DeviceTarget,
    picked: Set<String>,
    onSelect: (DeviceTarget) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(Spacing.m)) {
        DeviceTarget.entries.forEach { target ->
            val (count, retained) = deviceStats(target, picked)
            DeviceChoice(
                target = target,
                isSelected = target == current,
                count = count,
                retained = retained,
                hasIcons = picked.isNotEmpty(),
                onClick = { onSelect(target) },
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun DeviceChoice(
    target: DeviceTarget,
    isSelected: Boolean,
    count: Int,
    retained: Int,
    hasIcons: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tone = LocalPageTone.current
    val haptics = LocalHapticFeedback.current
    val check by animateFloatAsState(
        targetValue = if (isSelected) 1f else 0f,
        animationSpec = MaterialTheme.motionScheme.defaultSpatialSpec(),
        label = "deviceChoiceCheck",
    )
    Column(
        modifier
            .clip(MaterialTheme.shapes.extraLarge)
            .background(if (isSelected) tone.accent else tone.card)
            .border(
                width = 1.dp,
                color = if (isSelected) tone.deep else lerp(tone.field, tone.muted, 0.28f),
                shape = MaterialTheme.shapes.extraLarge,
            )
            .clickable(onClickLabel = "选它", role = Role.RadioButton) {
                haptics.performHapticFeedback(HapticFeedbackType.ContextClick)
                onClick()
            }
            .semantics {
                selected = isSelected
                contentDescription = "小米手环 ${target.label}，固件 ${target.firmware}" +
                    if (isSelected) "，已选择" else ""
            }
            .padding(Spacing.l),
        verticalArrangement = Arrangement.spacedBy(Spacing.s),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BandBadge(target, isSelected, tone.deep, lerp(tone.field, tone.onField, 0.30f))
            // 勾是"选中"的第二道信号(颜色已经表过一次), 给色觉障碍与灰度截图留着。
            // 尺寸走空间 spring: 它可以回弹, 透明度同层跟着走才不会闪。
            Box(Modifier.size(26.dp), contentAlignment = Alignment.Center) {
                Box(
                    Modifier
                        .size(26.dp)
                        .graphicsLayer { scaleX = check; scaleY = check; alpha = check }
                        .clip(CircleShape)
                        .background(tone.deep),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        chaosIcon(ChaosIcon.Check),
                        contentDescription = null,
                        tint = tone.onDeep,
                        modifier = Modifier.size(16.dp),
                    )
                }
            }
        }
        Text(
            "小米手环 ${target.label}",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Bold,
            color = if (isSelected) tone.onAccent else tone.onField,
        )
        Text(
            "固件 ${target.firmware}",
            style = MaterialTheme.typography.labelSmall,
            color = if (isSelected) tone.onAccent else tone.muted,
        )
        Text(
            when {
                !hasIcons -> "${IconSpec.all(target).size} 个槽位"
                retained == 0 -> "已选图标可导出 $count 张"
                else -> "可导出 $count 张 · $retained 张留工程"
            },
            style = MaterialTheme.typography.labelSmall,
            color = if (isSelected) tone.onAccent else tone.muted,
            maxLines = 2,
        )
    }
}
