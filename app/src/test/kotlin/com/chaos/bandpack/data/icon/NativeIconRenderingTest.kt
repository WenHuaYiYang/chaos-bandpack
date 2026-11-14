package com.chaos.bandpack.data.icon

import com.chaos.bandpack.data.DeviceTarget
import org.junit.Assert.*
import org.junit.Test

class NativeIconRenderingTest {
    @Test fun newDesktopImagesAre96AndRetainPartialAndFullTransparency() {
        val px = IntArray(96 * 96) { if (it % 96 < 48) 0x80402010.toInt() else 0 }
        val bin = IconConvert.convert(px, 96, 96).first
        val image = LvglIconCodec.decode(bin)
        assertEquals(96, image.width); assertEquals(96, image.height)
        assertArrayEquals(px, image.pixels)
        assertTrue(LvglIconCodec.decode(IconConvert.convert(IntArray(96 * 96), 96, 96).first).pixels.all { it == 0 })
    }

    @Test fun rectangularSourcesFitWithoutCroppingOrAddingABackground() {
        val image = LvglIconCodec.decode(IconConvert.convert(IntArray(32 * 16) { 0xff20a040.toInt() }, 32, 16).first)
        assertEquals(0, image.pixels[0])
        assertEquals(0xff20a040.toInt(), image.pixels[48 * 96 + 48])
        assertEquals(0xff20a040.toInt(), image.pixels[48 * 96])
        assertEquals(0, image.pixels[48])
    }

    @Test fun systemUiAndNineProKeepTheirExistingSizes() {
        val system = IconSpec.stemOf("ctrl_setting")!!
        assertEquals(64, LvglIconCodec.decode(IconConvert.convert(IntArray(32 * 32) { -1 }, 32, 32, system).first).width)
        val nine = IconSpec.stemOf("weather", DeviceTarget.NINE_PRO)!!
        assertEquals(100, LvglIconCodec.decode(IconConvert.convert(IntArray(32 * 32) { -1 }, 32, 32, nine).first).width)
    }
}
