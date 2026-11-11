package com.chaos.bandpack.data.icon

import java.io.ByteArrayOutputStream
import java.security.MessageDigest

/** The p67 DGF1 ABI. Parsing checks every frame, including its decompressed size. */
object Dgf1 {
    const val SIDE = 96
    const val PIXELS = SIDE * SIDE
    const val HEADER_BYTES = 60
    const val TABLE_OFFSET = HEADER_BYTES + 1024
    const val MAX_FRAMES = 256
    const val MAX_BYTES = 1024 * 1024
    const val MAX_ENCODED_FRAME = 18432

    data class Frame(val pixels: IntArray, val delayMs: Int)
    data class Record(val delayMs: Int, val offset: Int, val length: Int)
    class Animation internal constructor(
        val bytes: ByteArray, val frames: List<Record>, val durationMs: Int, val plays: Long,
        val sourceHash: ByteArray, private val palette: IntArray,
    ) {
        fun pixels(frame: Int): IntArray = unpack(bytes, frames[frame].offset, frames[frame].length).let { indices ->
            IntArray(PIXELS) { palette[indices[it].toInt() and 255] }
        }
    }

    fun isAnimation(bytes: ByteArray): Boolean = bytes.size >= 4 &&
        bytes[0] == 68.toByte() && bytes[1] == 71.toByte() && bytes[2] == 70.toByte() && bytes[3] == 49.toByte()

    fun parse(bytes: ByteArray): Animation {
        require(bytes.size in (TABLE_OFFSET + 12 + 1)..MAX_BYTES && isAnimation(bytes)) { "不是有效的 DGF1 动画，或动画超过 1 MiB" }
        require(u16(bytes, 4) == SIDE && u16(bytes, 6) == SIDE) { "DGF1 动画必须为 96 × 96" }
        val count = u16(bytes, 8)
        require(count in 1..MAX_FRAMES && u16(bytes, 10) == 0) { "DGF1 帧数或保留字段不合法" }
        val dataOffset = TABLE_OFFSET + count * 12
        require(u32(bytes, 20) == TABLE_OFFSET.toLong() && u32(bytes, 24) == dataOffset.toLong() && dataOffset < bytes.size) { "DGF1 帧表或负载偏移不合法" }
        var next = dataOffset
        var duration = 0
        val records = (0 until count).map { i ->
            val at = TABLE_OFFSET + i * 12
            val delay = u32(bytes, at)
            val offset = u32(bytes, at + 4)
            val length = u32(bytes, at + 8)
            require(delay in 1..60000 && offset == next.toLong() && length in 1..MAX_ENCODED_FRAME.toLong() && length <= bytes.size - next) { "DGF1 第 ${i + 1} 帧的时长、偏移或长度不合法" }
            unpack(bytes, next, length.toInt())
            val record = Record(delay.toInt(), next, length.toInt())
            next += length.toInt(); duration += delay.toInt()
            record
        }
        require(next == bytes.size && u32(bytes, 12) == duration.toLong()) { "DGF1 总时长或文件尾部不合法" }
        val palette = IntArray(256) { i ->
            val p = HEADER_BYTES + i * 4
            ((bytes[p + 3].toInt() and 255) shl 24) or ((bytes[p + 2].toInt() and 255) shl 16) or
                ((bytes[p + 1].toInt() and 255) shl 8) or (bytes[p].toInt() and 255)
        }
        return Animation(bytes, records, duration, u32(bytes, 16), bytes.copyOfRange(28, 60), palette)
    }

    fun encode(frames: List<Frame>, plays: Long, source: ByteArray): ByteArray {
        require(frames.size in 1..MAX_FRAMES) { "GIF 必须有 1–256 帧；不会自动抽帧" }
        require(plays in 0..0xffffffffL)
        frames.forEachIndexed { i, f ->
            require(f.pixels.size == PIXELS && f.delayMs in 1..60000) { "第 ${i + 1} 帧必须为 96 × 96，时长须为 1–60000 ms" }
        }
        val indexed = quantize(frames)
        val compressed = indexed.frames.map { pack(it).also { data -> require(data.size <= MAX_ENCODED_FRAME) } }
        val dataAt = TABLE_OFFSET + frames.size * 12
        val size = dataAt + compressed.sumOf { it.size }
        require(size <= MAX_BYTES) { "GIF 转换后超过 1 MiB；请减少帧数或画面复杂度，不会自动抽帧或降低分辨率" }
        val out = ByteArray(size)
        "DGF1".toByteArray(Charsets.US_ASCII).copyInto(out)
        w16(out, 4, SIDE); w16(out, 6, SIDE); w16(out, 8, frames.size)
        w32(out, 12, frames.sumOf { it.delayMs }.toLong()); w32(out, 16, plays)
        w32(out, 20, TABLE_OFFSET.toLong()); w32(out, 24, dataAt.toLong())
        MessageDigest.getInstance("SHA-256").digest(source).copyInto(out, 28)
        indexed.palette.forEachIndexed { i, c ->
            val p = HEADER_BYTES + i * 4
            out[p] = c.toByte(); out[p + 1] = (c ushr 8).toByte(); out[p + 2] = (c ushr 16).toByte(); out[p + 3] = (c ushr 24).toByte()
        }
        var next = dataAt
        frames.forEachIndexed { i, f ->
            val p = TABLE_OFFSET + i * 12
            w32(out, p, f.delayMs.toLong()); w32(out, p + 4, next.toLong()); w32(out, p + 8, compressed[i].size.toLong())
            compressed[i].copyInto(out, next); next += compressed[i].size
        }
        parse(out)
        return out
    }

    internal fun unpack(bytes: ByteArray, offset: Int, length: Int): ByteArray {
        require(offset >= 0 && length >= 1 && offset <= bytes.size - length) { "动画压缩数据越界" }
        val out = ByteArray(PIXELS)
        var p = offset; val end = offset + length; var n = 0
        while (p < end) {
            val tag = bytes[p++].toInt() and 255
            val count = (tag and 127) + 1
            require(count <= PIXELS - n) { "动画帧解压后超过 9216 字节" }
            if (tag and 128 != 0) {
                require(p < end) { "动画重复段被截断" }
                out.fill(bytes[p++], n, n + count)
            } else {
                require(count <= end - p) { "动画字面段被截断" }
                bytes.copyInto(out, n, p, p + count); p += count
            }
            n += count
        }
        require(n == PIXELS) { "动画帧解压后必须恰好为 9216 字节" }
        return out
    }

    internal fun pack(bytes: ByteArray): ByteArray {
        val out = ByteArrayOutputStream(bytes.size + bytes.size / 128 + 1)
        var p = 0
        fun run(at: Int): Int { var end = at + 1; while (end < bytes.size && end - at < 128 && bytes[end] == bytes[at]) end++; return end - at }
        while (p < bytes.size) {
            val repeat = run(p)
            if (repeat >= 3) { out.write(128 or (repeat - 1)); out.write(bytes[p].toInt()); p += repeat }
            else {
                val start = p; p += repeat
                while (p < bytes.size && p - start < 128 && run(p) < 3) p += minOf(run(p), 128 - (p - start))
                out.write(p - start - 1); out.write(bytes, start, p - start)
            }
        }
        return out.toByteArray()
    }

    private data class Indexed(val palette: IntArray, val frames: List<ByteArray>)
    private data class ColorCount(val color: Int, val count: Int)
    private fun color(c: Int) = if (c ushr 24 == 0) 0 else c
    private fun bucket(c: Int) = ((c ushr 28) shl 12) or (((c ushr 20) and 15) shl 8) or (((c ushr 12) and 15) shl 4) or ((c ushr 4) and 15)
    private fun channel(c: Int, k: Int) = (c ushr (k * 8)) and 255

    /** One palette for the whole animation; exact colors when there are at most 256. */
    private fun quantize(frames: List<Frame>): Indexed {
        val unique = linkedSetOf<Int>()
        outer@ for (frame in frames) for (pixel in frame.pixels) {
            unique.add(color(pixel)); if (unique.size > 256) break@outer
        }
        if (unique.size <= 256) {
            val colors = unique.toIntArray()
            val lookup = colors.withIndex().associate { it.value to it.index.toByte() }
            return Indexed(colors, frames.map { f -> ByteArray(PIXELS) { lookup.getValue(color(f.pixels[it])) } })
        }
        val counts = IntArray(65536)
        val sums = Array(4) { IntArray(65536) }
        var transparent = false
        for (f in frames) for (raw in f.pixels) {
            val c = color(raw)
            if (c == 0) { transparent = true; continue }
            val key = bucket(c); counts[key]++
            for (k in 0..3) sums[k][key] += channel(c, k)
        }
        val histogram = (counts.indices).filter { counts[it] > 0 }.map { key ->
            var c = 0; for (k in 0..3) c = c or ((sums[k][key] / counts[key]) shl (k * 8))
            ColorCount(c, counts[key])
        }
        val boxes = mutableListOf(histogram)
        val target = if (transparent) 255 else 256
        fun range(box: List<ColorCount>, k: Int) = box.maxOf { channel(it.color, k) } - box.minOf { channel(it.color, k) }
        while (boxes.size < target) {
            val at = boxes.indices.filter { boxes[it].size > 1 }.maxByOrNull { i ->
                val box = boxes[i]; (0..3).maxOf { range(box, it) * if (it == 3) 2 else 1 }.toLong() * box.sumOf { it.count }
            } ?: break
            val box = boxes.removeAt(at)
            val axis = (0..3).maxBy { range(box, it) * if (it == 3) 2 else 1 }
            val sorted = box.sortedWith(compareBy<ColorCount> { channel(it.color, axis) }.thenBy { it.color })
            val half = sorted.sumOf { it.count } / 2
            var total = 0; var cut = 0
            while (cut < sorted.size - 1 && (cut == 0 || total < half)) total += sorted[cut++].count
            boxes.add(sorted.subList(0, cut)); boxes.add(sorted.subList(cut, sorted.size))
        }
        val palette = (if (transparent) listOf(0) else emptyList()) + boxes.map { box ->
            val n = box.sumOf { it.count }.toLong(); var c = 0
            for (k in 0..3) c = c or ((box.sumOf { channel(it.color, k).toLong() * it.count } / n).toInt() shl (k * 8))
            c
        }
        val lookup = IntArray(65536) { -1 }
        if (transparent) lookup[0] = 0
        fun index(c: Int): Byte {
            val key = bucket(c)
            if (lookup[key] < 0) {
                var representative = 0
                for (k in 0..3) representative = representative or ((sums[k][key] / counts[key]) shl (k * 8))
                lookup[key] = palette.indices.minBy { i -> (0..3).sumOf { k ->
                    val d = channel(representative, k) - channel(palette[i], k); d * d * if (k == 3) 4 else 1
                } }
            }
            return lookup[key].toByte()
        }
        return Indexed(palette.toIntArray(), frames.map { f -> ByteArray(PIXELS) { index(color(f.pixels[it])) } })
    }

    internal fun u16(b: ByteArray, p: Int): Int = (b[p].toInt() and 255) or ((b[p + 1].toInt() and 255) shl 8)
    internal fun u32(b: ByteArray, p: Int): Long = (0..3).fold(0L) { n, i -> n or ((b[p + i].toLong() and 255) shl (i * 8)) }
    internal fun w16(b: ByteArray, p: Int, n: Int) { b[p] = n.toByte(); b[p + 1] = (n ushr 8).toByte() }
    internal fun w32(b: ByteArray, p: Int, n: Long) { for (i in 0..3) b[p + i] = (n ushr (i * 8)).toByte() }
}
