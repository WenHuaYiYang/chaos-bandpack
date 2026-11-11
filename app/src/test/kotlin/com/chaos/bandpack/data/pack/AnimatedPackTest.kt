package com.chaos.bandpack.data.pack

import com.chaos.bandpack.data.DeviceTarget
import com.chaos.bandpack.data.icon.*
import com.chaos.bandpack.data.project.*
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.*

class AnimatedPackTest {
    private fun resource(name: String) = javaClass.getResourceAsStream("/gif/$name")!!.use { it.readBytes() }
    private val assets = PackAssets(byteArrayOf(), byteArrayOf(), "", "local PACK_NAME = \"__PACK_NAME__\"\nlocal PACK_TITLE = \"__PACK_TITLE__\"\n")
    private fun inputs(short: String = "Demo") = IconPackBuilder.Inputs(short, "Icons Demo", "Icons Demo", "123456789012", listOf(
        Cipk.Icon("activities", resource("cover96.bin")), Cipk.Icon("alarm", resource("legacy112.bin")),
        Cipk.Icon("activities_anim", resource("valid.dgf")),
    ))

    @Test fun p67ContainerAndCipkMatchIndependentPythonGoldenBytes() {
        val result = IconPackBuilder.build(assets, inputs(), resource("reference-preview.block"))
        assertArrayEquals(resource("animated-pack.bin"), result.bytes)
        val parsed = ShellBuilder.parse(result.bytes)
        assertEquals(listOf("_lua/xiaomi-band-10-pro/main.lua", "_lua/xiaomi-band-10-pro/pack.bin"), parsed.files.map { it.first })
        assertArrayEquals(resource("animated-pack.cipk"), parsed.files[1].second)
        assertEquals(4, result.iconCount)
        val project = PackBinImport.read(result.bytes)
        assertEquals(setOf("activities", "alarm", "activities_anim"), project.icons!!.images.keys)
        assertArrayEquals(resource("legacy112.bin"), project.icons.images["alarm"])
        assertArrayEquals(resource("valid.dgf"), project.icons.images["activities_anim"])
    }

    @Test fun projectRoundtripAndNineProExportKeepAnimationInTheProject() {
        val images = mapOf("weather" to resource("cover96.bin"), "weather_anim" to resource("valid.dgf"), "perpetual_calendar" to resource("legacy112.bin"))
        val project = ChaosProject(DeviceTarget.TEN_PRO, IconProject(PackInfo("Demo", "Demo", "Demo"), images))
        val opened = ProjectCodec.read(ProjectCodec.write(project))
        images.forEach { (key, bytes) -> assertArrayEquals(bytes, opened.icons!!.images[key]) }
        val nine = PortableIcons.forTarget(opened.icons!!.images, DeviceTarget.NINE_PRO)
        assertEquals(1, nine.selected)
        assertEquals(setOf("weather_anim", "perpetual_calendar"), nine.omitted.toSet())
        assertEquals(listOf("weather.bin"), nine.icons.map { it.fileName })
        assertEquals(100, LvglIconCodec.decode(nine.icons.single().data).width)
        assertArrayEquals(resource("valid.dgf"), opened.icons.images["weather_anim"])
        val ten = PortableIcons.forTarget(opened.icons.images, DeviceTarget.TEN_PRO)
        assertEquals(setOf("weather.bin", "weather_anim.bin", "perpetual_calendar.bin", "animations.bin"), ten.icons.map { it.fileName }.toSet())
        assertEquals(setOf("weather"), AnimatedIcons.readIndex(ten.icons.single { it.stem == "animations" }.data))
        assertArrayEquals(resource("legacy112.bin"), ten.icons.single { it.stem == "perpetual_calendar" }.data)
    }

    @Test fun legacyProjectVersionOneStillOpens() {
        val original = ProjectCodec.write(ChaosProject(DeviceTarget.TEN_PRO, IconProject(PackInfo("Demo", "Demo", "Demo"), mapOf("alarm" to resource("legacy112.bin")))))
        val old = ByteArrayOutputStream().apply {
            ZipOutputStream(this).use { out -> ZipInputStream(original.inputStream()).use { input ->
                while (true) {
                    val entry = input.nextEntry ?: break
                    val data = input.readBytes().let { if (entry.name == "project.json") it.toString(Charsets.UTF_8).replace("\"version\":2", "\"version\":1").toByteArray() else it }
                    out.putNextEntry(ZipEntry(entry.name)); out.write(data); out.closeEntry()
                }
            } }
        }.toByteArray()
        assertArrayEquals(resource("legacy112.bin"), ProjectCodec.read(old).icons!!.images["alarm"])
    }

    @Test fun staticOnlyPacksCarryAnEmptyAnimationIndex() {
        val result = IconPackBuilder.build(assets, IconPackBuilder.Inputs("Static", "Static", "Static", null,
            listOf(Cipk.Icon("alarm", resource("legacy112.bin")))), resource("reference-preview.block"))
        val files = Cipk.parse(ShellBuilder.parse(result.bytes).files[1].second)
        assertEquals(2, files.size)
        assertTrue(AnimatedIcons.readIndex(files.single { it.first == "animations.bin" }.second).isEmpty())
    }

    @Test fun invalidAnimationPairsIndexAndNamesCannotBeExported() {
        assertTrue(runCatching { AnimatedIcons.validateProject(mapOf("weather_anim" to resource("valid.dgf"))) }.isFailure)
        assertTrue(runCatching { AnimatedIcons.validateProject(mapOf("weather" to resource("legacy112.bin"), "weather_anim" to resource("valid.dgf"))) }.isFailure)
        assertTrue(runCatching { AnimatedIcons.validateFiles(listOf(Cipk.Icon("alarm", resource("cover96.bin")), Cipk.Icon("animations", AnimatedIcons.index(setOf("weather"))))) }.isFailure)
        assertTrue(runCatching { AnimatedIcons.validateFiles(listOf(Cipk.Icon("unknown_stem", resource("cover96.bin")))) }.isFailure)
        assertTrue(runCatching { AnimatedIcons.validateFiles(listOf(Cipk.Icon("alarm", LvglIconCodec.bgra8(IntArray(100 * 100), 100, 100)))) }.isFailure)
        for (short in listOf("a.b", "a b", "a\"b", "中文", "too-long-name-123")) {
            assertTrue(short, runCatching { IconPackBuilder.build(assets, inputs(short), resource("reference-preview.block")) }.isFailure)
        }
        assertEquals("\\0011", luaQuote("\u00011"))
    }

    @Test fun longNativeResourceNamesAndClearingAnAnimatedSlotSurviveProjectEditing() {
        val stem = "card_jiangsu_transit_card_jiangsulianyungang"
        assertEquals(44, stem.length)
        val images = mapOf(stem to resource("cover96.bin"), "weather" to resource("cover96.bin"), "weather_anim" to resource("valid.dgf"))
        val saved = ProjectCodec.write(ChaosProject(DeviceTarget.TEN_PRO, IconProject(PackInfo("Demo", "Demo", "Demo"), images)))
        val opened = ProjectCodec.read(saved).icons!!.images
        assertArrayEquals(images.getValue(stem), opened[stem])
        val cleared = AnimatedIcons.withoutSlot(opened, "weather")
        assertEquals(setOf(stem), cleared.keys)
        val exported = PortableIcons.forTarget(cleared, DeviceTarget.TEN_PRO)
        assertArrayEquals(images.getValue(stem), exported.icons.single { it.stem == stem }.data)
        assertTrue(AnimatedIcons.readIndex(exported.icons.single { it.stem == "animations" }.data).isEmpty())
    }
}
