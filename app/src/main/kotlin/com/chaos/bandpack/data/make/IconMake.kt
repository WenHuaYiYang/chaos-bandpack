package com.chaos.bandpack.data.make

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.chaos.bandpack.data.icon.IconConvert
import com.chaos.bandpack.data.Assets
import com.chaos.bandpack.data.icon.IconSpec
import com.chaos.bandpack.data.icon.LvglIconCodec

/**
 * 桌面图标的处理与预览。
 *
 * "格式/尺寸不合适自动处理"这件事全在 [convert] 里: 解码交给系统(带降采样, 大图不会 OOM),
 * 几何交给 [IconConvert](外接方框 -> 内容框 100x100 -> 画布 112x112 居中, 四边 6px 留白)。
 * 用户拿到的图**不补底、不切圆角、不换色** —— 不合适就给出可读原因让他换图。
 */
object IconMake {

    class Result(val bytes: ByteArray, val report: IconConvert.Report)

    /** content:// -> 图标字节。大图先按最长边 1024 降采样再交给几何处理 */
    fun convert(ctx: Context, uri: Uri, slot: IconSpec.Slot = IconSpec.DESKTOP.first()): Result {
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

    /** 已转换的图标(112x112 BGRA + 12 字节头) -> 可直接画的位图 */
    fun previewOf(bin: ByteArray?): ImageBitmap? {
        bin ?: return null
        val image = runCatching { LvglIconCodec.decode(bin) }.getOrNull() ?: return null
        val bmp = Bitmap.createBitmap(image.width, image.height, Bitmap.Config.ARGB_8888)
        bmp.setPixels(image.pixels, 0, image.width, 0, 0, image.width, image.height)
        return bmp.asImageBitmap()
    }

    private val stockCache = HashMap<String, ImageBitmap?>()

    /**
     * 系统原图标(逆向固件资源包得到, 构建时同步进 assets/stock_icons)。
     * 没有这一张时返回 null —— 界面用"系统原图标"占位表示"这个槽不放进包"。
     */
    fun stockIcon(ctx: Context, stem: String): ImageBitmap? = stockCache.getOrPut(stem) {
        runCatching {
            val bytes = Assets.stockIcon(ctx, stem) ?: return@getOrPut null
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
        }.getOrNull()
    }
}
