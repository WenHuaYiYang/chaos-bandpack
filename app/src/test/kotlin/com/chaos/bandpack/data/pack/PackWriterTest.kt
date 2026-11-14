package com.chaos.bandpack.data.pack

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 投递包写入器的校验。分两组:
 *
 * **跟着仓库走的那一组**(不需要任何外部素材): 用合成的 Lua 模板与占位载荷把两种包打出来,
 * 再拆回来核对结构。它保证"打包链本身"在任何机器上都是通的。
 *
 * **需要对拍素材的那一组**(设备侧仓库 / PC 侧产物 / 图标素材): 必须具备对应素材 ——
 * 素材缺失即失败。旧 PC 图标包用于包名哈希和原样导入回归；
 * 新两资源图标包与 Python 的逐字节对拍位于 AnimatedPackTest。
 *
 * 字体包做不到逐字节(PC 侧用 fontTools 重写字体, 我们是手写子集化), 那一条改成两条能钉死的:
 * 结构 + "包号由载荷哈希推出来"。
 */
class PackWriterTest {

    // ===== 工具 =====

    private val repo: File = File(System.getProperty("chaos.repo") ?: "../../Chaos-Module").canonicalFile

    /** 设备侧工程根旁边那些产物(PC 打的包、图标素材目录): chaos.repo 指向工程根或其上一层都能找到 */
    private fun artifact(name: String): File? =
        listOf(File(repo, "dist/$name"), File(repo, name), File(repo.parentFile, name))
            .firstOrNull { it.exists() }

    /** 合成模板: 占位符各出现一次, 打包器的门就是照这个口径立的 */
    private val fakeAssets = PackAssets(
        ko = ByteArray(64) { it.toByte() },
        iconBin = ByteArray(48) { (it * 3).toByte() },
        fontLua = "local FONT_NAME = \"__FONT_NAME__\"\n" +
            "local PACK_LABEL = \"__PACK_LABEL__\"\n" +
            "local PACK_TITLE = \"__PACK_TITLE__\"\n",
        iconLua = "local PACK_NAME = \"__PACK_NAME__\"\n" +
            "local PACK_TITLE = \"__PACK_TITLE__\"\n",
    )

    /** 一块合法的预览(头 + 任意载荷): 打包器只校验头与长度自洽 */
    private fun fakePreview(size: Int = 512): ByteArray {
        val payload = ByteArray(size) { (it * 31 % 251).toByte() }
        val head = byteArrayOf(0x10, 0x04, 0, 0, 0x50, 0x01, 0xE0.toByte(), 0x01) +
            byteArrayOf(
                (size and 0xFF).toByte(), ((size shr 8) and 0xFF).toByte(),
                ((size shr 16) and 0xFF).toByte(), 0,
            )
        return head + payload
    }

    // ===== 1. 跟着仓库走的: 结构 =====

    @Test
    fun `字体包四槽结构正确且记录表与预览块自洽`() {
        val font = ByteArray(1024) { (it % 251).toByte() }
        val preview = fakePreview(5000)
        val res = FontPackBuilder.build(fakeAssets, FontPackBuilder.Inputs(
            label = "文楷", packName = "字:文楷", title = "字体投递 文楷", pkgName = null, font = font,
        ), preview)

        val p = ShellBuilder.parse(res.bytes)
        assertEquals("槽数不是 4", 4, p.files.size)
        assertEquals(
            listOf(
                "_lua/fontpack/main.lua", "_lua/fontpack/chaos_sup.ko",
                "_lua/fontpack/chaos_icon.bin", "_lua/fontpack/font.ttf",
            ),
            p.files.map { it.first },
        )
        assertEquals("包名不是自动推导的", ShellWriter.pkgFor(font), res.pkgName)
        assertEquals("显示名写错", "字:文楷", p.displayName)
        assertArrayEquals("注入的预览块没有原样进包", preview, p.preview)
        // 第 2、3 槽就是素材本身, 第 4 槽是载荷
        assertArrayEquals(fakeAssets.ko, p.files[1].second)
        assertArrayEquals(fakeAssets.iconBin, p.files[2].second)
        assertArrayEquals(font, p.files[3].second)
        // Lua 里三个占位符都被替换, 标题是整句
        val lua = String(p.files[0].second, Charsets.UTF_8)
        for (ph in listOf(FontPackBuilder.PH_NAME, FontPackBuilder.PH_LABEL, FontPackBuilder.PH_TITLE)) {
            assertTrue("Lua 里还有占位符 $ph", ph !in lua)
        }
        assertTrue("标题没写进去", lua.contains("local PACK_TITLE = \"字体投递 文楷\""))
        assertTrue("清单短名没写进去", lua.contains("local FONT_NAME = \"文楷\""))
        assertTrue("包名撞主包号", res.pkgName != ShellWriter.MAIN_PKG)
    }

    @Test
    fun `图标包两资源结构正确且CIPK往返一致`() {
        val icons = listOf(
            Cipk.Icon("alarm", com.chaos.bandpack.data.icon.LvglIconCodec.bgra(IntArray(96 * 96) { 0xff3366aa.toInt() }, 96, 96)),
            Cipk.Icon("heartrate", com.chaos.bandpack.data.icon.LvglIconCodec.bgra(IntArray(96 * 96) { 0xffaa6633.toInt() }, 96, 96)),
        )
        val res = IconPackBuilder.build(fakeAssets, IconPackBuilder.Inputs(
            short = "Demo", packName = "图标:Demo", title = "图标投递 Demo",
            pkgName = null, icons = icons,
        ), fakePreview(800))

        val p = ShellBuilder.parse(res.bytes)
        assertEquals(2, p.files.size)
        assertEquals(3, res.iconCount)
        assertEquals(
            listOf(
                "_lua/xiaomi-band-10-pro/main.lua", "_lua/xiaomi-band-10-pro/pack.bin",
            ),
            p.files.map { it.first },
        )
        val cipk = p.files[1].second
        assertEquals("包名不是 CIPK 的哈希", ShellWriter.pkgFor(cipk), res.pkgName)
        val back = Cipk.parse(cipk)
        assertEquals(3, back.size)
        assertEquals("alarm.bin", back[0].first)
        assertArrayEquals(icons[0].data, back[0].second)
        val lua = String(p.files[0].second, Charsets.UTF_8)
        assertTrue("短名没写进 Lua", lua.contains("local PACK_NAME = \"Demo\""))
    }

    @Test
    fun `手动指定包名时撞主包号会被拒绝`() {
        val e = runCatching {
            FontPackBuilder.build(fakeAssets, FontPackBuilder.Inputs(
                label = "x", packName = "字:x", title = "字体投递 x",
                pkgName = ShellWriter.MAIN_PKG, font = ByteArray(16),
            ), fakePreview(64))
        }.exceptionOrNull()
        assertTrue("撞主包号应被拒绝, 实际 $e", e is ShellWriter.PackError)
    }

    // ===== 2. 跟着仓库走的: 输入门与文本口径 =====

    @Test
    fun `非法输入被明确拒绝`() {
        // 短名超 12 字节
        val e1 = runCatching {
            FontPackBuilder.build(fakeAssets, FontPackBuilder.Inputs(
                label = "这是一个很长的名字", packName = "字:x", title = "字体投递 x",
                pkgName = null, font = ByteArray(16),
            ), fakePreview(64))
        }.exceptionOrNull()
        assertTrue("超长短名应被拒绝, 实际 $e1", e1 is ShellWriter.PackError)

        // 包名不是 12 位数字 / 撞主包号
        assertTrue(runCatching { ShellWriter.checkPkg("43482026092") }.exceptionOrNull() is ShellWriter.PackError)
        assertTrue(
            runCatching { ShellWriter.checkPkgAgainst(ShellWriter.MAIN_PKG) }.exceptionOrNull()
                is ShellWriter.PackError,
        )
        assertTrue(runCatching { ShellWriter.checkPkgAgainst("434800000001") }.exceptionOrNull() == null)

        // 显示名超 64 字节
        assertTrue(
            runCatching { ShellWriter.checkName("很".repeat(30)) }.exceptionOrNull()
                is ShellWriter.PackError,
        )

        // 图标包短名只允许 ASCII 字母、数字、下划线和连字符
        assertTrue(
            runCatching {
                IconPackBuilder.build(fakeAssets, IconPackBuilder.Inputs(
                    short = "中文", packName = "图标:中文", title = "图标投递 中文",
                    pkgName = null, icons = listOf(Cipk.Icon("alarm", ByteArray(8))),
                ), fakePreview(64))
            }.exceptionOrNull() is ShellWriter.PackError,
        )

        // 标题里的引号会被转义, 不破坏 Lua
        val res = FontPackBuilder.build(fakeAssets, FontPackBuilder.Inputs(
            label = "x", packName = "字:x", title = "标题\"带\\引号", pkgName = null, font = ByteArray(32),
        ), fakePreview(64))
        val lua = String(ShellBuilder.parse(res.bytes).files[0].second, Charsets.UTF_8)
        assertTrue("引号没被转义", lua.contains("local PACK_TITLE = \"标题\\\"带\\\\引号\""))
    }

    @Test
    fun `模板占位符必须恰好出现一次且换行归一成 LF`() {
        // CRLF 模板会被折成 LF(PC 侧用文本模式读, 两侧产出的字节数才一致)
        val crlf = PackAssets(
            ko = ByteArray(4), iconBin = ByteArray(4),
            fontLua = "local FONT_NAME = \"__FONT_NAME__\"\r\nlocal PACK_TITLE = \"__PACK_TITLE__\"\r\n",
            iconLua = "local PACK_NAME = \"__PACK_NAME__\"\r\nlocal PACK_TITLE = \"__PACK_TITLE__\"\r\n",
        )
        val out = patchLua(crlf.fontLua, mapOf(
            FontPackBuilder.PH_NAME to "a", FontPackBuilder.PH_TITLE to "b",
        ))
        assertTrue("CRLF 没被折成 LF", "\r" !in out)

        // 某个占位符出现两次 => 打死(多了说明有地方会漏改)
        val twice = "local FONT_NAME = \"__FONT_NAME__\"\nlocal X = \"__FONT_NAME__\"\n"
        assertTrue(
            runCatching { patchLua(twice, mapOf(FontPackBuilder.PH_NAME to "a")) }
                .exceptionOrNull() is ShellWriter.PackError,
        )
        // 少一个 => 也打死
        assertTrue(
            runCatching { patchLua("local A = 1\n", mapOf(FontPackBuilder.PH_NAME to "a")) }
                .exceptionOrNull() is ShellWriter.PackError,
        )
        // 控制字符走十进制转义
        assertEquals("a\\007b", luaQuote("a\u0007b"))
    }

    @Test
    fun `标题宽度按半角计算并给出超宽提醒`() {
        // "字体投递 花朝粗" = 7 个汉字(14) + 1 个空格 = 15, 正好在上限内
        assertEquals(15, TitleText.width("字体投递 花朝粗"))
        assertEquals(null, TitleText.validate("字体投递 花朝粗"))
        // 8 个汉字 = 16, 到顶但不超
        assertEquals(16, TitleText.width("字体投递花朝粗体"))
        assertEquals(null, TitleText.validate("字体投递花朝粗体"))
        // 9 个汉字 = 18, 超了
        val msg = TitleText.validate("字体投递花朝粗字体")
        assertTrue("超宽应给出提醒, 实际 $msg", msg != null && msg.contains("16"))
        // ASCII 一律算 1
        assertEquals(11, TitleText.width("Font Deluxe"))
        assertEquals(null, TitleText.validate("Font Deluxe Pack"))
        // 空标题
        assertTrue(TitleText.validate("   ") != null)
    }

    @Test
    fun `CIPK 往返与边界`() {
        val icons = listOf(
            Cipk.Icon("alarm", ByteArray(100) { 1 }),
            Cipk.Icon("sports_record", ByteArray(50) { 2 }),
        )
        val blob = Cipk.build(icons)
        val back = Cipk.parse(blob)
        assertEquals(2, back.size)
        assertEquals("alarm.bin", back[0].first)
        assertArrayEquals(icons[0].data, back[0].second)
        assertEquals("sports_record.bin", back[1].first)

        // 空列表 / 重复 stem / 非法名字
        assertTrue(runCatching { Cipk.build(emptyList()) }.exceptionOrNull() is Cipk.CipkError)
        assertTrue(
            runCatching { Cipk.build(listOf(icons[0], icons[0])) }.exceptionOrNull() is Cipk.CipkError
        )
        assertTrue(
            runCatching { Cipk.build(listOf(Cipk.Icon("bad-name", ByteArray(4)))) }
                .exceptionOrNull() is Cipk.CipkError
        )
        // 尾部多字节必须被发现
        assertTrue(runCatching { Cipk.parse(blob + ByteArray(3)) }.exceptionOrNull() is Cipk.CipkError)
    }

    // ===== 3. 要对拍素材的: 与 PC 侧一致 =====

    @Test
    fun `包名哈希与 PC 侧一致(拿 PC 打的包反推)`() {
        val iconPack = artifact("chaos-iconpack-Delta.bin")
        assertTrue("没有 PC 侧图标包, 跳过", iconPack != null)
        val d = iconPack!!.readBytes()
        val (path, cipk) = ShellWriter.readEntry(d, 4)
        assertTrue(path.endsWith("pack.bin"))
        val pkg = String(d, ShellWriter.PKG_OFF, ShellWriter.PKG_LEN, Charsets.US_ASCII)
        assertEquals("CIPK 哈希推导的包名与 PC 侧不一致", pkg, ShellWriter.pkgFor(cipk))
    }

    @Test
    fun `旧PC投递包中的素材仍可原样导入`() {
        val pcPack = artifact("chaos-iconpack-Delta.bin")
        assertTrue("没有 PC 侧旧图标包，不能验证兼容性", pcPack != null)
        val raw = pcPack!!.readBytes()
        val oldFiles = Cipk.parse(ShellWriter.readEntry(raw, 4).second)
        val imported = com.chaos.bandpack.data.project.PackBinImport.read(raw).icons!!.images
        for ((name, bytes) in oldFiles) {
            if (name != "animations.bin") assertArrayEquals(name, bytes, imported[name.removeSuffix(".bin")])
        }
    }

    @Test
    fun `主包号常量与设备侧那份主包一致`() {
        val main = artifact("chaos-installer-10p-043-v1.bin")
        assertTrue("本地没有主包, 跳过(主包是构建产物, 不入库)", main != null)
        val pkg = String(main!!.readBytes(), ShellWriter.PKG_OFF, ShellWriter.PKG_LEN, Charsets.US_ASCII)
        assertEquals(
            "App 里的主包号常量与设备侧主包不一致(改了主包号要同步 ShellWriter.MAIN_PKG)",
            pkg, ShellWriter.MAIN_PKG,
        )
    }
}
