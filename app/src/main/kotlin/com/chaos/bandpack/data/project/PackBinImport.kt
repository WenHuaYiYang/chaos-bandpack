package com.chaos.bandpack.data.project

import com.chaos.bandpack.data.DeviceTarget
import com.chaos.bandpack.data.font.Sfnt
import com.chaos.bandpack.data.icon.IconSpec
import com.chaos.bandpack.data.icon.NineIconSpec
import com.chaos.bandpack.data.icon.LvglIconCodec
import com.chaos.bandpack.data.pack.*
import java.io.ByteArrayOutputStream

/** 仅提取容器里的素材和字面量清单，不加载其中的 Lua 或原生模块。 */
object PackBinImport {
    fun read(bytes: ByteArray): ChaosProject {
        require(bytes.size <= ProjectCodec.MAX_BYTES) { "投递包超过 32 MB" }
        val ten = runCatching { ShellBuilder.parse(bytes) }.getOrNull()
        val nine = if (ten == null) NineShellBuilder.parse(bytes) else null
        val parsed = ten?.files ?: nine!!.files
        val pkg = ten?.pkg ?: nine!!.pkg
        val display = ten?.displayName ?: nine!!.displayName
        ShellWriter.checkPkg(pkg)
        val cipk = parsed.singleOrNull { it.first == "_lua/iconpack/pack.bin" }
        if (cipk != null) {
            val lua = parsed.singleOrNull { it.first == "_lua/iconpack/main.lua" }?.second?.toString(Charsets.UTF_8)
                ?: error("缺少图标投递清单")
            val info = PackInfo(localString(lua, "PACK_NAME") ?: "MyIcons", display, localString(lua, "PACK_TITLE") ?: "图标投递", pkg)
            val images = Cipk.parse(cipk.second).associate { it.first.removeSuffix(".bin") to it.second }
                .toMutableMap()
            images.values.forEach { LvglIconCodec.decode(it) }
            if ("ctrl_disturb" !in images) images["ctrl_dnd"]?.let { animation ->
                val image = LvglIconCodec.decode(animation)
                require(image.width == 160 && image.height == 124) { "勿扰动画尺寸不支持" }
                val static = IntArray(64 * 64)
                for (y in 0 until 64) System.arraycopy(image.pixels, (y + 30) * 160 + 48, static, y * 64, 64)
                images["ctrl_disturb"] = LvglIconCodec.bgra(static, 64, 64)
            }
            return ChaosProject(DeviceTarget.TEN_PRO, icons = IconProject(info, images))
        }
        val font = parsed.singleOrNull { it.first == "_lua/fontpack/font.ttf" }
        if (font != null) {
            Sfnt(font.second)
            val lua = parsed.singleOrNull { it.first == "_lua/fontpack/main.lua" }?.second?.toString(Charsets.UTF_8)
                ?: error("缺少字体投递清单")
            val info = PackInfo(localString(lua, "FONT_NAME") ?: "font", display, localString(lua, "PACK_TITLE") ?: "字体投递", pkg)
            return ChaosProject(DeviceTarget.TEN_PRO, font = FontProject(info, "$display.ttf", font.second, preserve = true))
        }
        return readNine(parsed, pkg, display)
    }

    private fun localString(text: String, key: String): String? {
        val match = Regex("(?m)^local\\s+$key\\s*=\\s*([\"'])").find(text) ?: return null
        return LuaLiteral(text, match.range.last).value() as? String
    }

    @Suppress("UNCHECKED_CAST")
    private fun readNine(files: List<Pair<String, ByteArray>>, pkg: String, display: String): ChaosProject {
        val lua = files.singleOrNull { it.first == "_lua/_Lua/main.lua" }?.second?.toString(Charsets.UTF_8)
            ?: error("这不是可编辑的 Chaos 图标或字体投递包")
        val start = Regex("(?m)^local\\s+M\\s*=\\s*\\{").find(lua)
            ?: error("这是主安装包或其他表盘，请导入图标 / 字体投递包")
        val manifest = LuaLiteral(lua, start.range.last).value() as? Map<String, Any> ?: error("投递清单类型不合法")
        fun text(key: String) = manifest[key] as? String ?: error("投递清单缺少 $key")
        require(text("pkg") == pkg) { "清单与容器的表盘 ID 不一致" }
        val info = PackInfo(text("label"), display, text("title"), pkg)
        val rows = manifest["entries"] as? List<Map<String, Any>> ?: error("投递清单缺少素材")
        require(rows.size in 1..126)
        val leaves = files.filter { it.first != "_lua/_Lua/main.lua" }.toMap().toMutableMap()
        fun payload(row: Map<String, Any>): ByteArray {
            val name = row["src"] as? String ?: error("素材名缺失")
            require(Regex("[a-z0-9_-]+\\.dat").matches(name)) { "素材名不合法" }
            val data = leaves.remove("_lua/_Lua/$name") ?: error("素材缺失或重复：$name")
            require(row["bytes"] == data.size && row["sum"] == data.sumOf { it.toInt() and 255 }) { "素材校验失败：$name" }
            return data
        }
        val result = when (text("kind")) {
            "icons" -> {
                val images = linkedMapOf<String, ByteArray>()
                for (row in rows) {
                    val fileStem = row["stem"] as? String ?: error("图标槽位缺失")
                    val slot = NineIconSpec.SLOTS.singleOrNull { it.fileStem == fileStem }
                    require(slot != null || fileStem in listOf("ctrl_phone_conn", "ctrl_phone_disconn")) { "9 Pro 图标槽位未知：$fileStem" }
                    val data = payload(row); val image = LvglIconCodec.decode(data)
                    val width = slot?.width ?: 48; val height = slot?.height ?: 48
                    require(image.width == width && image.height == height && row["width"] == width && row["height"] == height)
                    require(data.size == 4 + width * height * 4)
                    val key = slot?.stem ?: fileStem; require(key !in images) { "图标槽位重复" }; images[key] = data
                }
                ChaosProject(DeviceTarget.NINE_PRO, icons = IconProject(info, images))
            }
            "font" -> {
                require(rows.indices.all { i -> rows[i]["src"] == "font-%03d.dat".format(java.util.Locale.ROOT, i) }) { "字体分块顺序不完整" }
                val output = ByteArrayOutputStream()
                rows.forEach { row ->
                    val data = payload(row)
                    require(data.size in 1..NinePackBuilder.CHUNK_BYTES && output.size() + data.size <= NinePackBuilder.MAX_FONT_BYTES)
                    output.write(data)
                }
                val source = output.toByteArray(); Sfnt(source)
                ChaosProject(DeviceTarget.NINE_PRO, font = FontProject(info, "$display.ttf", source, preserve = true))
            }
            else -> error("投递素材类型不支持")
        }
        require(leaves.isEmpty()) { "容器含有清单之外的文件" }
        return result
    }
}
