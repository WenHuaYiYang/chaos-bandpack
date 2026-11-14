package com.chaos.bandpack.data.icon

import com.chaos.bandpack.data.pack.Cipk
import org.junit.Assert.*
import org.junit.Test

class Dgf1Test {
    private fun fixture() = javaClass.getResourceAsStream("/gif/valid.dgf")!!.use { it.readBytes() }

    @Test fun independentAbiFixtureHasExactTimingOffsetsAndPixels() {
        val raw = fixture(); val animation = Dgf1.parse(raw)
        assertEquals(60001, animation.durationMs)
        assertEquals(0xffffffffL, animation.plays)
        assertEquals(listOf(1, 60000), animation.frames.map { it.delayMs })
        assertEquals(1108, animation.frames.first().offset)
        assertArrayEquals(ByteArray(32) { it.toByte() }, animation.sourceHash)
        assertTrue(animation.pixels(0).all { it == 0xff01fe54.toInt() })
        assertEquals(0xff02fd57.toInt(), animation.pixels(1)[0])
        assertEquals(0xff03fc56.toInt(), animation.pixels(1)[1])
    }

    @Test fun malformedAbiCannotPassValidation() {
        fun bad(change: (ByteArray) -> Unit) { assertTrue(runCatching { Dgf1.parse(fixture().also(change)) }.isFailure) }
        bad { Dgf1.w16(it, 4, 95) }; bad { Dgf1.w16(it, 8, 0) }; bad { Dgf1.w16(it, 8, 257) }
        bad { Dgf1.w16(it, 10, 1) }; bad { Dgf1.w32(it, 12, 1) }
        bad { Dgf1.w32(it, 20, 1083) }; bad { Dgf1.w32(it, 24, 1109) }
        bad { Dgf1.w32(it, 1084, 0) }; bad { Dgf1.w32(it, 1084, 60001) }
        bad { Dgf1.w32(it, 1088, 1109) }; bad { Dgf1.w32(it, 1092, 18433) }
        assertTrue(runCatching { Dgf1.parse(fixture() + 0.toByte()) }.isFailure)
        assertTrue(runCatching { Dgf1.parse(fixture().copyOf(1100)) }.isFailure)
        assertTrue(runCatching { Dgf1.unpack(byteArrayOf(0xff.toByte()), 0, 1) }.isFailure)
        assertTrue(runCatching { Dgf1.unpack(byteArrayOf(0, 1), 0, 2) }.isFailure)
    }

    @Test fun cia1BitOrderAndReservedBitsAreFixed() {
        val expected = byteArrayOf(67, 73, 65, 49, 96, 0, 96, 0, 38, 0, 0, 0, 1, 0, 128.toByte(), 0, 0, 0, 0, 0)
        val raw = AnimatedIcons.index(setOf("activities", "settings"))
        assertArrayEquals(expected, raw)
        assertEquals(setOf("activities", "settings"), AnimatedIcons.readIndex(raw))
        assertTrue(AnimatedIcons.readIndex(AnimatedIcons.index(emptySet())).isEmpty())
        assertTrue(runCatching { AnimatedIcons.readIndex(raw.copyOf().also { it[19] = 0x80.toByte() }) }.isFailure)
        assertTrue(runCatching { AnimatedIcons.readIndex(raw.copyOf().also { it[10] = 1 }) }.isFailure)
    }

    @Test fun cipkLimitsApplyToTheEncodedContainerAndEachFileType() {
        val files = (0 until 256).map { Cipk.Icon("item_$it", byteArrayOf(1)) }
        assertEquals(256, Cipk.parse(Cipk.build(files)).size)
        assertTrue(runCatching { Cipk.build(files + Cipk.Icon("overflow", byteArrayOf(1))) }.isFailure)
        assertTrue(runCatching { Cipk.build(listOf(Cipk.Icon("alarm", ByteArray(512 * 1024 + 1)))) }.isFailure)
        val megabyte = ByteArray(1024 * 1024)
        assertTrue(runCatching { Cipk.build((0 until 16).map { Cipk.Icon("item_${it}_anim", megabyte) }) }.isFailure)
        val one = Cipk.build(listOf(Cipk.Icon("activities_anim", megabyte)))
        assertEquals(megabyte.size, Cipk.parse(one).single().second.size)
        assertTrue(runCatching { Cipk.parse(one + 0.toByte()) }.isFailure)
        assertTrue(runCatching { Cipk.build(listOf(Cipk.Icon("../alarm", byteArrayOf(1)))) }.isFailure)
        assertTrue(runCatching { Cipk.build(listOf(Cipk.Icon("alarm", byteArrayOf(1)), Cipk.Icon("alarm", byteArrayOf(2)))) }.isFailure)
    }
}
