package com.chaos.bandpack.data.icon

import com.chaos.bandpack.data.DeviceTarget
import com.chaos.bandpack.data.pack.Cipk

/** 工程内保留源素材，导出时才转换目标规格。 */
object PortableIcons {
    data class Result(val icons: List<Cipk.Icon>, val selected: Int, val omitted: List<String>)

    fun forTarget(picked: Map<String, ByteArray>, target: DeviceTarget): Result {
        val selected = picked.filterKeys { IconSpec.stemOf(it, target) != null }
        val converted = selected.mapValues { (key, bytes) -> convert(bytes, IconSpec.stemOf(key, target)!!) }
        val omitted = picked.keys.filter { it !in selected && !(it == "ctrl_dnd" && "ctrl_disturb" in selected && target == DeviceTarget.TEN_PRO) }
        return Result(IconSpec.export(converted, target), selected.size, omitted)
    }

    fun convert(bytes: ByteArray, slot: IconSpec.Slot): ByteArray {
        val image = LvglIconCodec.decode(bytes)
        val nine = bytes[0].toInt() and 255 != 0x19
        if (image.width == slot.width && image.height == slot.height) {
            if (nine == (slot.device == DeviceTarget.NINE_PRO)) return bytes
            return if (slot.device == DeviceTarget.NINE_PRO) LvglIconCodec.bgra8(image.pixels, image.width, image.height)
            else LvglIconCodec.bgra(image.pixels, image.width, image.height)
        }
        require(slot.group == IconSpec.Group.DESKTOP && image.width == image.height && image.width in listOf(100, 112)) {
            "${slot.label}源图尺寸不支持转换：${image.width} × ${image.height}"
        }
        val content = if (image.width == 112) IntArray(100 * 100).also { out ->
            for (y in 0 until 100) System.arraycopy(image.pixels, (y + 6) * 112 + 6, out, y * 100, 100)
        } else image.pixels
        val canvas = IntArray(slot.width * slot.height)
        val margin = (slot.width - 100) / 2
        for (y in 0 until 100) System.arraycopy(content, y * 100, canvas, (y + margin) * slot.width + margin, 100)
        return if (slot.device == DeviceTarget.NINE_PRO) LvglIconCodec.bgra8(canvas, slot.width, slot.height)
        else LvglIconCodec.bgra(canvas, slot.width, slot.height)
    }

    fun label(key: String): String = (IconSpec.SLOTS + NineIconSpec.SLOTS).firstOrNull { it.stem == key }?.let {
        "${it.group.label} · ${it.label}"
    } ?: key
}
