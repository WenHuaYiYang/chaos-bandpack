package com.chaos.bandpack.data.icon

import com.chaos.bandpack.data.pack.Cipk

/** CIA1 bit order is an ABI; it is independent of the order of UI slots. */
object AnimatedIcons {
    val STEMS = listOf(
        "activities", "aivs", "alarm", "alipay", "breath", "calendar", "camera", "card",
        "chronograph", "compass", "dealt", "findphone", "flashlight", "heartrate",
        "innovation_research", "interconnect", "mijia", "music", "mute", "oxygen",
        "perpetual_calendar", "pressure", "recorder", "settings", "share", "sleep", "sports",
        "sports_course", "sports_record", "sports_status", "timer", "todo", "tomato_clock",
        "vitality", "weather", "womenhealth", "worldclock", "wxpay",
    )
    fun key(stem: String) = "${stem}_anim"
    fun isAnimationKey(key: String) = key.endsWith("_anim")
    fun base(key: String) = key.removeSuffix("_anim")
    fun withoutSlot(images: Map<String, ByteArray>, stem: String): Map<String, ByteArray> =
        images - stem - key(stem) - if (stem == "ctrl_disturb") setOf("ctrl_dnd") else emptySet()

    fun index(stems: Set<String>): ByteArray {
        require(stems.all { it in STEMS }) { "只有 38 个桌面 stem 支持 DGF1 动画" }
        val out = ByteArray(20)
        "CIA1".toByteArray(Charsets.US_ASCII).copyInto(out)
        Dgf1.w16(out, 4, 96); Dgf1.w16(out, 6, 96); Dgf1.w16(out, 8, 38)
        val mask = stems.fold(0L) { n, s -> n or (1L shl STEMS.indexOf(s)) }
        Dgf1.w32(out, 12, mask); Dgf1.w32(out, 16, mask ushr 32)
        return out
    }

    fun readIndex(bytes: ByteArray): Set<String> {
        require(bytes.size == 20 && String(bytes, 0, 4, Charsets.US_ASCII) == "CIA1" &&
            Dgf1.u16(bytes, 4) == 96 && Dgf1.u16(bytes, 6) == 96 && Dgf1.u16(bytes, 8) == 38 && Dgf1.u16(bytes, 10) == 0) { "CIA1 索引头不合法" }
        val mask = Dgf1.u32(bytes, 12) or (Dgf1.u32(bytes, 16) shl 32)
        require(mask ushr 38 == 0L) { "CIA1 第 38–63 位必须为 0" }
        return STEMS.filterIndexed { i, _ -> mask and (1L shl i) != 0L }.toSet()
    }

    /** Project payloads retain animations while exporting a static cover to 9 Pro. */
    fun validateProject(images: Map<String, ByteArray>) {
        require("animations" !in images) { "工程中的动画索引由导出时自动生成" }
        for ((stem, bytes) in images) {
            if (isAnimationKey(stem)) {
                val source = base(stem)
                require(source in STEMS) { "未知桌面动画槽位：$source" }
                Dgf1.parse(bytes)
                val cover = requireNotNull(images[source]) { "$source 的动画缺少静态封面" }
                val decoded = LvglIconCodec.decode(cover)
                require(decoded.width == 96 && decoded.height == 96) { "$source 动画的封面必须为 96 × 96" }
            } else {
                require(bytes.size <= Cipk.ICON_LEN_MAX) { "$stem 静态文件超过 512 KiB" }
                LvglIconCodec.decode(bytes)
            }
        }
    }

    fun validateFiles(files: List<Cipk.Icon>, requireIndex: Boolean = false) {
        require(files.map { it.stem }.toSet().size == files.size) { "图标文件名重复" }
        val map = files.associate { it.stem to it.data }
        val images = map - "animations"
        val known = STEMS.toSet() + NativeIconStems.ALL + IconSpec.SLOTS.map { it.stem }
        require(images.keys.all { if (isAnimationKey(it)) base(it) in STEMS else it in known }) { "投递包包含未知 stem" }
        require(images.keys.any { !isAnimationKey(it) }) { "投递包没有静态封面或图标" }
        require(images.all { (stem, bytes) -> isAnimationKey(stem) || bytes.firstOrNull() == 0x19.toByte() }) {
            "p67 静态文件必须使用原生图像头，不能直接放入 9 Pro DAT"
        }
        validateProject(images)
        val animated = images.keys.filter(::isAnimationKey).map(::base).toSet()
        val index = map["animations"]
        require(!requireIndex || index != null) { "投递包缺少 CIA1 索引" }
        if (index != null) require(readIndex(index) == animated) { "CIA1 索引与动画文件不一致" }
    }

    fun prepare(statics: List<Cipk.Icon>, animations: Map<String, ByteArray>): List<Cipk.Icon> {
        val result = statics + animations.toSortedMap().map { (stem, bytes) -> Cipk.Icon(key(stem), bytes) } +
            Cipk.Icon("animations", index(animations.keys))
        validateFiles(result, requireIndex = true)
        return result
    }

    fun payload(files: List<Cipk.Icon>): List<Cipk.Icon> {
        if (files.any { it.stem == "animations" }) { validateFiles(files, requireIndex = true); return files }
        require(files.map { it.stem }.toSet().size == files.size) { "图标文件名重复" }
        return prepare(files.filterNot { isAnimationKey(it.stem) },
            files.filter { isAnimationKey(it.stem) }.associate { base(it.stem) to it.data })
    }
}
