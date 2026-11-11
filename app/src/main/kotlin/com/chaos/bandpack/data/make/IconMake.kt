package com.chaos.bandpack.data.make

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.chaos.bandpack.data.icon.IconConvert
import com.chaos.bandpack.data.Assets
import com.chaos.bandpack.data.icon.IconSpec
import com.chaos.bandpack.data.icon.CalendarPreview
import com.chaos.bandpack.data.icon.LvglIconCodec
import com.chaos.bandpack.data.icon.AnimatedIcons
import com.chaos.bandpack.data.icon.Dgf1
import com.chaos.bandpack.data.icon.GifIcons
import com.chaos.bandpack.data.icon.IconInputNames
import com.chaos.bandpack.data.DeviceTarget
import com.chaos.bandpack.data.displayNameOf
import java.time.LocalDate

/** URI decoding, GIF/native imports, previews and atomic per-slot batch pairing. */
object IconMake {

    class Result(val bytes: ByteArray, val report: IconConvert.Report, val animation: ByteArray? = null, val frames: Int = 0)
    data class Batch(val picked: Map<String, ByteArray>, val ok: Int, val unmatched: Int, val bad: List<String>)

    /** New still images are downsampled before conversion; GIF/native inputs use bounded readers. */
    fun convert(ctx: Context, uri: Uri, slot: IconSpec.Slot = IconSpec.DESKTOP.first(), existingCover: ByteArray? = null): Result {
        val prefix = ctx.contentResolver.openInputStream(uri)!!.use { stream ->
            val bytes = ByteArray(12); var n = 0
            while (n < bytes.size) { val read = stream.read(bytes, n, bytes.size - n); if (read <= 0) break; n += read }
            bytes.copyOf(n)
        }
        val name = displayNameOf(ctx, uri).orEmpty()
        val gif = GifIcons.isGif(prefix) || name.endsWith(".gif", ignoreCase = true)
        if (gif || Dgf1.isAnimation(prefix)) {
            require(slot.device == DeviceTarget.TEN_PRO && slot.group == IconSpec.Group.DESKTOP && slot.stem in AnimatedIcons.STEMS) {
                "GIF / DGF1 动画仅支持 10 Pro 桌面图标；9 Pro 和系统 UI 请使用静态图片或 BIN"
            }
            val bytes = readBounded(ctx, uri, if (gif) GifIcons.MAX_SOURCE_BYTES else Dgf1.MAX_BYTES)
            if (gif) {
                val made = GifIcons.convert(bytes)
                return Result(made.cover, report(made.cover), made.animation, made.frameCount)
            }
            val animation = Dgf1.parse(bytes)
            val cover = requireNotNull(existingCover) { "导入 _anim.bin 时必须同时提供 96 × 96 静态封面" }
            AnimatedIcons.validateProject(mapOf(slot.stem to cover, AnimatedIcons.key(slot.stem) to bytes))
            return Result(cover, report(cover), bytes, animation.frames.size)
        }
        if (name.endsWith(".bin", ignoreCase = true)) {
            val bytes = readBounded(ctx, uri, com.chaos.bandpack.data.pack.Cipk.ICON_LEN_MAX)
            val converted = com.chaos.bandpack.data.icon.PortableIcons.convert(bytes, slot)
            return Result(converted, report(converted))
        }
        require(slot.group != IconSpec.Group.NATIVE) { "此系统资源只接受原尺寸的原生 BIN" }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        ctx.contentResolver.openInputStream(uri)!!.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw IllegalArgumentException("这个文件不是图片")
        }
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        var sample = 1
        while (longest / sample > 1024) sample *= 2

        val opts = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val bmp = ctx.contentResolver.openInputStream(uri)!!.use { BitmapFactory.decodeStream(it, null, opts) }
            ?: throw IllegalArgumentException("这个文件不是图片")
        val w = bmp.width
        val h = bmp.height
        val px = IntArray(w * h)
        bmp.getPixels(px, 0, w, 0, 0, w, h)
        bmp.recycle()
        val (out, rep) = IconConvert.convert(px, w, h, slot)
        return Result(out, rep)
    }

    fun importMany(ctx: Context, uris: List<Uri>, device: DeviceTarget, picked: Map<String, ByteArray>): Batch {
        val plan = IconInputNames.plan(uris.map { runCatching { displayNameOf(ctx, it).orEmpty() }.getOrDefault("") }, device)
        var next = picked; var ok = 0; val bad = mutableListOf<String>()
        for (group in plan.groups) {
            val slot = requireNotNull(IconSpec.stemOf(group.stem, device))
            if (group.error != null) { bad += "${slot.label}：${group.error}"; continue }
            runCatching {
                var cover: ByteArray? = null; var animation: ByteArray? = null
                group.sources.singleOrNull { it.kind == IconInputNames.Kind.GIF }?.let {
                    val made = convert(ctx, uris[it.index], slot)
                    require(made.animation != null) { "GIF 文件内容与扩展名不符" }
                    cover = made.bytes; animation = made.animation
                }
                group.sources.singleOrNull { it.kind in listOf(IconInputNames.Kind.IMAGE, IconInputNames.Kind.BIN) }?.let {
                    val made = convert(ctx, uris[it.index], slot)
                    require(made.animation == null) { "动画 BIN 必须命名为 <stem>_anim.bin" }
                    cover = made.bytes
                }
                group.sources.singleOrNull { it.kind == IconInputNames.Kind.ANIMATION }?.let {
                    val made = convert(ctx, uris[it.index], slot, cover ?: picked[group.stem])
                    require(made.animation != null) { "_anim.bin 中没有 DGF1 动画" }
                    cover = made.bytes; animation = made.animation
                }
                val files = mutableMapOf(group.stem to requireNotNull(cover) { "缺少静态封面" })
                animation?.let { files[AnimatedIcons.key(group.stem)] = it }
                AnimatedIcons.validateProject(files)
                next = AnimatedIcons.withoutSlot(next, group.stem) + files
                ok++
            }.onFailure { bad += "${slot.label}：${it.message ?: "素材不合适"}" }
        }
        return Batch(next, ok, plan.unmatched, bad)
    }

    private fun readBounded(ctx: Context, uri: Uri, max: Int): ByteArray = ctx.contentResolver.openInputStream(uri)!!.use { stream ->
        val out = java.io.ByteArrayOutputStream(); val buffer = ByteArray(65536)
        while (true) {
            val n = stream.read(buffer); if (n < 0) break
            require(n <= max - out.size()) { "素材超过容量上限 $max 字节" }
            if (n > 0) out.write(buffer, 0, n)
        }
        out.toByteArray()
    }

    private fun report(bytes: ByteArray): IconConvert.Report {
        val image = LvglIconCodec.decode(bytes)
        return IconConvert.Report(image.pixels.count { it ushr 24 > 200 }.toDouble() / image.pixels.size, maxOf(image.width, image.height), maxOf(image.width, image.height))
    }

    /** 已转换的图标(112x112 BGRA + 12 字节头) -> 可直接画的位图 */
    fun previewOf(bin: ByteArray?): ImageBitmap? {
        bin ?: return null
        val image = runCatching { LvglIconCodec.decode(bin) }.getOrNull() ?: return null
        val bmp = Bitmap.createBitmap(image.width, image.height, Bitmap.Config.ARGB_8888)
        bmp.setPixels(image.pixels, 0, image.width, 0, 0, image.width, image.height)
        return bmp.asImageBitmap()
    }

    private val stockCache = HashMap<String, ImageBitmap?>()
    private var calendarCache: Pair<LocalDate, ImageBitmap>? = null

    /**
     * 系统原图标(逆向固件资源包得到, 构建时同步进 assets/stock_icons)。
     * 没有这一张时返回 null —— 界面用"系统原图标"占位表示"这个槽不放进包"。
     */
    fun stockIcon(ctx: Context, stem: String): ImageBitmap? {
        if (stem == "perpetual_calendar") return calendarIcon(ctx, LocalDate.now())
        return stockCache.getOrPut(stem) {
            runCatching {
                val bytes = Assets.stockIcon(ctx, stem) ?: return@getOrPut null
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
            }.getOrNull()
        }
    }

    /** 原背景上绘制当天日期，只在页面取图时更新。 */
    private fun calendarIcon(ctx: Context, date: LocalDate): ImageBitmap? {
        calendarCache?.takeIf { it.first == date }?.let { return it.second }
        return runCatching {
            val bytes = Assets.stockIcon(ctx, "perpetual_calendar") ?: return null
            val background = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
            require(background.width == background.height && background.width in listOf(IconSpec.LEGACY_CANVAS, IconSpec.CANVAS))
            val bitmap = background.copy(Bitmap.Config.ARGB_8888, true)
            background.recycle()
            val canvas = Canvas(bitmap)
            canvas.scale(bitmap.width / 112f, bitmap.height / 112f)
            val face = runCatching { Typeface.createFromAsset(ctx.assets, "fonts/MiSans-Regular-subset.ttf") }
                .getOrDefault(Typeface.SANS_SERIF)
            fun text(value: String, top: Float, size: Float, color: Int, weight: Int) {
                val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    textSize = size
                    this.color = color
                    textAlign = Paint.Align.CENTER
                    typeface = if (Build.VERSION.SDK_INT >= 28) Typeface.create(face, weight, false)
                    else Typeface.create(face, if (weight >= 600) Typeface.BOLD else Typeface.NORMAL)
                }
                canvas.drawText(value, 56f, top - paint.fontMetrics.ascent, paint)
            }
            text(CalendarPreview.week(date), CalendarPreview.WEEK_TOP, CalendarPreview.WEEK_SIZE, CalendarPreview.WEEK_COLOR, 600)
            text(CalendarPreview.day(date), CalendarPreview.DAY_TOP, CalendarPreview.DAY_SIZE, CalendarPreview.DAY_COLOR, 500)
            bitmap.asImageBitmap().also { calendarCache = date to it }
        }.getOrNull()
    }
}
