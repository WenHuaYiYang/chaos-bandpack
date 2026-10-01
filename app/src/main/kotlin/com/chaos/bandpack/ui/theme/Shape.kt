package com.chaos.bandpack.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

/**
 * 圆角层级。
 *
 * M3 Expressive 把圆角档**加长**了：在原来的 extraLarge 之上还有 `largeIncreased` /
 * `extraLargeIncreased` / `extraExtraLarge` 三档。大卡与强调容器要用这三档，
 * 不然整页的"圆"都停在同一水平，看不出表达层级。
 *
 * 各档相差约 1.3 到 1.4 倍，肉眼能分辨；不做"万物 16dp"。
 *
 * 注意：这里**只定义统一圆角**。Expressive 里"某个角不一样大"不是靠手搓一个
 * 固定形状实现的 —— 一是我之前按参考图猜了一版对角非对称，方向还猜错了；二是
 * 官方那套是**按状态变形**（见 `ListItemShapes`：normal / selected / pressed /
 * focused / hovered / dragged 各有自己的 Shape），形状随交互变化才是它的签名做法。
 * 需要那种效果时用组件自己的 shapes 参数，别在主题里造一个固定的怪形状。
 */
internal val ChaosShapes = Shapes(
    extraSmall = RoundedCornerShape(6.dp),
    small = RoundedCornerShape(10.dp),
    medium = RoundedCornerShape(14.dp),
    large = RoundedCornerShape(18.dp),
    // Expressive 新增的三档
    largeIncreased = RoundedCornerShape(22.dp),
    extraLarge = RoundedCornerShape(28.dp),
    extraLargeIncreased = RoundedCornerShape(34.dp),
    extraExtraLarge = RoundedCornerShape(48.dp),
)
