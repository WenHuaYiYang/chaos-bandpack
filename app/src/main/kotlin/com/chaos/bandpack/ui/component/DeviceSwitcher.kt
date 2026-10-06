package com.chaos.bandpack.ui.component

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.chaos.bandpack.data.DeviceTarget
import com.chaos.bandpack.data.icon.IconSpec
import com.chaos.bandpack.ui.theme.LocalPageTone
import com.chaos.bandpack.ui.theme.Spacing

/** 当前设备入口与选择面板，切换前展示素材的可用数量。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeviceSwitcher(
    current: DeviceTarget,
    enabled: Boolean,
    picked: Set<String>,
    onSelect: (DeviceTarget) -> Unit,
    modifier: Modifier = Modifier,
) {
    var choosing by remember { mutableStateOf(false) }
    val tone = LocalPageTone.current
    ExtendedFloatingActionButton(
        onClick = { if (enabled) choosing = true },
        modifier = modifier.semantics {
            contentDescription = "切换制作设备，当前小米手环 ${current.label}"
            if (!enabled) disabled()
        },
        containerColor = if (enabled) tone.deep else tone.card,
        contentColor = if (enabled) tone.onDeep else tone.muted,
    ) {
        Text(current.label, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
    }
    if (choosing) {
        ModalBottomSheet(onDismissRequest = { choosing = false },
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
                    val count = picked.count { IconSpec.stemOf(it, target) != null }
                    val retained = picked.count { key ->
                        IconSpec.stemOf(key, target) == null &&
                            !(key == "ctrl_dnd" && "ctrl_disturb" in picked && target == DeviceTarget.TEN_PRO)
                    }
                    DeviceOption(target, target == current, enabled, count, retained, picked.isNotEmpty()) {
                        onSelect(target)
                        choosing = false
                    }
                }
                Text("目标设备没有对应槽位的图标仍保留在工程里，切回原设备可继续使用。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
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
            Surface(
                modifier = Modifier.size(width = 48.dp, height = 64.dp),
                shape = RoundedCornerShape(Spacing.l),
                color = if (isSelected) colors.secondary else colors.surfaceContainerHighest,
                contentColor = if (isSelected) colors.onSecondary else colors.onSurfaceVariant,
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(if (target == DeviceTarget.TEN_PRO) "10" else "9",
                        style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                }
            }
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
