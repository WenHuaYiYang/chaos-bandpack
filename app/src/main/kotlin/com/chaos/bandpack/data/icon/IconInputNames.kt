package com.chaos.bandpack.data.icon

import com.chaos.bandpack.data.DeviceTarget

/** Group covers and animations before touching the workspace, regardless of picker order. */
object IconInputNames {
    enum class Kind { IMAGE, BIN, GIF, ANIMATION }
    data class Source(val index: Int, val stem: String, val kind: Kind)
    data class Group(val stem: String, val sources: List<Source>, val error: String?)
    data class Plan(val groups: List<Group>, val unmatched: Int)

    fun match(name: String, device: DeviceTarget): Pair<String, Kind>? {
        val extension = name.substringAfterLast('.', "").lowercase()
        val base = name.substringBeforeLast('.').trim()
        val kind = when (extension) {
            "gif" -> Kind.GIF
            "bin" -> if (base.endsWith("_anim", ignoreCase = true)) Kind.ANIMATION else Kind.BIN
            "png", "jpg", "jpeg", "webp", "bmp", "heic", "heif", "" -> Kind.IMAGE
            else -> return null
        }
        val key = if (kind == Kind.ANIMATION) base.dropLast(5) else base
        val slot = IconSpec.matchName(key, device) ?: return null
        if (slot.group == IconSpec.Group.NATIVE && kind != Kind.BIN) return null
        return slot.stem to kind
    }

    fun plan(names: List<String>, device: DeviceTarget): Plan {
        val matched = names.mapIndexedNotNull { index, name -> match(name, device)?.let { Source(index, it.first, it.second) } }
        val groups = matched.groupBy { it.stem }.map { (stem, items) ->
            val covers = items.count { it.kind in listOf(Kind.IMAGE, Kind.BIN) }
            val animations = items.count { it.kind in listOf(Kind.GIF, Kind.ANIMATION) }
            Group(stem, items, when {
                covers > 1 -> "同一槽位不能有多个静态封面（PNG/图片与 BIN 也不能同时提供）"
                animations > 1 -> "同一槽位不能有多个动画（GIF 与 _anim.bin 也不能同时提供）"
                else -> null
            })
        }
        return Plan(groups, names.size - matched.size)
    }
}
