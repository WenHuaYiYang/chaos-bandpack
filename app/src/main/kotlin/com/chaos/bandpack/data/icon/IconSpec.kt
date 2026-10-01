package com.chaos.bandpack.data.icon

/**
 * 手环桌面图标的规格与槽位表。
 *
 * 规格是量出来的，不是拍的：画布 112x112，内容上限 100x100，四边至少 6px 透明留白
 * —— 与固件自带图标（`more.bin` / `calendar_background_icon.bin`）同规格。
 * 留白是桌面用来做磁贴间距的，少了会看着比系统图标大一圈。
 *
 * 槽位表来自内核模块 `icon_apply.rs` 的 `ICON_STEMS`：手环只认那张表里的名字，
 * 名字对不上直接回 NAME 错误（错误码 5），照片再好也进不去。所以表里的名字一律不许自己编，
 * 只允许"照抄再减去设备上不存在的应用"（见 [ABSENT_ON_DEVICE]，漂移守卫单测钉住这条）。
 * 名字要传**不带扩展名**的 stem（固件允许带 `.bin`，但没必要留两种写法）。
 */
object IconSpec {

    const val CANVAS = 112
    const val CONTENT = 100
    const val MARGIN = (CANVAS - CONTENT) / 2      // 6

    /** 文件头 12 字节：宽高与色深，固件按它判"这是不是我们的图标" */
    val HEADER = byteArrayOf(
        0x19, 0x10, 0x00, 0x00,
        0x70, 0x00, 0x70, 0x00,
        0xC0.toByte(), 0x01, 0x00, 0x00,
    )

    /** 12 字节头 + 112*112 个 BGRA 像素 */
    const val OUT_BYTES = 12 + CANVAS * CANVAS * 4    // 50188

    /** 一个槽位：传给手环的名字 + 界面上显示的中文名 */
    data class Slot(val stem: String, val label: String)

    /**
     * 手环上**根本没有**这三个应用（逐个对着设备核过）。内核那张 `ICON_STEMS` 仍然收
     * 这些名字（收着不报错，改了也没人读），但界面上不摆出来 —— 摆出来只会让人给一个
     * 不存在的应用挑图标。漂移守卫单测拿这个集合做减法，所以两边仍然是一条来源。
     */
    val ABSENT_ON_DEVICE = setOf("dealt", "innovation_research", "perpetual_calendar")

    /**
     * 可换图标的桌面槽位（固件 `ICON_STEMS` 去掉 [ABSENT_ON_DEVICE] 之后按名字排序）。
     *
     * 中文名**不是**照英文 stem 猜的 —— 猜错过一整批（把 `pressure` 写成"血压"、
     * `vitality` 写成"活力"、`share` 写成"分享"）。真值来源是
     * 槽位表来自对固件 launcher 的逆向：
     * 那份表是**在真机 launcher 图标列表里逐个读出来的** 32 个显示名，
     * 再加上对 `share` / `vitality` / `activities` 等几项的逐项核对。
     *
     * 注意名字与 stem 的对应**不能按顺序对**（那份表是列表模式的显示顺序，不是 app_id），
     * 只能按含义对：`activities` 是活力指标不是计步，`camera` 是遥控拍照，
     * `aivs` 是小爱同学，`mute` 是手机静音，`calendar` 是日程。
     *
     * 只剩三项在那份 32 项表里没有（`oxygen` / `womenhealth` / 以及 `share` 的旧名），
     * 名字沿用系统设置里的叫法。
     */
    val SLOTS: List<Slot> = listOf(
        Slot("activities", "活力指标"),
        Slot("aivs", "小爱同学"),
        Slot("alarm", "闹钟"),
        Slot("alipay", "支付宝"),
        Slot("breath", "呼吸放松"),
        Slot("calendar", "日程"),
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

    fun stemOf(s: String): Slot? = SLOTS.firstOrNull { it.stem == s }

    /** 手环侧的落地路径（只用于显示，手机不拼路径，路径由固件拼） */
    fun devicePath(stem: String): String = "/data/chaos/icons/$stem.bin"
}
