package com.chaos.bandpack.data

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * 外部送进来的文件（"用 Chaos 打开" / 分享到 Chaos）。
 *
 * 为什么值得做: 字体文件在手机上的常态是躺在"下载"或网盘目录里, 用户从文件管理器
 * 分享过来一步就到; 而系统文件选择器在部分 ROM 上连推送到本地的文件都要等媒体库索引
 * 才看得见。两条路都留着, 用户哪条顺走哪条。
 *
 * 生命周期: MainActivity 在 onCreate 里塞进来, 界面消费一次后清掉 —— 否则旋转屏/重组
 * 会把它当成新的输入反复触发。
 */
object Incoming {

    data class Source(val uri: Uri, val mime: String?)
    private var mime: String? = null

    var sequence: Long by mutableStateOf(0L)
        private set
    @Volatile
    var uri: Uri? = null
        set(value) {
            field = value
            if (value != null) sequence++
        }

    fun take(): Source? {
        val u = uri ?: return null
        val source = Source(u, mime)
        uri = null
        mime = null
        return source
    }

    /** 从 Intent 里取出"要我处理的文件"。VIEW 取 data, SEND 取 EXTRA_STREAM */
    fun from(intent: Intent?): Uri? {
        intent ?: return null
        val source = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            else -> null
        }
        if (source != null) mime = intent.type
        return source
    }

    /** 按 MIME + 扩展名猜这是字体还是图片。猜不准返回 null(界面自己决定怎么提示) */
    fun kindOf(uri: Uri, mime: String?, displayName: String? = null): Kind? {
        val m = mime?.lowercase().orEmpty()
        if (m.startsWith("image/")) return Kind.IMAGE
        if (m.startsWith("font/") || m.contains("font") || m.contains("truetype")) return Kind.FONT
        val name = (displayName ?: uri.lastPathSegment)?.lowercase().orEmpty()
        return when {
            name.endsWith(".ttf") || name.endsWith(".otf") || name.endsWith(".ttc") -> Kind.FONT
            name.endsWith(".png") || name.endsWith(".jpg") || name.endsWith(".jpeg") ||
                name.endsWith(".webp") || name.endsWith(".bmp") -> Kind.IMAGE
            name.endsWith(".bin") || name.endsWith(".chaosproj") || m == "application/octet-stream" || m == "application/zip" -> Kind.PACK
            else -> null
        }
    }

    enum class Kind { FONT, IMAGE, PACK }
}
