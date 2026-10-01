package com.chaos.bandpack.data.pack

/**
 * 打包要用的固定素材。全部来自**设备侧那一份源码**(主仓库), 由 Gradle 在构建时同步进
 * assets(见 app/build.gradle.kts 的 syncPackAssets 任务) —— 本仓库不存第二份拷贝,
 * 也不放任何二进制: 内核模块与那枚应用图标都是设备侧构建出来的产物。
 *
 * 目录由 `chaos.repo` 指定(默认 `../Chaos-Module`), 缺失时构建直接失败并说明怎么准备 ——
 * 不给"装好了却打不出包"的 App。
 */
class PackAssets(
    /** 内核模块 chaos_sup.ko(与主包同一份, 投递包靠它自己跑起来) */
    val ko: ByteArray,
    /** 应用图标 chaos_icon.bin(注册应用要用, 与主包同一份) */
    val iconBin: ByteArray,
    /** 字体投递 Lua 模板(带 __FONT_NAME__ / __PACK_LABEL__ / __PACK_TITLE__ 占位符) */
    val fontLua: String,
    /** 图标投递 Lua 模板(带 __PACK_NAME__ / __PACK_TITLE__ 占位符) */
    val iconLua: String,
)
