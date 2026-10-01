package com.chaos.bandpack.data

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns

/**
 * 取一个 `content://` URI 的**显示文件名**。
 *
 * 必须查 `OpenableColumns.DISPLAY_NAME`，**不能**用 `uri.lastPathSegment` ——
 * MediaStore 的 URI 里那一段是行号（例如 `images/media/1000000026`），
 * 拿它当文件名会给用户显示一串数字（真机上出现过）。
 * 查不到时退回 lastPathSegment，至少比空着强。
 */
fun displayNameOf(ctx: Context, uri: Uri): String? =
    runCatching {
        ctx.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { c -> if (c.moveToFirst() && !c.isNull(0)) c.getString(0) else null }
    }.getOrNull() ?: uri.lastPathSegment
