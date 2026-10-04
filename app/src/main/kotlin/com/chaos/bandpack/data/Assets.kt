package com.chaos.bandpack.data

import android.content.Context
import com.chaos.bandpack.data.icon.IconSpec
import com.chaos.bandpack.data.pack.PackAssets
import com.chaos.bandpack.data.pack.ShellWriter

/**
 * 从 APK 的 assets 里读打包素材。文件由构建期的 syncPackAssets 任务从仓库同步进来,
 * 名字固定(见 app/build.gradle.kts)。
 */
object Assets {

    private const val DIR = "pack"

    fun pack(context: Context): PackAssets = context.assets.let { a ->
        PackAssets(
            ko = a.open("$DIR/chaos_sup.ko").use { it.readBytes() },
            iconBin = a.open("$DIR/chaos_icon.bin").use { it.readBytes() },
            fontLua = a.open("$DIR/font_pack.lua").use { String(it.readBytes(), Charsets.UTF_8) },
            iconLua = a.open("$DIR/icon_pack.lua").use { String(it.readBytes(), Charsets.UTF_8) },
        )
    }

    /**
     * 系统原图标预览: assets/stock_icons/<stem>.png。
     *
     * 这些图是从固件资源包里解出来的, **没有可再分发的授权**, 所以构建期是可选的
     * (见 app/build.gradle.kts 的 stockIcons 开关): 公开仓库的构建里就是空的,
     * 界面自动退成"未内置"。
     */
    fun stockIconNames(context: Context): Set<String> =
        context.assets.list("stock_icons")?.toSet() ?: emptySet()

    fun stockIcon(context: Context, stem: String): ByteArray? =
        IconSpec.previewStems(stem).firstNotNullOfOrNull { name ->
            runCatching { context.assets.open("stock_icons/$name.png").use { it.readBytes() } }.getOrNull()
        }

    /**
     * 设置页"关于"要显示的真实数字。主包包号是编译期常量(见 [ShellWriter.MAIN_PKG]),
     * 哈希由构建期的校验任务跟本地主包对齐。
     *
     * [stockIcons] 只数**对得上槽位**的那些: 素材目录里可能留着设备上已不存在的应用的图
     * (例如 `dealt.png`), 直接拿文件数除以槽位数会算出 36/35 这种不可能的比值。
     */
    class About(
        val mainPkg: String,
        val koBytes: Int,
        val iconBytes: Int,
        val stockIcons: Int,
    )

    fun about(context: Context): About? = runCatching {
        val a = context.assets
        val names = stockIconNames(context)
        About(
            mainPkg = ShellWriter.MAIN_PKG,
            koBytes = a.open("$DIR/chaos_sup.ko").use { it.readBytes().size },
            iconBytes = a.open("$DIR/chaos_icon.bin").use { it.readBytes().size },
            stockIcons = IconSpec.SLOTS.count { slot -> IconSpec.previewStems(slot.stem).any { "$it.png" in names } },
        )
    }.getOrNull()
}
