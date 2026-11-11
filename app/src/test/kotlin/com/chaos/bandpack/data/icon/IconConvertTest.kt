package com.chaos.bandpack.data.icon

import com.chaos.bandpack.data.DeviceTarget
import org.junit.Assert.assertEquals
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * p67 完整画布转换、旧原生 BIN 与 9 Pro 底板约束的回归。
 * 槽位漂移守卫另读取设备侧 icon_apply.rs；缺少源码时明确失败。
 * 合成图像的几何与透明度参考见 NativeIconRenderingTest，GIF 参考见 GifIconsTest。
 */
class IconConvertTest {

    private val repo: File = File(System.getProperty("chaos.repo") ?: "../..").canonicalFile

    // ===== 1. 槽位表必须与内核模块一致（减掉设备上不存在的那几个） =====

    @Test
    fun `槽位表等于 icon_apply_rs 的 ICON_STEMS 去掉设备上不存在的应用`() {
        val rs = listOf(File(repo, "supervisor/src/icon_apply.rs"),
            File(repo, "Chaos-Module/supervisor/src/icon_apply.rs")).firstOrNull { it.isFile }
            ?: error("找不到设备侧 supervisor/src/icon_apply.rs，请按 README 准备 chaos.repo")
        val text = rs.readText()
        val block = Regex("const ICON_STEMS: \\[&\\[u8\\]; [^\\]]+\\] = \\[(.*?)\\];", RegexOption.DOT_MATCHES_ALL)
            .find(text)?.groupValues?.get(1) ?: error("没解析出 ICON_STEMS")
        val names = Regex("b\"([^\"]+)\"").findAll(block).map { it.groupValues[1] }.toList()
        assertEquals("内核模块里的图标条数变了", 38, names.size)
        // 例外集合只准是内核表里的名字, 否则这条减法会悄悄放过一个拼错的名字
        assertTrue(
            "ABSENT_ON_DEVICE 里有名字不在内核表里",
            IconSpec.ABSENT_ON_DEVICE.all { it in names },
        )
        assertEquals(
            "安卓端槽位表与 icon_apply.rs 不一致",
            names.filterNot { it in IconSpec.ABSENT_ON_DEVICE }.sorted(),
            IconSpec.DESKTOP.map { it.stem }.sorted(),
        )
    }

    // ===== 1b. 中文名必须照真实显示名, 不许按英文 stem 猜 =====

    @Test
    fun `几个曾被猜错的中文名保持在真值上`() {
        // 这几条原来是照英文 stem 猜的, 全猜错了(血压/活力/分享/计步/呼吸训练/互联/
        // 运动课程/健身记录), 逐个对着设备核过。钉住它们, 防止以后又被"顺手改回去"。
        val truth = mapOf(
            "activities" to "活力指标",
            "breath" to "呼吸放松",
            "camera" to "遥控拍照",
            "calendar" to "日程",
            "perpetual_calendar" to "日历",
            "interconnect" to "多端联动",
            "mute" to "手机静音",
            "pressure" to "压力",
            "share" to "融合设备中心",
            "sports_course" to "跑步课程",
            "sports_record" to "运动记录",
            "sports_status" to "训练状态",
            "vitality" to "元气值",
        )
        for ((stem, label) in truth) {
            assertEquals("$stem 的显示名不对", label, IconSpec.stemOf(stem)?.label)
        }
    }

    // ===== 2. 图像转换与跨设备兼容 =====

    @Test
    fun `旧112原生BIN导出时不改变像素或尺寸`() {
        val original = javaClass.getResourceAsStream("/gif/legacy112.bin")!!.use { it.readBytes() }
        val exported = PortableIcons.forTarget(mapOf("weather" to original), DeviceTarget.TEN_PRO)
        assertArrayEquals(original, exported.icons.single { it.stem == "weather" }.data)
        assertEquals(112, LvglIconCodec.decode(original).width)
    }

    @Test
    fun `9Pro透明底裸图形仍被拒绝并说明原因`() {
        // 透明底 + 一条 5px 粗的对角线。注意覆盖率是在**外接方框内**算的，
        // 所以"实心小方块"覆盖率是 1（它把自己的方框填满了）——这也是为什么
        // 这条判据能区分"底板"和"裸图形"：看的是形状填不填得满自己的方框。
        val n = 120
        val px = IntArray(n * n)
        for (t in 10..109) {
            for (d in -2..2) {
                val x = t
                val y = t + d
                if (x in 0 until n && y in 0 until n) px[y * n + x] = 0xFF3366FF.toInt()
            }
        }
        val e = runCatching { IconConvert.convert(px, n, n, IconSpec.stemOf("weather", DeviceTarget.NINE_PRO)!!) }.exceptionOrNull()
        assertTrue("透明底裸图形应被拒绝，实际: $e", e is IconConvert.NoPlate)
        assertTrue("拒绝理由应说清楚原因与覆盖率: ${e!!.message}",
            e.message!!.contains("底板") && e.message!!.contains("5%"))
    }

    @Test
    fun `实心小图不会被误判为裸图形`() {
        // p67 保留 100x100 完整画布；其中 40x40 实心图形覆盖约 16%，仍可导出。
        val n = 100
        val px = IntArray(n * n)
        for (y in 30 until 70) for (x in 30 until 70) px[y * n + x] = 0xFF3366FF.toInt()
        val (out, rep) = IconConvert.convert(px, n, n)
        assertTrue(rep.coverage in 0.12..0.18)
        assertEquals(100, rep.srcBoxSide)
        assertEquals(IconSpec.OUT_BYTES, out.size)
    }

    @Test
    fun `p67整幅透明图仍可导出`() {
        val bytes = IconConvert.convert(IntArray(64 * 64), 64, 64).first
        assertTrue(LvglIconCodec.decode(bytes).pixels.all { it == 0 })
    }

    @Test
    fun `小图会被放大到96并保持完整画布`() {
        val n = 48
        val px = IntArray(n * n) { 0xFF22AA44.toInt() }   // 整幅实心 => 覆盖率 1.0
        val (out, rep) = IconConvert.convert(px, n, n)
        assertEquals(IconSpec.OUT_BYTES, out.size)
        assertEquals(IconSpec.CONTENT, rep.scaled)
        assertTrue("完整实心画布应全部保留", LvglIconCodec.decode(out).pixels.all { it == 0xff22aa44.toInt() })
    }

    @Test
    fun `通道顺序是 BGRA`() {
        val n = 32
        val px = IntArray(n * n) { 0xFF112233.toInt() }   // A=FF R=11 G=22 B=33
        val (out, _) = IconConvert.convert(px, n, n)
        val o = 12 + ((IconSpec.CANVAS / 2) * IconSpec.CANVAS + IconSpec.CANVAS / 2) * 4
        assertEquals("B 应在第 1 字节", 0x33, out[o].toInt() and 0xFF)
        assertEquals("G 应在第 2 字节", 0x22, out[o + 1].toInt() and 0xFF)
        assertEquals("R 应在第 3 字节", 0x11, out[o + 2].toInt() and 0xFF)
        assertEquals("A 应在第 4 字节", 0xFF, out[o + 3].toInt() and 0xFF)
    }
}
