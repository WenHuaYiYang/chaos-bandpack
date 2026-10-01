package com.chaos.bandpack.data.pack

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 容器壳的**合成器与解析器**。
 *
 * 判据是拿 PC 侧生成器(`tools/container_shell.py`)造的样本当金标准: 先拆开(证明两侧对同一套
 * 布局的理解一致), 再用拆出来的输入重新合成, 必须**逐字节相同**。样本是我们自己造的占位数据,
 * 不含任何第三方字节, 所以这一组跟着仓库走、任何机器上都能跑。
 */
class ShellBuilderTest {

    private fun res(name: String): ByteArray =
        javaClass.getResourceAsStream("/shell/$name")!!.use { it.readBytes() }

    private data class Case(val file: String, val slots: Int, val pkg: String, val display: String)

    private val cases = listOf(
        Case("golden-one.bin", 1, "434811111111", "字:一号"),
        Case("golden-four.bin", 4, "434822222222", "图标:四号"),
        Case("golden-ten.bin", 10, "434833333333", "字:十号"),
    )

    @Test
    fun `PC 侧金标准容器能拆回来并逐字节重建`() {
        for (c in cases) {
            val golden = res(c.file)
            val p = ShellBuilder.parse(golden)

            assertEquals("${c.file} 槽数", c.slots, p.files.size)
            assertEquals("${c.file} 包名", c.pkg, p.pkg)
            assertEquals("${c.file} 显示名", c.display, p.displayName)
            assertEquals("${c.file} 主题名", ShellBuilder.DEFAULT_THEME_NAME, p.themeName)

            // 派生关系: 记录表结束 = 0x148 + 16*(2+条数); 文件区起点 = 记录表结束 + 预览块长
            val recEnd = ShellWriter.readU32(golden, 0x20)
            assertEquals("${c.file} 记录表结束地址", ShellBuilder.recordEnd(c.slots), recEnd)
            assertEquals("${c.file} 文件区起点", recEnd + p.preview.size, p.fileRegion)
            assertArrayEquals(
                "${c.file} 重建不是逐字节相同",
                golden,
                ShellBuilder.build(
                    p.files.map { ShellBuilder.Entry(it.first, it.second) },
                    p.pkg, p.displayName, p.preview, p.themeName,
                ),
            )
        }
    }

    @Test
    fun `产物里每条槽的路径与内容都能按记录表取回`() {
        val p = ShellBuilder.parse(res("golden-four.bin"))
        assertEquals(
            listOf(
                "_lua/iconpack/main.lua", "_lua/iconpack/chaos_sup.ko",
                "_lua/iconpack/chaos_icon.bin", "_lua/iconpack/pack.bin",
            ),
            p.files.map { it.first },
        )
        // 逐条与 readEntry(按记录表偏移取)对齐 —— 两条独立路径必须给同一答案
        p.files.forEachIndexed { i, (path, data) ->
            val (path2, data2) = ShellWriter.readEntry(res("golden-four.bin"), i + 1)
            assertEquals(path, path2)
            assertArrayEquals(data, data2)
        }
        // 第一条槽内容就是我们生成器写进去的占位 Lua
        assertTrue(String(p.files[0].second, Charsets.UTF_8).contains("local PACK_NAME = \"四号\""))
    }

    @Test
    fun `拆出来的容器改一个字节就会被发现`() {
        val golden = res("golden-four.bin")
        // 槽号字段
        val bad1 = golden.copyOf().also { it[ShellBuilder.REC_OFF + 16] = 0x7F }
        assertTrue(runCatching { ShellBuilder.parse(bad1) }.exceptionOrNull() is ShellWriter.PackError)
        // 文件条数字段
        val bad2 = golden.copyOf().also { it[ShellBuilder.FILE_CNT_OFF] = 5 }
        assertTrue(runCatching { ShellBuilder.parse(bad2) }.exceptionOrNull() is ShellWriter.PackError)
        // 小头里的保留字节
        val off = ShellWriter.readU32(golden, ShellBuilder.REC_OFF + 16 + 8)
        val bad3 = golden.copyOf().also { it[off + 6] = 1 }
        assertTrue(runCatching { ShellBuilder.parse(bad3) }.exceptionOrNull() is ShellWriter.PackError)
        // 尾部多一字节
        assertTrue(
            runCatching { ShellBuilder.parse(golden + ByteArray(1)) }.exceptionOrNull()
                is ShellWriter.PackError,
        )
    }

    @Test
    fun `预览块自检与输入门`() {
        val good = ShellBuilder.previewOf(res("golden-one.bin"))
        ShellBuilder.checkPreview(good)

        // 标签不对
        val badTag = good.copyOf().also { it[0] = 0x11 }
        assertTrue(
            runCatching { ShellBuilder.checkPreview(badTag) }.exceptionOrNull()
                is ShellWriter.PackError,
        )
        // 长度字段与实际长度不符
        val badLen = good.copyOf().also { it[8] = (it[8] + 1).toByte() }
        assertTrue(
            runCatching { ShellBuilder.checkPreview(badLen) }.exceptionOrNull()
                is ShellWriter.PackError,
        )
        // 太短
        assertTrue(
            runCatching { ShellBuilder.checkPreview(ByteArray(4)) }.exceptionOrNull()
                is ShellWriter.PackError,
        )

        val files = listOf(ShellBuilder.Entry("a.bin", ByteArray(3)))
        // 空槽列表
        assertTrue(
            runCatching { ShellBuilder.build(emptyList(), "434800000001", "x", good) }
                .exceptionOrNull() is ShellWriter.PackError,
        )
        // 路径不是可打印 ASCII(设备侧只认 ASCII 路径)
        assertTrue(
            runCatching { ShellBuilder.build(listOf(ShellBuilder.Entry("中文.bin", ByteArray(3))),
                "434800000001", "x", good) }.exceptionOrNull() is ShellWriter.PackError,
        )
        // 槽号占一个字节: 255 条是上限内, 256 条必须被拒
        val many = (0 until 256).map { ShellBuilder.Entry("f$it.bin", ByteArray(1)) }
        assertTrue(runCatching { ShellBuilder.build(many, "434800000001", "x", good) }
            .exceptionOrNull() is ShellWriter.PackError)
        val max = (0 until 255).map { ShellBuilder.Entry("f$it.bin", ByteArray(1)) }
        assertEquals(255, ShellBuilder.parse(ShellBuilder.build(max, "434800000001", "x", good)).files.size)
        assertEquals(1, files.size)
    }

    @Test
    fun `显示名与包名的口径`() {
        val good = ShellBuilder.previewOf(res("golden-one.bin"))
        val files = listOf(ShellBuilder.Entry("a.bin", ByteArray(3)))

        // 12 位数字之外的包名
        assertTrue(
            runCatching { ShellBuilder.build(files, "43480000001", "x", good) }
                .exceptionOrNull() is ShellWriter.PackError,
        )
        assertTrue(
            runCatching { ShellBuilder.build(files, "43480000000a", "x", good) }
                .exceptionOrNull() is ShellWriter.PackError,
        )
        // 显示名上限 63 字节(第 64 字节留给 NUL): 21 个汉字 = 63 字节可以, 22 个不行
        ShellBuilder.build(files, "434800000001", "名".repeat(21), good)
        assertTrue(
            runCatching { ShellBuilder.build(files, "434800000001", "名".repeat(22), good) }
                .exceptionOrNull() is ShellWriter.PackError,
        )
        // 空显示名
        assertTrue(
            runCatching { ShellBuilder.build(files, "434800000001", "", good) }
                .exceptionOrNull() is ShellWriter.PackError,
        )
    }
}
