package com.chaos.bandpack.ui.component

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.chaos.bandpack.data.icon.Dgf1
import kotlinx.coroutines.delay

/** Only the opened preview animates; stopping the activity pauses its timer. */
@Composable
fun AnimatedIconDialog(bytes: ByteArray, onDismiss: () -> Unit) {
    val animation = remember(bytes) { Dgf1.parse(bytes) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var foreground by remember(lifecycle) { mutableStateOf(lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) }
    var playing by remember(bytes) { mutableStateOf(true) }
    var frame by remember(bytes) { mutableIntStateOf(0) }
    var rounds by remember(bytes) { mutableLongStateOf(0) }
    var replay by remember { mutableIntStateOf(0) }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, _ -> foreground = lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED) }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(bytes, playing, foreground, replay) {
        if (!playing || !foreground) return@LaunchedEffect
        while (playing) {
            delay(animation.frames[frame].delayMs.toLong())
            if (frame + 1 == animation.frames.size) {
                rounds++
                if (animation.plays != 0L && rounds >= animation.plays) { playing = false; break }
                frame = 0
            } else frame++
        }
    }
    val image = remember(bytes, frame) {
        Bitmap.createBitmap(animation.pixels(frame), 96, 96, Bitmap.Config.ARGB_8888).asImageBitmap()
    }
    AlertDialog(onDismissRequest = onDismiss, title = { Text("动态图标预览") }, text = {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Image(image, "第 ${frame + 1} 帧", Modifier.size(192.dp))
            Text("${animation.frames.size} 帧 · %.2f 秒/轮 · ".format(animation.durationMs / 1000.0) +
                if (animation.plays == 0L) "无限循环" else "播放 ${animation.plays} 轮")
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                TextButton(onClick = { playing = !playing }) { Text(if (playing) "暂停" else "播放") }
                TextButton(onClick = { frame = 0; rounds = 0; playing = true; replay++ }) { Text("重播") }
            }
            Text("预览节奏受手机刷新率影响；导出保留每帧时长。", style = MaterialTheme.typography.bodySmall)
        }
    }, confirmButton = { TextButton(onClick = onDismiss) { Text("关闭") } })
}
