package com.chaos.bandpack.data

enum class DeviceTarget(val id: String, val label: String, val firmware: String) {
    TEN_PRO("p67", "10 Pro", "3.101.043"),
    NINE_PRO("n67", "9 Pro", "3.1.187");

    companion object {
        fun fromId(id: String): DeviceTarget = entries.singleOrNull { it.id == id }
            ?: throw IllegalArgumentException("工程中的设备型号不支持：$id")
    }
}
