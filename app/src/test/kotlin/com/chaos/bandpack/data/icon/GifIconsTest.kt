package com.chaos.bandpack.data.icon

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.security.MessageDigest

class GifIconsTest {
    private fun resource(name: String) = javaClass.getResourceAsStream("/gif/$name")!!.use { it.readBytes() }

    @Test fun gifCompositingTimingAndLoopsMatchPillow() {
        val references = Json.parseToJsonElement(resource("reference.json").toString(Charsets.UTF_8)).jsonObject
        for ((name, value) in references) {
            val original = resource("$name.gif")
            val made = GifIcons.convert(original)
            val parsed = Dgf1.parse(made.animation)
            val ref = value.jsonObject
            assertEquals(name, ref["plays"]!!.jsonPrimitive.long, parsed.plays)
            assertEquals(name, ref["delays"]!!.jsonArray.map { it.jsonPrimitive.int }, parsed.frames.map { it.delayMs })
            assertArrayEquals(MessageDigest.getInstance("SHA-256").digest(original), parsed.sourceHash)
            val pixels = resource("$name.rgba")
            for (frame in parsed.frames.indices) {
                val expected = IntArray(9216) { i ->
                    val p = (frame * 9216 + i) * 4
                    if (pixels[p + 3] == 0.toByte()) 0 else ((pixels[p + 3].toInt() and 255) shl 24) or ((pixels[p].toInt() and 255) shl 16) or
                        ((pixels[p + 1].toInt() and 255) shl 8) or (pixels[p + 2].toInt() and 255)
                }
                assertArrayEquals("$name frame $frame", expected, parsed.pixels(frame))
                if (frame == 0) assertArrayEquals(expected, LvglIconCodec.decode(made.cover).pixels)
            }
        }
    }

    @Test fun invalidGifIsRejectedWithoutDroppingFramesOrChangingTiming() {
        assertTrue(runCatching { GifIcons.convert(resource("zero-delay.gif")) }.isFailure)
        assertTrue(runCatching { GifIcons.convert(resource("too-many.gif")) }.exceptionOrNull()?.message.orEmpty().contains("256"))
        val valid = resource("disposal.gif")
        assertTrue(runCatching { GifIcons.convert(valid.copyOf(valid.size / 2)) }.isFailure)
        assertTrue(runCatching { GifIcons.convert(valid.copyOf().also { it[6] = 0; it[7] = 0 }) }.isFailure)
    }

    @Test fun manyColorsUseOneBoundedPaletteAndKeepTransparency() {
        val frames = (0 until 3).map { f -> Dgf1.Frame(IntArray(9216) { i ->
            if (i < 96) 0 else (0xff000000.toInt() or (((i * 17 + f) and 255) shl 16) or (((i / 3) and 255) shl 8) or ((i / 7) and 255))
        }, 10 + f) }
        val out = Dgf1.encode(frames, 1, byteArrayOf(1, 2, 3))
        val parsed = Dgf1.parse(out)
        assertTrue(out.size <= Dgf1.MAX_BYTES)
        for (i in frames.indices) assertTrue(parsed.pixels(i).take(96).all { it ushr 24 == 0 })
    }

    @Test fun oversizedAnimationIsRejectedWithoutReducingFrameCountOrResolution() {
        val random = java.util.Random(67)
        val frames = (0 until 128).map { Dgf1.Frame(IntArray(9216) {
            val c = random.nextInt(256); 0xff000000.toInt() or (c shl 16) or (c shl 8) or c
        }, 20) }
        val error = runCatching { Dgf1.encode(frames, 0, byteArrayOf(1)) }.exceptionOrNull()
        assertTrue(error?.message.orEmpty().contains("1 MiB"))
        assertEquals(128, frames.size)
        assertTrue(frames.all { it.pixels.size == 9216 })
    }
}
