package com.chaos.bandpack.data.icon

import com.chaos.bandpack.data.pack.Cipk
import org.junit.Assert.*
import org.junit.Test
import java.io.File

/** 各槽位规格、透明图形与实际导出载荷的回归。 */
class SystemIconsTest {
    private fun plate() = IntArray(80 * 80) { 0xff3366aa.toInt() }
    private fun glyph(): IntArray = IntArray(96 * 48).also { px ->
        for (y in 8 until 40) for (x in 8 until 88) {
            val edge = x < 10 || x >= 86 || y < 10 || y >= 38
            px[y * 96 + x] = (if (edge) 0x703366aa else 0xff3366aa).toInt()
        }
    }
    @Test fun `系统图保留透明度且长边不被裁掉`() {
        val slot = IconSpec.stemOf("ctrl_disturb")!!
        val (bin, _) = IconConvert.convert(glyph(), 96, 48, slot)
        val image = LvglIconCodec.decode(bin)
        assertEquals(64, image.width); assertEquals(64, image.height)
        assertTrue(image.pixels.any { it ushr 24 in 1..254 })
        assertEquals(0, image.pixels[0])
        val visible = image.pixels.indices.filter { image.pixels[it] ushr 24 > 24 }
        assertTrue(visible.minOf { it % 64 } < 2 && visible.maxOf { it % 64 } > 61)
        assertTrue(visible.minOf { it / 64 } >= 18 && visible.maxOf { it / 64 } <= 45)
        val thin = IntArray(64 * 64).also { for (i in 0..63) it[i * 64 + i] = -1 }
        assertTrue(runCatching { IconConvert.convert(thin, 64, 64) }.exceptionOrNull() is IconConvert.NoPlate)
        assertEquals(64, LvglIconCodec.decode(IconConvert.convert(thin, 64, 64, slot).first).width)
    }
    @Test fun `勿扰一槽输出两种资源且清空后全部缺席`() {
        val bin = IconConvert.convert(glyph(), 96, 48, IconSpec.stemOf("ctrl_disturb")!!).first
        val icons = IconSpec.export(mapOf("ctrl_disturb" to bin))
        assertEquals(setOf("ctrl_disturb", "ctrl_dnd"), icons.map { it.stem }.toSet())
        val dnd = icons.single { it.stem == "ctrl_dnd" }.data
        assertArrayEquals(LvglIconCodec.header(160, 124, 10, 8, 160), dnd.copyOfRange(0, 12))
        val decoded = LvglIconCodec.decode(dnd)
        val source = LvglIconCodec.decode(bin)
        for (y in 0 until 124) for (x in 0 until 160) {
            val expect = if (x in 48..111 && y in 30..93) source.pixels[(y - 30) * 64 + x - 48] else 0
            assertEquals(expect, decoded.pixels[y * 160 + x])
        }
        assertTrue(IconSpec.export(emptyMap()).isEmpty())
        val damaged = dnd.copyOf().also { it[16] = (it[16].toInt() xor 1).toByte() }
        assertTrue("坏压缩长度必须拒绝", runCatching { LvglIconCodec.decode(damaged) }.isFailure)
        val dump = File("build/icon120-check").apply { mkdirs() }
        File(dump, "ctrl_disturb.bin").writeBytes(bin); File(dump, "ctrl_dnd.bin").writeBytes(dnd)
    }
    @Test fun `调色板超过256色仍保留透明边且编码可解`() {
        val pixels = IntArray(160 * 124) { i ->
            val x = i % 160; val y = i / 160
            if (x !in 48..111 || y !in 30..93) 0
            else ((80 + (x + y) % 176) shl 24) or (x * 3 % 256 shl 16) or (y * 5 % 256 shl 8) or ((x + y) % 256)
        }
        val bin = LvglIconCodec.indexedRle(pixels, 160, 124)
        val decoded = LvglIconCodec.decode(bin)
        assertEquals(0, decoded.pixels[0])
        assertTrue(decoded.pixels.any { it ushr 24 in 1..254 })
        assertTrue(bin.contentEquals(LvglIconCodec.indexedRle(pixels, 160, 124)))
        File("build/icon120-check").apply { mkdirs() }.resolve("ctrl_dnd_gradient.bin").writeBytes(bin)
    }
    @Test fun `55槽共56文件蓝牙与心率广播缺席`() {
        assertEquals(36, IconSpec.DESKTOP.size); assertEquals(9, IconSpec.CONTROL.size)
        assertEquals(10, IconSpec.SETTINGS.size)
        assertEquals(55, IconSpec.SLOTS.size)
        assertNull(IconSpec.stemOf("set_hr"))
        assertNull(IconSpec.matchName("设置_心率广播"))
        val selected = IconSpec.SLOTS.associate { slot -> slot.stem to IconConvert.convert(plate(), 80, 80, slot).first }
        val icons = IconSpec.export(selected)
        assertEquals(56, icons.size)
        assertTrue(icons.none { "phone_conn" in it.stem || "phone_disconn" in it.stem })
        assertTrue(icons.none { it.stem == "set_hr" })
        assertEquals(2, icons.count { it.stem in setOf("calendar", "perpetual_calendar") })
        val dumped = File("build/icon120-check").apply { mkdirs() }
        val cipk = Cipk.build(icons); File(dumped, "pack.bin").writeBytes(cipk)
        assertEquals(56, Cipk.parse(cipk).size)
        val calendar = selected.getValue("perpetual_calendar")
        assertTrue(runCatching { IconSpec.export(mapOf("ctrl_phone_conn" to calendar)) }.isFailure)
        assertTrue(runCatching { IconSpec.export(mapOf("set_hr" to calendar)) }.isFailure)
        assertTrue(IconSpec.export(selected - "calendar" - "perpetual_calendar" - "ctrl_disturb").none {
            it.stem in setOf("calendar", "perpetual_calendar", "ctrl_disturb", "ctrl_dnd")
        })
    }
    @Test fun `日历与日程的预览导入导出独立且分别清空`() {
        assertEquals("日程", IconSpec.stemOf("calendar")!!.label)
        assertEquals("日历", IconSpec.stemOf("perpetual_calendar")!!.label)
        assertEquals(listOf("calendar"), IconSpec.previewStems("calendar"))
        assertEquals(listOf("calendar_background"), IconSpec.previewStems("perpetual_calendar"))
        assertTrue(IconSpec.duplicateStems(listOf("calendar.png", "日历.png")
            .map { IconSpec.matchName(it.substringBeforeLast('.'))?.stem }).isEmpty())
        assertEquals(setOf("calendar"), IconSpec.duplicateStems(listOf("calendar.png", "日程.png")
            .map { IconSpec.matchName(it.substringBeforeLast('.'))?.stem }))
        val schedule = IconConvert.convert(plate(), 80, 80, IconSpec.stemOf("calendar")!!).first
        val calendar = IconConvert.convert(IntArray(80 * 80) { 0xffcc6633.toInt() }, 80, 80,
            IconSpec.stemOf("perpetual_calendar")!!).first
        val picked = mapOf("calendar" to schedule, "perpetual_calendar" to calendar)
        val both = IconSpec.export(picked)
        assertEquals(setOf("calendar", "perpetual_calendar"), both.map { it.stem }.toSet())
        assertArrayEquals(schedule, both.single { it.stem == "calendar" }.data)
        assertArrayEquals(calendar, both.single { it.stem == "perpetual_calendar" }.data)
        assertFalse(schedule.contentEquals(calendar))
        val dump = File("build/icon120-check").apply { mkdirs() }
        for (stem in picked.keys) {
            val one = IconSpec.export(picked - picked.keys.single { it != stem })
            assertEquals(listOf(stem), one.map { it.stem })
            assertEquals(listOf("$stem.bin"), Cipk.parse(Cipk.build(one)).map { it.first })
            File(dump, "$stem-pack.bin").writeBytes(Cipk.build(one))
        }
        File(dump, "calendar-and-schedule-pack.bin").writeBytes(Cipk.build(both))
        assertTrue(IconSpec.export(picked - picked.keys).isEmpty())
    }
    @Test fun `系统规则与设备侧映射一致`() {
        val repo = File(System.getProperty("chaos.repo") ?: error("必须指定 chaos.repo"))
        val source = listOf(File(repo, "Chaos-Module/supervisor/src/res_hook.rs"), File(repo, "supervisor/src/res_hook.rs"))
            .firstOrNull { it.isFile } ?: error("系统映射源缺失")
        val stems = Regex("stem: b\"([^\"]+)\"").findAll(source.readText()).map { it.groupValues[1] }.toSet()
        assertEquals(stems - setOf("ctrl_phone_conn", "ctrl_phone_disconn", "cal_background", "ctrl_dnd", "set_hr"),
            (IconSpec.CONTROL + IconSpec.SETTINGS).map { it.stem }.toSet())
    }
}
