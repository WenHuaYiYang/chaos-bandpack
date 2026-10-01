package com.chaos.bandpack.data.pack

import java.io.ByteArrayOutputStream

/**
 * 容器壳的**从零合成**（与 PC 侧 `tools/container_shell.py` 的 `build_shell()` 逐字节同构）。
 *
 * 为什么不再拿一份主包当模板: 模板会漂移(主包换壳/换号, App 还在用旧的), 而壳里真正
 * 需要继承的只有"主题表那几个指针与计数", 那些本来就是可以从文件条数算出来的派生量。
 * 自己算出来之后, 打包只需要三样输入: 内核模块、应用图标、投递 Lua。
 *
 * 布局(逐字段对过 PC 侧生成器与多个来源不同的容器):
 * ```
 * 0x00  u32 魔数 0x1234A55A     0x04 u32 设备码(10 Pro = 0x10000)
 * 0x10  u32 0x800               0x14 u32 0x10000    0x18 0    0x1C 主题数 = 1
 * 0x20  u32 记录表结束地址( = 预览块起点)              0x24 0
 * 0x28  12 字节包名 pkgName(身份键, 撞号 = 同一个包)
 * 0x68  64 字节显示名(UTF-8, NUL 补齐)
 * 0xA8  主题表: (0x80000000, 记录表结束, 1, 0x148)
 *       0xB8..0xFF 共 9 组 (u32,u32): 前 5 组的第二个字 = 首条文件记录地址,
 *       后 4 组的第二个字 = 尾标记地址; 0xD8 那组的第一个字 = **文件条数**
 *       0x100.. 主题名(默认"样式1")
 * 0x148 记录表: 首条 (0, 0, 尾标记地址, 0x10) + 每条文件 (0x05000000|槽号, 0, 偏移, 长度)
 *       + 尾标记 (0x05000000, 0, 0, 0)
 *       [预览块 12 字节头 + 数据]
 *       [文件区: 每条 = u32((长度 & 0xFFFFFF) | (路径长 << 24)) + 16 字节零 + 路径 + 内容]
 * ```
 * 派生量只有三个: 记录表结束 = `0x148 + 16*(2 + 条数)`; 预览块起点 = 记录表结束;
 * 文件区起点 = 记录表结束 + 预览块长度。
 */
object ShellBuilder {

    const val MAGIC = 0x1234A55A
    const val DEVICE_CODE = 0x10000
    const val PREVIEW_TAG = 0x410
    const val PREVIEW_HDR = 12

    const val REC_OFF = 0x148
    const val PKG_OFF = 0x28
    const val PKG_LEN = 12
    const val NAME_OFF = 0x68
    const val NAME_MAX = 64
    const val THEME_OFF = 0xA8
    const val THEME_END = 0x148
    const val FILE_CNT_OFF = 0xD8
    const val THEME_NAME_OFF = 0x100
    const val THEME_NAME_MAX = THEME_END - THEME_NAME_OFF
    const val THEME_PTR_SLOTS = 5
    const val THEME_TAIL_SLOTS = 4
    const val REC_UID_BASE = 0x05000000
    const val BLOB_HDR_LEN = 20
    const val DEFAULT_THEME_NAME = "样式1"

    /** 一条槽: 容器内路径 + 内容 */
    class Entry(val path: String, val data: ByteArray)

    /** 拆回容器。字段全按记录表自己的偏移取, 越界即抛。 */
    class Parsed(
        val files: List<Pair<String, ByteArray>>,
        val pkg: String,
        val displayName: String,
        val themeName: String,
        val preview: ByteArray,
        val fileRegion: Int,
    )

    fun recordEnd(fileCount: Int): Int = REC_OFF + 16 * (2 + fileCount)

    /** 一条文件在容器里的完整记录(含 20 字节小头) */
    private fun blobFor(path: String, data: ByteArray): ByteArray {
        // 先按字符查, 再编码: `toByteArray(US_ASCII)` 会把非 ASCII **静默换成 '?'**,
        // 那样中文路径会被悄悄改写成一个不存在的名字(PC 侧 encode('ascii') 是直接抛)。
        if (path.isEmpty() || path.any { it.code < 0x20 || it.code >= 0x7F }) {
            throw ShellWriter.PackError("槽路径必须是可打印 ASCII: $path")
        }
        val pb = path.toByteArray(Charsets.US_ASCII)
        if (data.size >= (1 shl 24)) throw ShellWriter.PackError("$path 超过单槽 24bit 长度上限(16MB)")
        if (pb.size >= 256) throw ShellWriter.PackError("槽路径太长: $path")
        val head = ShellWriter.u32((data.size and 0xFFFFFF) or (pb.size shl 24))
        val out = ByteArray(BLOB_HDR_LEN + pb.size + data.size)
        System.arraycopy(head, 0, out, 0, 4)
        System.arraycopy(pb, 0, out, BLOB_HDR_LEN, pb.size)
        System.arraycopy(data, 0, out, BLOB_HDR_LEN + pb.size, data.size)
        return out
    }

    /**
     * 合成一份完整容器。[preview] 是预览块原始字节(含 12 字节头), 由 [PreviewFactory] 按包生成。
     */
    fun build(
        files: List<Entry>,
        pkgName: String,
        displayName: String,
        preview: ByteArray,
        themeName: String = DEFAULT_THEME_NAME,
        deviceCode: Int = DEVICE_CODE,
    ): ByteArray {
        ShellWriter.checkPkg(pkgName)
        ShellWriter.checkName(displayName)
        val pkg = pkgName.toByteArray(Charsets.US_ASCII)
        val nb = displayName.toByteArray(Charsets.UTF_8)
        val tb = themeName.toByteArray(Charsets.UTF_8)
        if (tb.size > THEME_NAME_MAX) throw ShellWriter.PackError("主题名过长")
        checkPreview(preview)
        if (files.isEmpty() || files.size >= 256) {
            throw ShellWriter.PackError("文件条数必须在 1..255(槽号占一个字节), 现在 ${files.size}")
        }

        val n = files.size
        val recEnd = recordEnd(n)
        val firstRec = REC_OFF + 16
        val tailRec = recEnd - 16
        val fileRegion = recEnd + preview.size

        val shell = ByteArray(fileRegion)
        ShellWriter.writeU32(shell, 0x00, MAGIC)
        ShellWriter.writeU32(shell, 0x04, deviceCode)
        ShellWriter.writeU32(shell, 0x10, 0x800)
        ShellWriter.writeU32(shell, 0x14, 0x10000)
        ShellWriter.writeU32(shell, 0x1C, 1)
        ShellWriter.writeU32(shell, 0x20, recEnd)
        System.arraycopy(pkg, 0, shell, PKG_OFF, PKG_LEN)
        System.arraycopy(nb, 0, shell, NAME_OFF, nb.size)

        ShellWriter.writeU32(shell, THEME_OFF, 0x80000000.toInt())
        ShellWriter.writeU32(shell, THEME_OFF + 4, recEnd)
        ShellWriter.writeU32(shell, THEME_OFF + 8, 1)
        ShellWriter.writeU32(shell, THEME_OFF + 12, REC_OFF)
        for (i in 0 until THEME_PTR_SLOTS) {
            val at = THEME_OFF + 16 + 8 * i
            ShellWriter.writeU32(shell, at, if (at == FILE_CNT_OFF) n else 0)
            ShellWriter.writeU32(shell, at + 4, firstRec)
        }
        for (i in 0 until THEME_TAIL_SLOTS) {
            val at = THEME_OFF + 16 + 8 * (THEME_PTR_SLOTS + i)
            ShellWriter.writeU32(shell, at, 0)
            ShellWriter.writeU32(shell, at + 4, tailRec)
        }
        System.arraycopy(tb, 0, shell, THEME_NAME_OFF, tb.size)

        ShellWriter.writeU32(shell, REC_OFF, 0)
        ShellWriter.writeU32(shell, REC_OFF + 4, 0)
        ShellWriter.writeU32(shell, REC_OFF + 8, tailRec)
        ShellWriter.writeU32(shell, REC_OFF + 12, 0x10)

        val blobs = ArrayList<ByteArray>(n)
        var pos = fileRegion
        files.forEachIndexed { i, e ->
            val blob = blobFor(e.path, e.data)
            val at = REC_OFF + 16 * (1 + i)
            ShellWriter.writeU32(shell, at, REC_UID_BASE + i)
            ShellWriter.writeU32(shell, at + 4, 0)
            ShellWriter.writeU32(shell, at + 8, pos)
            ShellWriter.writeU32(shell, at + 12, blob.size)
            blobs.add(blob)
            pos += blob.size
        }
        ShellWriter.writeU32(shell, tailRec, REC_UID_BASE)
        ShellWriter.writeU32(shell, tailRec + 4, 0)
        ShellWriter.writeU32(shell, tailRec + 8, 0)
        ShellWriter.writeU32(shell, tailRec + 12, 0)
        System.arraycopy(preview, 0, shell, recEnd, preview.size)

        val out = ByteArrayOutputStream(pos)
        out.write(shell)
        for (b in blobs) out.write(b)
        val bytes = out.toByteArray()
        if (bytes.size != pos) throw ShellWriter.PackError("布局不自洽: 预期 $pos 实际 ${bytes.size}")
        return bytes
    }

    /** 预览块自检: 12 字节头 + 长度字段与实际长度必须自洽(块内编码是各端自己的事) */
    fun checkPreview(preview: ByteArray) {
        if (preview.size < PREVIEW_HDR) throw ShellWriter.PackError("预览块太短")
        val tag = ShellWriter.readU32(preview, 0)
        if (tag != PREVIEW_TAG) throw ShellWriter.PackError("预览块标签不对: %#x".format(tag))
        val plen = ShellWriter.readU32(preview, 8)
        if (plen < 0 || preview.size != PREVIEW_HDR + plen) {
            throw ShellWriter.PackError("预览块长度与头里的字段不符")
        }
    }

    /** 取产物里的预览块原始字节 */
    fun previewOf(raw: ByteArray): ByteArray {
        val recEnd = ShellWriter.readU32(raw, 0x20)
        ShellWriter.readU32(raw, recEnd).let {
            if (it != PREVIEW_TAG) throw ShellWriter.PackError("预览块标签不对: %#x".format(it))
        }
        val plen = ShellWriter.readU32(raw, recEnd + 8)
        if (recEnd + PREVIEW_HDR + plen > raw.size) throw ShellWriter.PackError("预览块越界")
        return raw.copyOfRange(recEnd, recEnd + PREVIEW_HDR + plen)
    }

    /**
     * 打包的最后一道门: **把自己刚写出来的字节拆回来**逐字段核对。
     *
     * 以前这道门是"与模板逐字节比主题表", 现在没有模板了 —— 改成核对派生关系是否自洽
     * (条数 -> 记录表结束 -> 预览块起点 -> 文件区起点), 以及每条记录是否真能按自己的
     * 偏移取到完整的路径与内容。
     */
    fun parse(raw: ByteArray): Parsed {
        if (raw.size < REC_OFF + 16 * 3) throw ShellWriter.PackError("容器太短")
        if (ShellWriter.readU32(raw, 0) != MAGIC) throw ShellWriter.PackError("容器魔数不符")
        if (ShellWriter.readU32(raw, 4) != DEVICE_CODE) {
            throw ShellWriter.PackError("设备码不是 10 Pro(0x10000)")
        }
        val n = ShellWriter.readU32(raw, FILE_CNT_OFF)
        if (n < 1 || n > 255) throw ShellWriter.PackError("文件条数非法: $n")
        val recEnd = ShellWriter.readU32(raw, 0x20)
        if (recEnd != recordEnd(n)) throw ShellWriter.PackError("记录表结束地址与条数不符: $recEnd")
        if (ShellWriter.readU32(raw, THEME_OFF + 4) != recEnd) {
            throw ShellWriter.PackError("主题表的记录表指针与 0x20 不一致")
        }
        if (ShellWriter.readU32(raw, THEME_OFF) != 0x80000000.toInt()) {
            throw ShellWriter.PackError("主题表首字不对")
        }
        if (ShellWriter.readU32(raw, THEME_OFF + 8) != 1) throw ShellWriter.PackError("主题数不是 1")
        if (ShellWriter.readU32(raw, THEME_OFF + 12) != REC_OFF) {
            throw ShellWriter.PackError("主题表里的记录表地址不对")
        }
        val firstRec = REC_OFF + 16
        val tailRec = recEnd - 16
        for (i in 0 until THEME_PTR_SLOTS) {
            val at = THEME_OFF + 16 + 8 * i
            val cnt = ShellWriter.readU32(raw, at)
            if (cnt != (if (at == FILE_CNT_OFF) n else 0)) throw ShellWriter.PackError("主题表计数槽 $i 不对")
            if (ShellWriter.readU32(raw, at + 4) != firstRec) throw ShellWriter.PackError("主题表首记录指针 $i 不对")
        }
        for (i in 0 until THEME_TAIL_SLOTS) {
            val at = THEME_OFF + 16 + 8 * (THEME_PTR_SLOTS + i)
            if (ShellWriter.readU32(raw, at) != 0) throw ShellWriter.PackError("主题表尾槽 $i 计数不是 0")
            if (ShellWriter.readU32(raw, at + 4) != tailRec) throw ShellWriter.PackError("主题表尾记录指针 $i 不对")
        }
        if (ShellWriter.readU32(raw, REC_OFF) != 0 || ShellWriter.readU32(raw, REC_OFF + 12) != 0x10 ||
            ShellWriter.readU32(raw, REC_OFF + 8) != tailRec
        ) {
            throw ShellWriter.PackError("记录表首条形状不对")
        }
        if (ShellWriter.readU32(raw, tailRec) != REC_UID_BASE ||
            ShellWriter.readU32(raw, tailRec + 4) != 0 ||
            ShellWriter.readU32(raw, tailRec + 8) != 0 ||
            ShellWriter.readU32(raw, tailRec + 12) != 0
        ) {
            throw ShellWriter.PackError("尾标记不对")
        }

        val preview = previewOf(raw)
        val fileRegion = recEnd + preview.size
        val files = ArrayList<Pair<String, ByteArray>>(n)
        var expectOff = fileRegion
        for (i in 0 until n) {
            val at = REC_OFF + 16 * (1 + i)
            if (ShellWriter.readU32(raw, at) != REC_UID_BASE + i) {
                throw ShellWriter.PackError("第 ${i + 1} 条记录的槽号不对")
            }
            val off = ShellWriter.readU32(raw, at + 8)
            val len = ShellWriter.readU32(raw, at + 12)
            if (off != expectOff) throw ShellWriter.PackError("第 ${i + 1} 条记录起点不连续: $off")
            if (len < BLOB_HDR_LEN || off + len > raw.size) throw ShellWriter.PackError("第 ${i + 1} 条记录越界")
            val head = ShellWriter.readU32(raw, off)
            val dlen = head and 0xFFFFFF
            val plen = head ushr 24
            if (BLOB_HDR_LEN + plen + dlen != len) throw ShellWriter.PackError("第 ${i + 1} 条小头长度对不上")
            for (k in 4 until BLOB_HDR_LEN) {
                if (raw[off + k] != 0.toByte()) throw ShellWriter.PackError("第 ${i + 1} 条小头保留字节非 0")
            }
            val path = String(raw, off + BLOB_HDR_LEN, plen, Charsets.US_ASCII)
            val data = raw.copyOfRange(off + BLOB_HDR_LEN + plen, off + len)
            files.add(path to data)
            expectOff += len
        }
        if (expectOff != raw.size) throw ShellWriter.PackError("文件区结尾多出 ${raw.size - expectOff} 字节")

        val zero = (0 until NAME_MAX).firstOrNull { raw[NAME_OFF + it] == 0.toByte() } ?: NAME_MAX
        val themeZero = (0 until THEME_NAME_MAX).firstOrNull { raw[THEME_NAME_OFF + it] == 0.toByte() }
            ?: THEME_NAME_MAX
        return Parsed(
            files = files,
            pkg = String(raw, PKG_OFF, PKG_LEN, Charsets.US_ASCII),
            displayName = String(raw, NAME_OFF, zero, Charsets.UTF_8),
            themeName = String(raw, THEME_NAME_OFF, themeZero, Charsets.UTF_8),
            preview = preview,
            fileRegion = fileRegion,
        )
    }
}
