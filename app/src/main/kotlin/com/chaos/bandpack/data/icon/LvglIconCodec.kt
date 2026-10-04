package com.chaos.bandpack.data.icon

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** LVGL 图像文件与保留透明度的 I8/RLE 编码。 */
object LvglIconCodec {
    data class Image(val width: Int, val height: Int, val pixels: IntArray)
    fun header(w: Int, h: Int, cf: Int, flags: Int, stride: Int): ByteArray =
        ByteBuffer.allocate(12).order(ByteOrder.LITTLE_ENDIAN)
            .put(0x19.toByte()).put(cf.toByte()).putShort(flags.toShort())
            .putShort(w.toShort()).putShort(h.toShort()).putShort(stride.toShort()).putShort(0).array()

    fun bgra(pixels: IntArray, w: Int, h: Int): ByteArray {
        require(pixels.size == w * h)
        val out = ByteBuffer.allocate(12 + pixels.size * 4).order(ByteOrder.LITTLE_ENDIAN)
        out.put(header(w, h, 16, 0, w * 4))
        pixels.forEach { out.putInt(it) }
        return out.array()
    }

    private data class ColorCount(val color: Int, val count: Int)
    private fun channel(color: Int, ch: Int) = (color ushr (ch * 8)) and 255
    private class Box(val colors: List<ColorCount>) {
        val ranges = IntArray(4) { ch -> colors.maxOf { channel(it.color, ch) } - colors.minOf { channel(it.color, ch) } }
        val splitChannel = ranges.indices.maxBy { ranges[it] * if (it == 3) 2 else 1 }
        val score = if (colors.size > 1) ranges[splitChannel] * colors.sumOf { it.count }.toLong() else -1L
        fun split(): Pair<Box, Box> {
            val sorted = colors.sortedWith(compareBy<ColorCount> { channel(it.color, splitChannel) }.thenBy { it.color })
            val half = sorted.sumOf { it.count } / 2
            var sum = 0; var split = 1
            for (i in 0 until sorted.lastIndex) {
                sum += sorted[i].count
                split = i + 1
                if (sum >= half) break
            }
            return Box(sorted.take(split)) to Box(sorted.drop(split))
        }
        fun mean(): Int {
            val total = colors.sumOf { it.count }.toLong()
            var result = 0
            for (ch in 0..3) {
                val value = ((colors.sumOf { channel(it.color, ch).toLong() * it.count } + total / 2) / total).toInt()
                result = result or (value shl (ch * 8))
            }
            return result
        }
    }

    fun indexedRle(pixels: IntArray, w: Int, h: Int): ByteArray {
        require(w > 0 && h > 0 && pixels.size == w * h)
        val histogram = pixels.filter { it ushr 24 != 0 }.groupingBy { it }.eachCount()
        val palette = if (histogram.size <= 255) histogram.keys.sorted().toIntArray() else {
            val boxes = mutableListOf(Box(histogram.map { ColorCount(it.key, it.value) }))
            while (boxes.size < 255) {
                val index = boxes.indices.maxBy { boxes[it].score }
                if (boxes[index].score < 0) break
                val (a, b) = boxes.removeAt(index).split()
                boxes.add(a); boxes.add(b)
            }
            boxes.map { it.mean() }.toIntArray()
        }
        val lookup = histogram.keys.associateWith { color ->
            palette.indices.minBy { i ->
                val candidate = palette[i]
                val alpha = channel(color, 3); val ca = channel(candidate, 3)
                var error = (alpha - ca) * (alpha - ca) * 2
                for (ch in 0..2) {
                    val delta = (channel(color, ch) * alpha - channel(candidate, ch) * ca) / 255
                    error += delta * delta
                }
                error
            } + 1
        }
        val raw = ByteBuffer.allocate(1024 + pixels.size).order(ByteOrder.LITTLE_ENDIAN)
        raw.putInt(0)
        repeat(255) { raw.putInt(palette.getOrElse(it) { 0 }) }
        pixels.forEach { raw.put(if (it ushr 24 == 0) 0 else lookup.getValue(it).toByte()) }
        val compressed = rle(raw.array())
        return header(w, h, 10, 8, w) + ByteBuffer.allocate(12).order(ByteOrder.LITTLE_ENDIAN)
            .putInt(1).putInt(compressed.size).putInt(raw.capacity()).array() + compressed
    }

    private fun rle(raw: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        var at = 0
        fun run(start: Int): Int {
            var n = 1
            while (n < 127 && start + n < raw.size && raw[start + n] == raw[start]) n++
            return n
        }
        while (at < raw.size) {
            val count = run(at)
            if (count >= 3) { out.write(count); out.write(raw[at].toInt()); at += count }
            else {
                val begin = at
                at += count
                while (at < raw.size && at - begin < 127 && run(at) < 3) at += minOf(run(at), 127 - (at - begin))
                out.write(0x80 or (at - begin)); out.write(raw, begin, at - begin)
            }
        }
        return out.toByteArray()
    }

    fun decode(bin: ByteArray): Image {
        require(bin.size >= 12 && bin[0].toInt() and 255 == 0x19) { "图像头不合法" }
        val input = ByteBuffer.wrap(bin).order(ByteOrder.LITTLE_ENDIAN)
        val cf = bin[1].toInt() and 255
        val flags = input.getShort(2).toInt() and 65535
        val w = input.getShort(4).toInt() and 65535
        val h = input.getShort(6).toInt() and 65535
        val stride = input.getShort(8).toInt() and 65535
        require(w in 1..512 && h in 1..512)
        if (cf == 16 && flags == 0) {
            require(stride >= w * 4 && bin.size == 12 + stride * h)
            return Image(w, h, IntArray(w * h) { i -> input.getInt(12 + (i / w) * stride + (i % w) * 4) })
        }
        require(cf == 10 && flags == 8 && stride >= w && bin.size >= 24) { "图像编码不支持" }
        require(input.getInt(12) == 1 && input.getInt(16) == bin.size - 24 && input.getInt(20) == 1024 + stride * h)
        val raw = ByteArray(input.getInt(20))
        var at = 24; var dst = 0
        while (at < bin.size) {
            val tag = bin[at++].toInt() and 255
            val count = tag and 127
            require(count > 0 && dst + count <= raw.size)
            if (tag and 128 != 0) {
                require(at + count <= bin.size)
                bin.copyInto(raw, dst, at, at + count); at += count
            } else {
                require(at < bin.size)
                raw.fill(bin[at++], dst, dst + count)
            }
            dst += count
        }
        require(dst == raw.size)
        val palette = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN)
        return Image(w, h, IntArray(w * h) { i -> palette.getInt((raw[1024 + i / w * stride + i % w].toInt() and 255) * 4) })
    }
}
