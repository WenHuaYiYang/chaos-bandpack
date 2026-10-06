package com.chaos.bandpack.data.pack

import com.chaos.bandpack.data.icon.NineIconSpec
import com.chaos.bandpack.data.icon.LvglIconCodec

/** 沿用 9 Pro 的独立素材导入协议。 */
object NinePackBuilder {
    const val MAIN_PKG = "990000000028"
    const val CHUNK_BYTES = 64000
    const val MAX_FONT_BYTES = 8_000_000

    fun font(template: String, inputs: FontPackBuilder.Inputs, preview: ByteArray): FontPackBuilder.Result {
        checkLabel(inputs.label)
        require(inputs.font.size in 12..MAX_FONT_BYTES && inputs.font.take(4) == listOf<Byte>(0, 1, 0, 0)) { "9 Pro 需要不超过 8 MB 的独立 TrueType 字体" }
        val pkg = inputs.pkgName ?: ShellWriter.pkgFor(inputs.font + inputs.label.toByteArray(Charsets.UTF_8))
        val leaves = (inputs.font.indices step CHUNK_BYTES).mapIndexed { i, start ->
            ShellBuilder.Entry("_lua/_Lua/font-%03d.dat".format(java.util.Locale.ROOT, i), inputs.font.copyOfRange(start, minOf(start + CHUNK_BYTES, inputs.font.size)))
        }
        val out = build(template, "font", pkg, inputs.label, inputs.title, inputs.packName, leaves, emptyList(), preview)
        return FontPackBuilder.Result(out, pkg, inputs.packName)
    }

    fun icons(template: String, inputs: IconPackBuilder.Inputs, preview: ByteArray): IconPackBuilder.Result {
        checkLabel(inputs.short)
        val icons = inputs.icons.sortedBy { it.stem }
        require(icons.size in 1..NineIconSpec.SLOTS.size && icons.map { it.stem }.toSet().size == icons.size)
        for (icon in icons) {
            val slot = requireNotNull(NineIconSpec.SLOTS.find { it.fileStem == icon.stem }) { "9 Pro 没有图标槽：${icon.stem}" }
            val image = LvglIconCodec.decode(icon.data)
            require(image.width == slot.width && image.height == slot.height && icon.data.size == 4 + slot.width * slot.height * 4)
        }
        // 原始包身份算法支持更多素材，CIPK 仅用于哈希。
        val identity = java.io.ByteArrayOutputStream().apply {
            write("CIPK".toByteArray(Charsets.US_ASCII)); write(ShellWriter.u32(icons.size))
            icons.forEach {
            val name = "${it.stem}.bin".toByteArray(Charsets.US_ASCII)
            write(ShellWriter.u32(it.data.size)); write(name.size); write(name); write(it.data)
        } }.toByteArray()
        val pkg = inputs.pkgName ?: ShellWriter.pkgFor(identity + inputs.short.toByteArray(Charsets.UTF_8))
        val leaves = icons.map { ShellBuilder.Entry("_lua/_Lua/${it.stem}.dat", it.data) }
        val out = build(template, "icons", pkg, inputs.short, inputs.title, inputs.packName, leaves, icons.map { it.stem }, preview)
        return IconPackBuilder.Result(out, pkg, inputs.packName, icons.size)
    }

    private fun checkLabel(label: String) {
        require(label.toByteArray(Charsets.UTF_8).size in 1..12 && label.none { it.isWhitespace() || it.code < 32 }) {
            "9 Pro 素材短名须为 1..12 个 UTF-8 字节，不能含空格或控制字符"
        }
    }

    private fun quoted(text: String) = "\"${luaQuote(text)}\""

    private fun build(template: String, kind: String, pkg: String, label: String, title: String, display: String,
                      leaves: List<ShellBuilder.Entry>, stems: List<String>, preview: ByteArray): ByteArray {
        ShellWriter.checkPkg(pkg); ShellWriter.checkPkgAgainst(pkg); ShellWriter.checkPkgAgainst(pkg, MAIN_PKG)
        require(title.isNotBlank() && title.length <= 256 && title.none { it.code < 32 }) { "标题为空、过长或包含控制字符" }
        val rows = leaves.mapIndexed { i, entry ->
            "{src=${quoted(entry.path.substringAfterLast('/'))},bytes=${entry.data.size},sum=${entry.data.sumOf { it.toInt() and 255 }}" +
                (if (kind == "icons") NineIconSpec.SLOTS.single { it.fileStem == stems[i] }.let {
                    ",stem=${quoted(stems[i])},width=${it.width},height=${it.height}"
                } else "") + "}"
        }.joinToString(",\n")
        val allStems = (NineIconSpec.SLOTS.map { it.fileStem } + listOf("ctrl_phone_conn", "ctrl_phone_disconn"))
        val manifest = "{kind=${quoted(kind)},pkg=${quoted(pkg)},label=${quoted(label)},title=${quoted(title)},stems={${allStems.joinToString(",") { quoted(it) }}},entries={$rows}}"
        require(template.split("__N67_MANIFEST__").size == 2) { "9 Pro 模板占位符不匹配" }
        val lua = template.replace("\r\n", "\n").replace("__N67_MANIFEST__", manifest).toByteArray(Charsets.UTF_8)
        require(lua.size <= 65535)
        val entries = listOf(NineShellBuilder.Entry("_lua/_Lua/main.lua", lua)) + leaves.map { NineShellBuilder.Entry(it.path, it.data) }
        val out = NineShellBuilder.build(entries, pkg, display, preview)
        val parsed = NineShellBuilder.parse(out)
        require(parsed.pkg == pkg && parsed.displayName == display && parsed.files.size == entries.size)
        entries.forEachIndexed { i, entry -> require(parsed.files[i].first == entry.path && parsed.files[i].second.contentEquals(entry.data)) }
        return out
    }
}
