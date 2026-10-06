package com.chaos.bandpack.ui.component

import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.chaos.bandpack.ui.screen.StudioWorkspace
import kotlin.math.roundToInt

/** 悬浮入口可拖动，位置限制在内容区域，不改变页面的布局尺寸。 */
@Composable
fun FloatingDeviceSwitcher(workspace: StudioWorkspace) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val width = with(density) { maxWidth.toPx() }
        val height = with(density) { maxHeight.toPx() }
        val margin = with(density) { 16.dp.toPx() }
        var measured by remember(density) {
            mutableStateOf(with(density) { IntSize(88.dp.roundToPx(), 56.dp.roundToPx()) })
        }
        var x by remember { mutableFloatStateOf(Float.NaN) }
        var y by remember { mutableFloatStateOf(Float.NaN) }
        val maxX = (width - measured.width - margin).coerceAtLeast(margin)
        val maxY = (height - measured.height - margin).coerceAtLeast(margin)
        val px = (if (x.isNaN()) maxX else x).coerceIn(margin, maxX)
        val py = (if (y.isNaN()) height * 0.4f else y).coerceIn(margin, maxY)
        val enabled = !workspace.busy && !workspace.icons.busy && !workspace.font.busy
        DeviceSwitcher(workspace.device, enabled, workspace.icons.picked.keys, workspace::selectDevice,
            modifier = Modifier.offset { IntOffset(px.roundToInt(), py.roundToInt()) }
                .onSizeChanged { measured = it }
                .pointerInput(maxX, maxY, margin) {
                    detectDragGestures(onDragStart = {
                        x = (if (x.isNaN()) maxX else x).coerceIn(margin, maxX)
                        y = (if (y.isNaN()) height * 0.4f else y).coerceIn(margin, maxY)
                    }) { change, delta ->
                        change.consume()
                        x = (x + delta.x).coerceIn(margin, maxX)
                        y = (y + delta.y).coerceIn(margin, maxY)
                    }
                })
    }
}
