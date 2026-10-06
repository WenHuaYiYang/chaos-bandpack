package com.chaos.bandpack.data.pack

import com.chaos.bandpack.data.DeviceTarget
import com.chaos.bandpack.data.font.Sfnt
import com.chaos.bandpack.data.icon.*
import com.chaos.bandpack.data.project.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.io.ByteArrayOutputStream
import java.util.zip.*
import kotlinx.serialization.json.*

/** 真实旧包、独立壳样本和损坏对照验证导入与跨设备转换。 */
class DualDeviceProjectTest {
    private val root = File(System.getProperty("chaos.repo") ?: error("必须指定 chaos.repo"))
    private val nine = File(System.getProperty("chaos.n67.repo") ?: error("必须指定 chaos.n67.repo"))
    private val template get() = File(nine, "n67/importer.lua.in").readText(Charsets.UTF_8)
    private fun golden(count: Int) = File(nine.parentFile, "chaos-bandpack-9pro/app/src/test/resources/n67/golden-$count.bin").readBytes()
    private fun assets(): PackAssets = PackAssets(File(root, "Chaos-Module/supervisor/chaos_sup.ko").readBytes(),
        File(root, "Chaos-Module/chaos_icon.bin").readBytes(), File(root, "Chaos-Module/installer/font_pack.lua").readText(),
        File(root, "Chaos-Module/installer/icon_pack.lua").readText())
    private fun preview() = NineShellBuilder.previewOf(golden(1))
    private val info = PackInfo("Demo", "图标 Demo", "图标投递 Demo")
    private val output = File("build/dual-device-check").apply { mkdirs() }
    private fun tenImage() = LvglIconCodec.bgra(IntArray(112 * 112) { i ->
        val x = i % 112; val y = i / 112
        if (x in 6..105 && y in 6..105) 0x803366aa.toInt() else 0
    }, 112, 112)
    private fun validFont() = File(root, "Chaos-Module/fonts/lxgw-wenkai-band.ttf").takeIf { it.isFile }?.readBytes()
        ?: File(System.getProperty("user.home"), "Downloads/LXGWWenKai-Regular.ttf").readBytes()

    @Test fun independentNineShellGoldenAndBrokenLength() {
        for (count in listOf(1, 4, 30, 126)) {
            val raw = golden(count); val parsed = NineShellBuilder.parse(raw)
            assertEquals(count, parsed.files.size)
            assertArrayEquals(raw, NineShellBuilder.build(parsed.files.map { NineShellBuilder.Entry(it.first, it.second) },
                parsed.pkg, parsed.displayName, parsed.preview, parsed.themeName))
        }
        val broken = golden(4).also { ShellWriter.writeU32(it, 0x158 + 12, Int.MAX_VALUE) }
        assertTrue(runCatching { NineShellBuilder.parse(broken) }.isFailure)
        assertTrue(runCatching { NineShellBuilder.build(listOf(NineShellBuilder.Entry("_lua/_Lua/a.dat", ByteArray(65536))),
            "434812341234", "oversize", preview()) }.isFailure)
    }

    @Test fun mappingsAgreeWithOriginalPortAndNoBluetoothExport() {
        val desktop = Json.parseToJsonElement(File(nine, "n67/icon-mapping.json").readText()).jsonArray
        val system = Json.parseToJsonElement(File(nine, "n67/system-icon-mapping.json").readText()).jsonArray
        assertEquals(81, NineIconSpec.SLOTS.size)
        val expected = (desktop + system).filter { it.jsonObject["stem"]!!.jsonPrimitive.content !in listOf("ctrl_phone_conn", "ctrl_phone_disconn") }
        assertEquals(expected.map { it.jsonObject["stem"]!!.jsonPrimitive.content }.toSet(), NineIconSpec.SLOTS.map { it.fileStem }.toSet())
        expected.forEach { entry ->
            val row = entry.jsonObject; val slot = NineIconSpec.SLOTS.single { it.fileStem == row["stem"]!!.jsonPrimitive.content }
            assertEquals(row["width"]?.jsonPrimitive?.int ?: 100, slot.width)
            assertEquals(row["height"]?.jsonPrimitive?.int ?: 100, slot.height)
        }
        assertEquals("calendar", IconSpec.matchName("schedule", DeviceTarget.NINE_PRO)!!.stem)
        assertEquals("todo", IconSpec.matchName("dealt", DeviceTarget.NINE_PRO)!!.stem)
        assertNull(IconSpec.stemOf("ctrl_phone_conn", DeviceTarget.NINE_PRO))
        assertEquals(listOf("set_wrist"), IconSpec.previewStems("set_safe"))
        assertEquals(listOf("set_safe"), IconSpec.previewStems("set_wrist"))
    }

    @Test fun pixelsAndTransparencyRoundTripAcrossDevices() {
        val original = tenImage()
        val source = linkedMapOf("weather" to original, "perpetual_calendar" to original)
        val converted = PortableIcons.forTarget(source, DeviceTarget.NINE_PRO)
        assertEquals(listOf("perpetual_calendar"), converted.omitted)
        assertEquals(1, converted.selected)
        val bytes = converted.icons.single().data
        assertEquals(40004, bytes.size)
        val image = LvglIconCodec.decode(bytes)
        assertEquals(0x803366aa.toInt(), image.pixels[0])
        val back = PortableIcons.forTarget(mapOf("weather" to bytes), DeviceTarget.TEN_PRO)
        assertArrayEquals(original, back.icons.single().data)
        val slot = NineIconSpec.SLOTS.single { it.fileStem == "hr_rest" }
        val (rect, _) = IconConvert.convert(IntArray(100 * 100) { 0x803366aa.toInt() }, 100, 100, slot)
        assertEquals(64, LvglIconCodec.decode(rect).width); assertEquals(56, LvglIconCodec.decode(rect).height)
        assertTrue(runCatching { LvglIconCodec.decode(bytes.copyOf(bytes.size - 1)) }.isFailure)
    }

    @Test fun old35IconPackCanBeEditedAndConverted() {
        val legacy = File(System.getProperty("user.home"), "Downloads/chaos-iconpack-pure.bin").readBytes()
        val source = PackBinImport.read(legacy)
        assertEquals(DeviceTarget.TEN_PRO, source.device)
        assertEquals(35, source.icons!!.images.size)
        val replaced = source.icons.images + ("weather" to tenImage())
        val transformed = PortableIcons.forTarget(replaced, DeviceTarget.NINE_PRO)
        val result = NinePackBuilder.icons(template, IconPackBuilder.Inputs("PureNew", source.icons.info.display,
            source.icons.info.title, null, transformed.icons), preview())
        val imported = PackBinImport.read(result.bytes)
        assertEquals(DeviceTarget.NINE_PRO, imported.device)
        assertEquals(transformed.selected, imported.icons!!.images.size)
        assertEquals(40004, imported.icons.images.getValue("weather").size)
        assertTrue(transformed.omitted.isNotEmpty())
        assertFalse(NineShellBuilder.parse(result.bytes).files.any { it.first.endsWith(".ko") })
        val nineBack = PortableIcons.forTarget(imported.icons.images, DeviceTarget.TEN_PRO)
        val rebuilt = IconPackBuilder.build(assets(), IconPackBuilder.Inputs("PureNew", "旧包转换", "图标投递 PureNew", null, nineBack.icons), preview())
        assertEquals(nineBack.selected, PackBinImport.read(rebuilt.bytes).icons!!.images.size)
        File(output, "converted-nine.bin").writeBytes(result.bytes)
        File(output, "converted-ten.bin").writeBytes(rebuilt.bytes)
        File(output, "legacy.chaosproj").writeBytes(ProjectCodec.write(source))
        val broken = legacy.copyOf().also { ShellWriter.writeU32(it, 0x20, Int.MAX_VALUE) }
        assertTrue(runCatching { PackBinImport.read(broken) }.isFailure)
    }

    @Test fun allNineSlotsAndDndDifferences() {
        val picked = NineIconSpec.SLOTS.associate { slot -> slot.stem to LvglIconCodec.bgra8(IntArray(slot.width * slot.height) { 0xff23aedd.toInt() }, slot.width, slot.height) }
        val result = PortableIcons.forTarget(picked, DeviceTarget.NINE_PRO)
        val pack = NinePackBuilder.icons(template, IconPackBuilder.Inputs("AllNine", "全部图标", "图标导入", null, result.icons), preview())
        assertEquals(82, NineShellBuilder.parse(pack.bytes).files.size)
        val imported = PackBinImport.read(pack.bytes)
        assertEquals(picked.keys, imported.icons!!.images.keys)
        assertTrue(result.icons.none { "phone_conn" in it.stem || "phone_disconn" in it.stem })
        val dnd = picked.getValue("ctrl_disturb")
        val ten = PortableIcons.forTarget(mapOf("ctrl_disturb" to dnd), DeviceTarget.TEN_PRO)
        assertEquals(setOf("ctrl_disturb", "ctrl_dnd"), ten.icons.map { it.stem }.toSet())
        assertEquals(160, LvglIconCodec.decode(ten.icons.single { it.stem == "ctrl_dnd" }.data).width)
        File(output, "icons-pack.bin").writeBytes(pack.bytes)
    }

    @Test fun fontChunkConversionKeepsExactBytes() {
        val font = validFont(); Sfnt(font)
        val pack = NinePackBuilder.font(template, FontPackBuilder.Inputs("FontNew", "字体包", "字体投递", null, font), preview())
        val chunks = NineShellBuilder.parse(pack.bytes).files.drop(1)
        assertTrue(chunks.dropLast(1).all { it.second.size == 64000 })
        val imported = PackBinImport.read(pack.bytes)
        assertTrue(imported.font!!.preserve)
        assertArrayEquals(font, imported.font.source)
        val ten = FontPackBuilder.build(assets(), FontPackBuilder.Inputs("FontNew", "字体包", "字体投递", null, imported.font.source), preview())
        assertArrayEquals(font, PackBinImport.read(ten.bytes).font!!.source)
        File(output, "font-pack.bin").writeBytes(pack.bytes)
    }

    private fun rewrite(bytes: ByteArray, transform: (String, ByteArray) -> ByteArray): ByteArray = ByteArrayOutputStream().apply {
        ZipOutputStream(this).use { out -> ZipInputStream(bytes.inputStream()).use { input ->
            while (true) { val entry = input.nextEntry ?: break
                val data = input.readBytes(); out.putNextEntry(ZipEntry(entry.name)); out.write(transform(entry.name, data)); out.closeEntry()
            }
        } }
    }.toByteArray()

    @Test fun projectPreservesBothDevicesAndRejectsTampering() {
        val original = ChaosProject(DeviceTarget.NINE_PRO,
            IconProject(info, mapOf("weather" to tenImage(), "unknown_icon" to tenImage())),
            FontProject(PackInfo("FontNew", "字体", "字体投递"), "font.ttf", validFont(), preserve = true))
        val bytes = ProjectCodec.write(original); val opened = ProjectCodec.read(bytes)
        assertEquals(original.device, opened.device); assertEquals(original.icons!!.images.keys, opened.icons!!.images.keys)
        original.icons.images.forEach { (key, data) -> assertArrayEquals(data, opened.icons.images[key]) }
        assertArrayEquals(original.font!!.source, opened.font!!.source)
        assertTrue(opened.font.preserve)
        val corrupt = rewrite(bytes) { name, data -> if (name == "images/weather.bin") data.copyOf().also { it[30] = (it[30].toInt() xor 1).toByte() } else data }
        assertTrue(runCatching { ProjectCodec.read(corrupt) }.isFailure)
        val newer = rewrite(bytes) { name, data -> if (name == "project.json") data.toString(Charsets.UTF_8).replace("\"version\":1", "\"version\":99").toByteArray() else data }
        assertTrue(runCatching { ProjectCodec.read(newer) }.isFailure)
        File(output, "both-devices.chaosproj").writeBytes(bytes)
    }

    @Test fun importReadsLiteralsWithoutRunningLua() {
        val bad = "local M={kind=os.execute(\"bad\")}"
        val packed = NineShellBuilder.build(listOf(NineShellBuilder.Entry("_lua/_Lua/main.lua", bad.toByteArray())), "434812341234", "bad", preview())
        assertTrue(runCatching { PackBinImport.read(packed) }.isFailure)
        val benign = "local PACK_NAME = \"Safe\"\nlocal PACK_TITLE = \"标题\\\"\"\nos.execute(\"bad\")"
        val entries = listOf(ShellBuilder.Entry("_lua/iconpack/main.lua", benign.toByteArray()),
            ShellBuilder.Entry("_lua/iconpack/pack.bin", Cipk.build(listOf(Cipk.Icon("weather", tenImage())))))
        val imported = PackBinImport.read(ShellBuilder.build(entries, "434812341234", "test", preview()))
        assertEquals("标题\"", imported.icons!!.info.title)
        assertEquals("Safe", imported.icons.info.short)
    }
}
