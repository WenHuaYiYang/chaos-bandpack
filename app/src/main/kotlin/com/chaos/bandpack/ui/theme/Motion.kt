package com.chaos.bandpack.ui.theme

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import android.provider.Settings
import kotlinx.coroutines.delay

/**
 * 系统动画缩放为 0(开发者选项里"关闭所有动画")时, 界面必须**立刻**到位而不是照播一遍。
 * Compose 不会自动尊重这个开关, 所以自己读。
 *
 * 注意 `Settings.Global` 里**没有** `ANIMATION_SCALE` 常量, 键名只能是这个字符串。
 */
@Composable
fun rememberAnimationsEnabled(): Boolean {
    val ctx = LocalContext.current
    return remember(ctx) {
        runCatching {
            Settings.Global.getFloat(ctx.contentResolver, "global_animation_scale", 1f) > 0f
        }.getOrDefault(true)
    }
}

/**
 * 逐段入场的"已经出现几段": 每 [stepMs] 毫秒放行一段, 调用方按
 * `index < step` 决定某一行该不该显示。
 *
 * 为什么是**一个**效果而不是每行一个: @Composable 的 Modifier 工厂等价于已废弃的
 * `Modifier.composed`, 在里面放 `LaunchedEffect` 会随修饰符链重建被反复重启,
 * 实测入场会卡在 alpha=0 —— 元素占位但一个像素都不画。效果放在 Composable 顶层就没事。
 */
@Composable
fun rememberEnterStep(count: Int, stepMs: Long = 70L): Int {
    if (!rememberAnimationsEnabled()) return count
    var step by remember { mutableIntStateOf(0) }
    LaunchedEffect(count) {
        repeat(count) { i ->
            delay(stepMs)
            step = i + 1
        }
    }
    return step
}

/**
 * 某一行的入场进度。状态放在 Composable 里(不是修饰符工厂里), 所以安全。
 * 与 [rememberEnterStep] 配套: 调用方传 `shown = index < step`。
 */
@Composable
fun enterT(shown: Boolean): Float = animateFloatAsState(
    targetValue = if (shown) 1f else 0f,
    animationSpec = MaterialTheme.motionScheme.defaultEffectsSpec(),
    label = "enter",
).value

/** 把入场进度落成"淡入 + 轻微上移"。普通函数, 不是 @Composable 修饰符工厂 */
fun Modifier.enterLayer(t: Float): Modifier = graphicsLayer {
    alpha = t
    translationY = (1f - t) * 28f * density
}
