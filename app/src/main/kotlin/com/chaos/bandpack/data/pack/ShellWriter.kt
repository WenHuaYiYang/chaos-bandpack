package com.chaos.bandpack.data.pack

import java.security.MessageDigest

/**
 * 投递包的字段级规矩: 包名、显示名的口径, 包名哈希, 以及产物回读。
 *
 * 容器壳的**布局与合成**在 [ShellBuilder]; 这里只放"与容器布局无关"的那些门。
 *
 * 两个真机事故刻在这里, 不是注释里的提醒:
 *   1. 显示名只占 `0x68..0xA8` 这 64 字节。多清到 `0xA8..0x100` 会把主题表前 88 字节抹掉
 *      => 表盘在列表里还在、切过去全黑、脚本一行不执行。
 *   2. 槽的**内容语义**必须与主包一致(lua / ko / 图标 / 载荷)。曾经把槽 3、4 放成文本占位,
 *      结果同上: 界面能看到、切过去全黑。
 */
object ShellWriter {

    const val PKG_OFF = ShellBuilder.PKG_OFF
    const val PKG_LEN = ShellBuilder.PKG_LEN
    const val NAME_OFF = ShellBuilder.NAME_OFF
    const val NAME_MAX = ShellBuilder.NAME_MAX

    /**
     * 主包的包名(表盘容器的身份键): 投递包不能与它相同, 否则固件视为同一个包。
     *
     * 这是**主包侧的常量**, 与 `build_chaos_installer_043.py` 里的 `PKG_NAME` 必须一致。
     * 以前是从主包容器 `0x28` 现读(那时 App 拿主包当模板); 现在 App 自己合成壳、手上没有
     * 主包字节, 所以退成常量 —— 换来的是构建期校验: `syncPackAssets` 发现本地主包时
     * 会把它的号读出来跟这里比, 不一致直接让构建失败(见 app/build.gradle.kts)。
     */
    const val MAIN_PKG = "979820260926"

    private const val PKG_PREFIX = "4348"

    class PackError(message: String) : Exception(message)

    /** 由载荷内容推导 12 位数字包名: 同一内容幂等, 不同内容自动分开(多个包可并存) */
    fun pkgFor(blob: ByteArray): String {
        val h = MessageDigest.getInstance("SHA-256").digest(blob)
        var n = 0L
        for (i in 0 until 5) n = (n shl 8) or (h[i].toLong() and 0xFF)
        return PKG_PREFIX + "%08d".format(n % 100_000_000L)
    }

    /** 手填包名校验(用户可以覆盖自动推导的号) */
    fun checkPkg(pkg: String) {
        if (pkg.length != PKG_LEN || !pkg.all { it in '0'..'9' }) {
            throw PackError("表盘 ID 必须是 12 位数字, 现在是「$pkg」")
        }
    }

    /** 与主包撞号 = 同一个包, 侧载会被判重复安装 */
    fun checkPkgAgainst(pkg: String, mainPkg: String = MAIN_PKG) {
        if (pkg == mainPkg) throw PackError("表盘 ID 撞上了主包号 $mainPkg, 侧载会判重复安装")
    }

    fun checkName(name: String) {
        val n = name.toByteArray(Charsets.UTF_8).size
        if (n == 0) throw PackError("表盘名称不能为空")
        if (n >= NAME_MAX) throw PackError("表盘名称太长($n 字节, 上限 ${NAME_MAX - 1} 字节)")
    }

    /** 读回某条槽(1 起)的路径与内容 —— 打包后的自检与测试用 */
    fun readEntry(out: ByteArray, index1: Int): Pair<String, ByteArray> {
        val off = readU32(out, ShellBuilder.REC_OFF + index1 * 16 + 8)
        val head = readU32(out, off)
        val dlen = head and 0xFFFFFF
        val plen = head ushr 24
        val path = String(out, off + ShellBuilder.BLOB_HDR_LEN, plen, Charsets.US_ASCII)
        val data = out.copyOfRange(
            off + ShellBuilder.BLOB_HDR_LEN + plen,
            off + ShellBuilder.BLOB_HDR_LEN + plen + dlen,
        )
        return path to data
    }

    // ---- 小端读写 ----

    fun readU32(b: ByteArray, o: Int): Int =
        (b[o].toInt() and 0xFF) or ((b[o + 1].toInt() and 0xFF) shl 8) or
            ((b[o + 2].toInt() and 0xFF) shl 16) or ((b[o + 3].toInt() and 0xFF) shl 24)

    fun writeU32(b: ByteArray, o: Int, v: Int) {
        b[o] = (v and 0xFF).toByte()
        b[o + 1] = ((v ushr 8) and 0xFF).toByte()
        b[o + 2] = ((v ushr 16) and 0xFF).toByte()
        b[o + 3] = ((v ushr 24) and 0xFF).toByte()
    }

    fun u32(v: Int): ByteArray = byteArrayOf(
        (v and 0xFF).toByte(),
        ((v ushr 8) and 0xFF).toByte(),
        ((v ushr 16) and 0xFF).toByte(),
        ((v ushr 24) and 0xFF).toByte(),
    )
}
