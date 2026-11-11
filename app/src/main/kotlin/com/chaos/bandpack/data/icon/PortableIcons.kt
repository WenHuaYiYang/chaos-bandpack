package com.chaos.bandpack.data.icon

import com.chaos.bandpack.data.DeviceTarget
import com.chaos.bandpack.data.pack.Cipk

/** 工程内保留源素材，导出时才转换目标规格。 */
object PortableIcons {
    data class Result(val icons: List<Cipk.Icon>, val selected: Int, val omitted: List<String>)

    fun forTarget(picked: Map<String, ByteArray>, target: DeviceTarget): Result {
        AnimatedIcons.validateProject(picked)
        val selected = picked.filterKeys { IconSpec.stemOf(it, target) != null }
        val converted = selected.mapValues { (key, bytes) -> convert(bytes, IconSpec.stemOf(key, target)!!) }
        val animations = if (target == DeviceTarget.TEN_PRO) picked.filterKeys(AnimatedIcons::isAnimationKey).mapKeys { AnimatedIcons.base(it.key) } else emptyMap()
        return Result(IconSpec.export(converted, target, animations), selected.size, omitted(picked, target))
    }

    fun omitted(picked: Map<String, ByteArray>, target: DeviceTarget): List<String> = omittedKeys(picked.keys, target)
    fun omittedKeys(keys: Set<String>, target: DeviceTarget): List<String> = keys.filter {
        IconSpec.stemOf(it, target) == null && !(target == DeviceTarget.TEN_PRO && AnimatedIcons.isAnimationKey(it) && AnimatedIcons.base(it) in AnimatedIcons.STEMS)
    }

    fun convert(bytes: ByteArray, slot: IconSpec.Slot): ByteArray {
        val image = LvglIconCodec.decode(bytes)
        val nine = bytes[0].toInt() and 255 != 0x19
        if (!nine && slot.device == DeviceTarget.TEN_PRO) return bytes
        if (image.width == slot.width && image.height == slot.height) {
            if (nine == (slot.device == DeviceTarget.NINE_PRO)) return bytes
            return if (slot.device == DeviceTarget.NINE_PRO) LvglIconCodec.bgra8(image.pixels, image.width, image.height)
            else LvglIconCodec.bgra(image.pixels, image.width, image.height)
        }
        require(slot.group == IconSpec.Group.DESKTOP && image.width == image.height && image.width in listOf(96, 100, 112)) {
            "${slot.label}源图尺寸不支持转换：${image.width} × ${image.height}"
        }
        val content = if (image.width == 112) IntArray(100 * 100).also { out ->
            for (y in 0 until 100) System.arraycopy(image.pixels, (y + 6) * 112 + 6, out, y * 100, 100)
        } else image.pixels
        val side = if (image.width == 112) 100 else image.width
        val canvas = IconConvert.fitCanvas(content, side, side, slot.width)
        return if (slot.device == DeviceTarget.NINE_PRO) LvglIconCodec.bgra8(canvas, slot.width, slot.height)
        else LvglIconCodec.bgra(canvas, slot.width, slot.height)
    }

    fun label(key: String): String = (IconSpec.SLOTS + NineIconSpec.SLOTS).firstOrNull { it.stem == AnimatedIcons.base(key) }?.let {
        "${it.group.label} · ${it.label}" + if (AnimatedIcons.isAnimationKey(key)) "动画" else ""
    } ?: key
}
