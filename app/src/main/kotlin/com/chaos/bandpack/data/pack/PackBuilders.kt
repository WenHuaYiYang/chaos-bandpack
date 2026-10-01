package com.chaos.bandpack.data.pack

/**
 * 两种投递包的组装(与 PC 侧 `build_font_pack.py` / `build_icon_pack.py` 同口径)。
 *
 * 槽位语义必须与主包一致 —— 载荷排第 4 槽, 前三个槽是 lua / ko / 图标:
 *   字体包: _lua/fontpack/{main.lua, chaos_sup.ko, chaos_icon.bin, font.ttf}
 *   图标包: _lua/iconpack/{main.lua, chaos_sup.ko, chaos_icon.bin, pack.bin}
 * 真机踩过的坑: 槽 3/4 放说明文本 => 表盘在列表里能看到、切过去全黑、脚本一行不执行。
 *
 * 投递 Lua 里的占位符在**打包时**替换(表盘容器里的脚本读不到自己的显示名),
 * 规则与 PC 侧一致: 每个占位符必须恰好出现一次, 少了说明脚本被改过而替换没跟上
 * (替换会静默失效), 多了说明有地方会漏改 —— 两种都当错误打死, 不猜。
 *
 * 预览块由调用方按包生成([PreviewFactory]), **不是可选项**: 表盘列表里那张图就是它。
 */
object FontPackBuilder {

    const val LABEL_BYTES = 12
    const val PH_NAME = "__FONT_NAME__"
    const val PH_LABEL = "__PACK_LABEL__"
    const val PH_TITLE = "__PACK_TITLE__"

    class Inputs(
        /** 清单短名(投递后清单里的名字, <= 12 字节, 可中文) */
        val label: String,
        /** 表盘显示名(手环表盘列表里看到的) */
        val packName: String,
        /** 表盘内那行标题("字体投递 X") */
        val title: String,
        /** 12 位数字包名, 传 null 时由字体内容自动推导 */
        val pkgName: String?,
        /** 已归一化 + 子集化的字体字节(就是要写进包里的那一段) */
        val font: ByteArray,
    )

    class Result(val bytes: ByteArray, val pkgName: String, val packName: String)

    fun build(a: PackAssets, inputs: Inputs, preview: ByteArray): Result {
        val labelBytes = inputs.label.toByteArray(Charsets.UTF_8)
        if (labelBytes.isEmpty() || labelBytes.size > LABEL_BYTES) {
            throw ShellWriter.PackError("字体短名要在 1..$LABEL_BYTES 字节之间: 「${inputs.label}」")
        }
        if (inputs.label.any { it.code < 0x20 }) throw ShellWriter.PackError("字体短名不能有控制字符")
        TitleText.validate(inputs.title)?.let { /* 超宽只是提醒, 不挡打包 */ }

        val lua = patchLua(a.fontLua, mapOf(
            PH_NAME to inputs.label,
            PH_LABEL to inputs.label,
            PH_TITLE to inputs.title,
        ))

        val entries = listOf(
            ShellBuilder.Entry("_lua/fontpack/main.lua", lua.toByteArray(Charsets.UTF_8)),
            ShellBuilder.Entry("_lua/fontpack/chaos_sup.ko", a.ko),
            ShellBuilder.Entry("_lua/fontpack/chaos_icon.bin", a.iconBin),
            ShellBuilder.Entry("_lua/fontpack/font.ttf", inputs.font),
        )
        val pkg = inputs.pkgName?.also { ShellWriter.checkPkg(it) } ?: ShellWriter.pkgFor(inputs.font)
        val out = ShellBuilder.build(entries, pkg, inputs.packName, preview)
        verifyBuilt(out, pkg, inputs.packName, entries)
        checkPackedLua(out, 1, listOf(PH_NAME, PH_LABEL, PH_TITLE), inputs.label)
        return Result(out, pkg, inputs.packName)
    }

    /** 打完之后回读第 1 槽, 确认占位符一个不剩(PC 侧同一道门) */
    private fun checkPackedLua(out: ByteArray, idx: Int, placeholders: List<String>, label: String) {
        val (path, data) = ShellWriter.readEntry(out, idx)
        if (!path.endsWith("main.lua")) throw ShellWriter.PackError("第 $idx 槽不是投递 Lua: $path")
        val txt = String(data, Charsets.UTF_8)
        for (ph in placeholders) {
            if (ph in txt) throw ShellWriter.PackError("投递 Lua 里还留着 $ph 占位符")
        }
        if (!txt.contains("local FONT_NAME = \"$label\"")) {
            throw ShellWriter.PackError("投递 Lua 里的短名不是「$label」")
        }
    }
}

object IconPackBuilder {

    const val SHORT_BYTES = 12
    const val PH_NAME = "__PACK_NAME__"
    const val PH_TITLE = "__PACK_TITLE__"

    class Inputs(
        /** 包短名(清单里的名字, 可打印 ASCII, <= 12 字节) */
        val short: String,
        val packName: String,
        val title: String,
        val pkgName: String?,
        /** 要打进包的图标(未选的槽位不进包, 手环就保持系统原图标) */
        val icons: List<Cipk.Icon>,
    )

    class Result(val bytes: ByteArray, val pkgName: String, val packName: String, val iconCount: Int)

    fun build(a: PackAssets, inputs: Inputs, preview: ByteArray): Result {
        val sb = inputs.short.toByteArray(Charsets.US_ASCII)
        if (sb.isEmpty() || sb.size > SHORT_BYTES) {
            throw ShellWriter.PackError("图标包短名要在 1..$SHORT_BYTES 字节之间")
        }
        if (inputs.short.any { it.code <= 0x20 || it.code >= 0x7F }) {
            throw ShellWriter.PackError("图标包短名只能是可打印 ASCII: 「${inputs.short}」")
        }

        val cipk = Cipk.build(inputs.icons)
        val lua = patchLua(a.iconLua, mapOf(PH_NAME to inputs.short, PH_TITLE to inputs.title))

        val entries = listOf(
            ShellBuilder.Entry("_lua/iconpack/main.lua", lua.toByteArray(Charsets.UTF_8)),
            ShellBuilder.Entry("_lua/iconpack/chaos_sup.ko", a.ko),
            ShellBuilder.Entry("_lua/iconpack/chaos_icon.bin", a.iconBin),
            ShellBuilder.Entry("_lua/iconpack/pack.bin", cipk),
        )
        val pkg = inputs.pkgName?.also { ShellWriter.checkPkg(it) } ?: ShellWriter.pkgFor(cipk)
        val out = ShellBuilder.build(entries, pkg, inputs.packName, preview)
        verifyBuilt(out, pkg, inputs.packName, entries)

        // 回读: 第 1 槽的短名替换干净, 第 4 槽的 CIPK 逐字节等于本次生成
        val (luaPath, luaData) = ShellWriter.readEntry(out, 1)
        if (!luaPath.endsWith("main.lua")) throw ShellWriter.PackError("第 1 槽不是投递 Lua")
        val txt = String(luaData, Charsets.UTF_8)
        for (ph in listOf(PH_NAME, PH_TITLE)) {
            if (ph in txt) throw ShellWriter.PackError("投递 Lua 里还留着 $ph 占位符")
        }
        if (inputs.short !in txt) throw ShellWriter.PackError("投递 Lua 里没找到短名「${inputs.short}」")
        val (packPath, packData) = ShellWriter.readEntry(out, 4)
        if (!packPath.endsWith("pack.bin")) throw ShellWriter.PackError("第 4 槽不是 CIPK: $packPath")
        if (!packData.contentEquals(cipk)) throw ShellWriter.PackError("pack.bin 与本次生成的容器不一致")
        val back = Cipk.parse(packData)
        if (back.size != inputs.icons.size) throw ShellWriter.PackError("CIPK 解回来张数不对")
        inputs.icons.forEachIndexed { i, ic ->
            val (name, data) = back[i]
            if (name != ic.fileName) throw ShellWriter.PackError("第 ${i + 1} 张名字对不上: $name")
            if (!data.contentEquals(ic.data)) throw ShellWriter.PackError("$name 内容不一致")
        }
        return Result(out, pkg, inputs.packName, back.size)
    }
}

/**
 * 打包的最后一道门: 把刚写出来的字节拆回来, 核对包名、显示名、槽数、每条槽的路径与内容。
 * 与"自己写出来"是两条独立路径(写入按表达式算, 回读按记录表里的偏移取), 所以能抓错位。
 */
internal fun verifyBuilt(
    out: ByteArray,
    pkgName: String,
    packName: String,
    entries: List<ShellBuilder.Entry>,
) {
    val p = ShellBuilder.parse(out)
    if (p.pkg != pkgName) throw ShellWriter.PackError("包名写错: ${p.pkg}")
    if (p.displayName != packName) throw ShellWriter.PackError("表盘名写错: ${p.displayName}")
    if (p.files.size != entries.size) {
        throw ShellWriter.PackError("槽数不符: 期望 ${entries.size}, 实际 ${p.files.size}")
    }
    entries.forEachIndexed { i, e ->
        val (path, data) = p.files[i]
        if (path != e.path) throw ShellWriter.PackError("第 ${i + 1} 槽路径不符: $path")
        if (!data.contentEquals(e.data)) throw ShellWriter.PackError("第 ${i + 1} 槽内容不一致: $path")
    }
    ShellWriter.checkPkgAgainst(pkgName)
}

/**
 * 把占位符换成本次的取值。[map] 里每个键都必须**恰好出现一次** —— 与 PC 侧同一条纪律。
 *
 * 另外先把换行归一成 LF: 设备侧仓库里的 Lua 是 CRLF, 而 PC 侧打包器用文本模式读(Python 会把
 * CRLF 折成 LF), 于是同一个模板两端产出的字节数会差"行数"那么多 —— 逐字节对照测试
 * 就是靠这个差异发现的。归一只做一次, 放在这个函数里, 调用方不用各自记得。
 */
internal fun patchLua(src: String, map: Map<String, String>): String {
    val norm = src.replace("\r\n", "\n").replace('\r', '\n')
    for ((ph, _) in map) {
        val n = countOccurrences(norm, ph)
        if (n != 1) throw ShellWriter.PackError("投递 Lua 里 $ph 应恰好出现 1 次, 实际 $n 次")
    }
    var out = norm
    for ((ph, v) in map) out = out.replace(ph, luaQuote(v))
    return out
}

private fun countOccurrences(s: String, sub: String): Int {
    var n = 0
    var i = s.indexOf(sub)
    while (i >= 0) {
        n++
        i = s.indexOf(sub, i + sub.length)
    }
    return n
}

/**
 * 写成 Lua 双引号字面量。取值来自用户输入, 引号/反斜杠漏进去会在表盘的**构建期**
 * 抛错 => 整棵 UI 树不提交 => 切过去全黑(首版黑屏就是这一类)。
 */
internal fun luaQuote(s: String): String {
    val sb = StringBuilder(s.length + 8)
    for (ch in s) {
        when {
            ch == '"' || ch == '\\' -> sb.append('\\').append(ch)
            ch.code < 0x20 -> sb.append("\\%d".format(ch.code))
            else -> sb.append(ch)
        }
    }
    return sb.toString()
}
