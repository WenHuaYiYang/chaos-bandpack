package com.chaos.bandpack.data.make

import android.content.Context
import com.chaos.bandpack.data.Assets
import com.chaos.bandpack.data.pack.Cipk
import com.chaos.bandpack.data.pack.FontPackBuilder
import com.chaos.bandpack.data.pack.IconPackBuilder
import com.chaos.bandpack.data.pack.PackAssets
import com.chaos.bandpack.data.pack.PreviewFactory

/**
 * 打包编排。素材(内核模块 / 应用图标 / 两个投递 Lua)在进程里只读一次 ——
 * 每次打包都重新读一遍没有意义, 而它们在一次运行里不会变。
 */
object PackMake {

    @Volatile
    private var cached: PackAssets? = null

    fun assets(ctx: Context): PackAssets =
        cached ?: synchronized(this) {
            cached ?: Assets.pack(ctx.applicationContext).also { cached = it }
        }

    fun fontPack(ctx: Context, inputs: FontPackBuilder.Inputs): FontPackBuilder.Result =
        FontPackBuilder.build(assets(ctx), inputs, PreviewFactory.fontBlob(ctx.assets, inputs.title))

    fun iconPack(ctx: Context, inputs: IconPackBuilder.Inputs): IconPackBuilder.Result =
        IconPackBuilder.build(
            assets(ctx), inputs,
            PreviewFactory.iconBlob(ctx.assets, inputs.title, inputs.short),
        )

    /** 图标素材名 -> 已转换的图标(打包时直接取) */
    fun icon(stem: String, data: ByteArray): Cipk.Icon = Cipk.Icon(stem, data)
}
