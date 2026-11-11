package com.chaos.bandpack.data.icon

import java.io.ByteArrayOutputStream

/** GIF87a/89a decoding on the JVM: local palettes, interlacing and disposal 0–3. */
object GifIcons {
    const val MAX_SOURCE_BYTES = 32_000_000
    private const val MAX_CANVAS_PIXELS = 4_194_304
    data class Made(val cover: ByteArray, val animation: ByteArray, val frameCount: Int, val durationMs: Int, val plays: Long)

    fun isGif(bytes: ByteArray): Boolean = bytes.size >= 6 &&
        (String(bytes, 0, 6, Charsets.US_ASCII) == "GIF87a" || String(bytes, 0, 6, Charsets.US_ASCII) == "GIF89a")

    fun convert(bytes: ByteArray): Made {
        require(bytes.size in 13..MAX_SOURCE_BYTES && isGif(bytes)) { "不是 GIF 图片，或源文件超过 32 MB" }
        val r = Reader(bytes); r.skip(6)
        val width = r.word(); val height = r.word()
        require(width in 1..4096 && height in 1..4096 && width.toLong() * height <= MAX_CANVAS_PIXELS) { "GIF 画布过大（最多 4096 边长、4194304 像素）" }
        val flags = r.byte(); val background = r.byte(); r.byte()
        val global = if (flags and 128 != 0) r.palette(1 shl ((flags and 7) + 1)) else null
        val canvas = IntArray(width * height)
        var initialized = false
        var initialTransparency = false
        var disposal = 0; var transparent = -1; var delay = 100
        var previousDisposal = 0; var previousLeft = 0; var previousTop = 0; var previousWidth = 0; var previousHeight = 0
        var previousClear = 0; var restore: IntArray? = null
        var plays = 1L
        var ended = false
        val frames = ArrayList<Dgf1.Frame>()
        while (r.remaining > 0 && !ended) {
            when (val tag = r.byte()) {
                0x3b -> ended = true
                0x21 -> when (r.byte()) {
                    0xf9 -> {
                        require(r.byte() == 4) { "GIF 控制块长度不合法" }
                        val control = r.byte(); val specifiedDisposal = (control ushr 2) and 7
                        require(specifiedDisposal in 0..3) { "GIF disposal 模式不支持：$specifiedDisposal" }
                        // Unspecified disposal inherits the last specified value, matching Pillow.
                        if (specifiedDisposal != 0) disposal = specifiedDisposal
                        delay = r.word() * 10
                        val index = r.byte(); transparent = if (control and 1 != 0) index else -1
                        require(r.byte() == 0) { "GIF 控制块未结束" }
                    }
                    0xff -> {
                        val application = String(r.take(r.byte()), Charsets.US_ASCII)
                        val data = r.blocks()
                        if (application in listOf("NETSCAPE2.0", "ANIMEXTS1.0")) {
                            require(data.size >= 3 && data[0] == 1.toByte()) { "GIF 循环扩展不合法" }
                            val repeats = Dgf1.u16(data, 1)
                            plays = if (repeats == 0) 0 else repeats.toLong() + 1
                        }
                    }
                    0x01 -> error("GIF 包含文本绘制扩展，请先转换为普通图片帧")
                    else -> r.blocks()
                }
                0x2c -> {
                    require(frames.size < Dgf1.MAX_FRAMES) { "GIF 超过 256 帧；不会自动抽帧" }
                    require(delay in 1..60000) { "GIF 第 ${frames.size + 1} 帧的时长须为 1–60000 ms（当前 $delay ms）" }
                    val left = r.word(); val top = r.word(); val w = r.word(); val h = r.word(); val packed = r.byte()
                    require(w > 0 && h > 0 && left <= width - w && top <= height - h) { "GIF 帧越出逻辑画布" }
                    val palette = if (packed and 128 != 0) r.palette(1 shl ((packed and 7) + 1)) else requireNotNull(global) { "GIF 缺少调色板" }
                    require(transparent < palette.size) { "GIF 透明色索引越界" }
                    val firstFrame = !initialized
                    if (!initialized) {
                        initialTransparency = transparent >= 0
                        // A partial first image starts with palette index zero outside its extent.
                        canvas.fill(if (initialTransparency) 0 else palette[0])
                        initialized = true
                    } else when (previousDisposal) {
                        2 -> for (y in previousTop until previousTop + previousHeight) canvas.fill(previousClear, y * width + previousLeft, y * width + previousLeft + previousWidth)
                        3 -> requireNotNull(restore).copyInto(canvas)
                    }
                    restore = if (disposal == 3) canvas.copyOf() else null
                    val indices = lzw(r.blocksAfterCodeSize(), w * h)
                    val rows = if (packed and 64 == 0) (0 until h).toList() else buildList {
                        for ((start, step) in listOf(0 to 8, 4 to 8, 2 to 4, 1 to 2)) for (y in start until h step step) add(y)
                    }
                    var p = 0
                    for (row in rows) for (x in 0 until w) {
                        val index = indices[p++].toInt() and 255
                        require(index < palette.size) { "GIF 像素调色板索引越界" }
                        if (index != transparent) canvas[(top + row) * width + left + x] = palette[index]
                        else if (firstFrame) canvas[(top + row) * width + left + x] = 0
                    }
                    frames.add(Dgf1.Frame(IconConvert.fitCanvas(canvas, width, height, Dgf1.SIDE), delay))
                    previousDisposal = disposal; previousLeft = left; previousTop = top; previousWidth = w; previousHeight = h
                    previousClear = if (initialTransparency || transparent >= 0) 0 else global?.getOrNull(background) ?: 0
                    transparent = -1; delay = 100
                }
                else -> error("GIF 数据块不合法：0x${tag.toString(16)}")
            }
        }
        require(ended && frames.isNotEmpty()) { "GIF 被截断或没有图片帧" }
        val animation = Dgf1.encode(frames, plays, bytes)
        return Made(LvglIconCodec.bgra(frames.first().pixels, Dgf1.SIDE, Dgf1.SIDE), animation, frames.size, frames.sumOf { it.delayMs }, plays)
    }

    private data class Compressed(val minBits: Int, val bytes: ByteArray)
    private class Reader(private val bytes: ByteArray) {
        private var p = 0
        val remaining: Int get() = bytes.size - p
        fun byte(): Int { require(p < bytes.size) { "GIF 数据被截断" }; return bytes[p++].toInt() and 255 }
        fun word(): Int = byte() or (byte() shl 8)
        fun skip(n: Int) { require(n in 0..remaining) { "GIF 数据被截断" }; p += n }
        fun take(n: Int): ByteArray { require(n in 0..remaining) { "GIF 数据被截断" }; return bytes.copyOfRange(p, p + n).also { p += n } }
        fun palette(n: Int): IntArray = IntArray(n) { val red = byte(); val green = byte(); val blue = byte(); 0xff000000.toInt() or (red shl 16) or (green shl 8) or blue }
        fun blocks(): ByteArray {
            val out = ByteArrayOutputStream()
            while (true) { val n = byte(); if (n == 0) break; out.write(take(n)) }
            return out.toByteArray()
        }
        fun blocksAfterCodeSize(): Compressed { val size = byte(); return Compressed(size, blocks()) }
    }

    private fun lzw(data: Compressed, expected: Int): ByteArray {
        require(data.minBits in 2..8) { "GIF LZW 初始码宽不合法" }
        val clear = 1 shl data.minBits; val stop = clear + 1
        val prefix = IntArray(4096); val suffix = ByteArray(4096); val stack = ByteArray(4097)
        for (i in 0 until clear) suffix[i] = i.toByte()
        val out = ByteArray(expected)
        var bit = 0; var bits = data.minBits + 1; var available = stop + 1
        var old = -1; var first = 0; var written = 0; var ended = false
        fun code(): Int {
            require(bit.toLong() + bits <= data.bytes.size.toLong() * 8) { "GIF LZW 数据被截断" }
            var value = 0
            for (i in 0 until bits) value = value or (((data.bytes[(bit + i) ushr 3].toInt() ushr ((bit + i) and 7)) and 1) shl i)
            bit += bits; return value
        }
        while (!ended) {
            var current = code()
            when (current) {
                clear -> { bits = data.minBits + 1; available = stop + 1; old = -1; continue }
                stop -> { ended = true; continue }
            }
            require(current <= available && current < 4096) { "GIF LZW 码字不合法" }
            if (old < 0) {
                require(current < clear && written < expected) { "GIF LZW 首码或像素数不合法" }
                out[written++] = current.toByte(); first = current; old = current; continue
            }
            val input = current; var top = 0
            if (current == available) { stack[top++] = first.toByte(); current = old }
            while (current >= clear) {
                require(current > stop && current < available && top < 4096) { "GIF LZW 字典损坏" }
                stack[top++] = suffix[current]; current = prefix[current]
            }
            first = current; stack[top++] = first.toByte()
            require(top <= expected - written) { "GIF LZW 像素数超过帧尺寸" }
            while (top > 0) out[written++] = stack[--top]
            if (available < 4096) {
                prefix[available] = old; suffix[available] = first.toByte(); available++
                if (available == 1 shl bits && bits < 12) bits++
            }
            old = input
        }
        require(written == expected) { "GIF LZW 解码后的像素数不符" }
        return out
    }
}
