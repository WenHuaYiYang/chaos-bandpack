package com.chaos.bandpack.data.icon

import com.chaos.bandpack.data.pack.Cipk

/** 图标槽位、尺寸及导出资源。 */
object IconSpec {
    const val CANVAS = 112
    const val CONTENT = 100
    const val MARGIN = (CANVAS - CONTENT) / 2
    const val OUT_BYTES = 12 + CANVAS * CANVAS * 4
    val HEADER = LvglIconCodec.header(CANVAS, CANVAS, 16, 0, CANVAS * 4)
    enum class Group(val label: String) { DESKTOP("桌面"), CONTROL("控制中心"), SETTINGS("设置") }
    data class Slot(val stem: String, val label: String, val group: Group = Group.DESKTOP) {
        val canvas: Int get() = if (group == Group.DESKTOP) CANVAS else 64
        val content: Int get() = if (group == Group.DESKTOP) CONTENT else 64
    }
    val ABSENT_ON_DEVICE = setOf("dealt", "innovation_research")
    val DESKTOP: List<Slot> = listOf(
        Slot("activities", "活力指标"),
        Slot("aivs", "小爱同学"),
        Slot("alarm", "闹钟"),
        Slot("alipay", "支付宝"),
        Slot("breath", "呼吸放松"),
        Slot("perpetual_calendar", "日历"),
        Slot("camera", "遥控拍照"),
        Slot("card", "卡包"),
        Slot("chronograph", "秒表"),
        Slot("compass", "指南针"),
        Slot("findphone", "找手机"),
        Slot("flashlight", "手电筒"),
        Slot("heartrate", "心率"),
        Slot("interconnect", "多端联动"),
        Slot("mijia", "米家"),
        Slot("music", "音乐"),
        Slot("mute", "手机静音"),
        Slot("oxygen", "血氧"),
        Slot("pressure", "压力"),
        Slot("recorder", "录音机"),
        Slot("settings", "设置"),
        Slot("share", "融合设备中心"),
        Slot("sleep", "睡眠"),
        Slot("sports", "运动"),
        Slot("sports_course", "跑步课程"),
        Slot("sports_record", "运动记录"),
        Slot("sports_status", "训练状态"),
        Slot("timer", "倒计时"),
        Slot("todo", "待办"),
        Slot("tomato_clock", "番茄钟"),
        Slot("vitality", "元气值"),
        Slot("weather", "天气"),
        Slot("womenhealth", "女性健康"),
        Slot("worldclock", "世界时钟"),
        Slot("wxpay", "微信支付"),
    )

    val CONTROL = listOf(
        Slot("ctrl_flashlight", "手电筒", Group.CONTROL),
        Slot("ctrl_setting", "设置", Group.CONTROL),
        Slot("ctrl_battery", "省电", Group.CONTROL),
        Slot("ctrl_bright", "亮度", Group.CONTROL),
        Slot("ctrl_alarm", "闹钟", Group.CONTROL),
        Slot("ctrl_findphone", "找手机", Group.CONTROL),
        Slot("ctrl_disturb", "勿扰", Group.CONTROL),
        Slot("ctrl_raise", "抬腕亮屏", Group.CONTROL),
        Slot("ctrl_game", "游戏模式", Group.CONTROL),
    )
    val SETTINGS = listOf(
        Slot("set_notify", "通知", Group.SETTINGS),
        Slot("set_desktop", "桌面", Group.SETTINGS),
        Slot("set_display", "显示", Group.SETTINGS),
        Slot("set_disturb", "勿扰", Group.SETTINGS),
        Slot("set_safe", "安全", Group.SETTINGS),
        Slot("set_battery", "电池", Group.SETTINGS),
        Slot("set_motion", "运动", Group.SETTINGS),
        Slot("set_preference", "偏好", Group.SETTINGS),
        Slot("set_mydevice", "我的设备", Group.SETTINGS),
        Slot("set_wrist", "佩戴方式", Group.SETTINGS),
    )
    val SLOTS = DESKTOP + CONTROL + SETTINGS
    fun stemOf(s: String): Slot? = SLOTS.firstOrNull { it.stem == if (s == "calendar") "perpetual_calendar" else s }
    fun slots(group: Group): List<Slot> = SLOTS.filter { it.group == group }

    /** 日历原图兼容旧素材名，仍只占一个槽位。 */
    fun previewStems(stem: String): List<String> =
        if (stem == "perpetual_calendar") listOf(stem, "calendar") else listOf(stem)

    /** 精确匹配英文名或分类中文名；未注明分类的重名不匹配。 */
    fun matchName(base: String): Slot? {
        val name = base.trim()
        stemOf(name.lowercase())?.let { return it }
        if (name == "日程" || name == "日历") return stemOf("perpetual_calendar")
        return SLOTS.filter { slot ->
            slot.label == name || listOf("_", "-", "·", " ").any {
                name == slot.group.label + it + slot.label
            }
        }.singleOrNull()
    }

    fun duplicateStems(stems: List<String?>): Set<String> =
        stems.filterNotNull().groupingBy { it }.eachCount().filterValues { it > 1 }.keys

    /** 一个日历槽兼容两个文件名，勿扰自动补齐动画画布。 */
    fun export(picked: Map<String, ByteArray>): List<Cipk.Icon> {
        val normalized = linkedMapOf<String, ByteArray>()
        picked.forEach { (stem, bin) ->
            val slot = requireNotNull(stemOf(stem)) { "未知图标槽位: $stem" }
            require(!normalized.containsKey(slot.stem)) { "图标槽位重复: ${slot.label}" }
            val decoded = LvglIconCodec.decode(bin)
            require(decoded.width == slot.canvas && decoded.height == slot.canvas) { "${slot.label}尺寸不匹配" }
            normalized[slot.stem] = bin
        }
        val out = normalized.map { Cipk.Icon(it.key, it.value) }.toMutableList()
        normalized["perpetual_calendar"]?.let { out += Cipk.Icon("calendar", it) }
        normalized["ctrl_disturb"]?.let { bin ->
            val image = LvglIconCodec.decode(bin)
            val canvas = IntArray(160 * 124)
            for (y in 0 until 64) System.arraycopy(image.pixels, y * 64, canvas, (y + 30) * 160 + 48, 64)
            out += Cipk.Icon("ctrl_dnd", LvglIconCodec.indexedRle(canvas, 160, 124))
        }
        return out.sortedBy { it.stem }
    }
    fun devicePath(stem: String): String = "/data/chaos/icons/$stem.bin"
}
