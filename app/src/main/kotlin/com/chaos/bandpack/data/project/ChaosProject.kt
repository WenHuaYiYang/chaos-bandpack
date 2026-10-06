package com.chaos.bandpack.data.project

import com.chaos.bandpack.data.DeviceTarget
import com.chaos.bandpack.data.icon.LvglIconCodec
import com.chaos.bandpack.data.font.Sfnt
import kotlinx.serialization.json.*
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

data class PackInfo(val short: String, val display: String, val title: String, val pkg: String = "")
data class IconProject(val info: PackInfo, val images: Map<String, ByteArray>)
data class FontProject(val info: PackInfo, val sourceName: String, val source: ByteArray,
    val charset: String = "SIMPLIFIED", val normalize: Boolean = true, val preserve: Boolean = false)
data class ChaosProject(val device: DeviceTarget, val icons: IconProject? = null, val font: FontProject? = null)

/** 可携带两种设备源素材的版本化工程容器。 */
object ProjectCodec {
    const val EXTENSION = "chaosproj"
    const val MAX_BYTES = 32_000_000
    private const val MAX_ENTRIES = 132
    private val key = Regex("[A-Za-z0-9_]{1,40}")
    private fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }

    private fun info(value: PackInfo) = buildJsonObject {
        listOf(value.short, value.display, value.title, value.pkg).forEach(::checkText)
        put("short", value.short); put("display", value.display); put("title", value.title); put("pkg", value.pkg)
    }

    fun write(project: ChaosProject): ByteArray {
        require(project.icons != null || project.font != null) { "工程没有素材" }
        val files = linkedMapOf<String, ByteArray>()
        val manifest = buildJsonObject {
            put("format", "chaos-studio-project"); put("version", 1); put("device", project.device.id)
            project.icons?.let { icons ->
                put("icons", buildJsonObject {
                    put("info", info(icons.info))
                    put("images", buildJsonArray { icons.images.toSortedMap().forEach { (stem, bytes) ->
                        require(key.matches(stem)) { "素材名不合法：$stem" }
                        LvglIconCodec.decode(bytes)
                        val path = "images/$stem.bin"; files[path] = bytes
                        add(buildJsonObject { put("key", stem); put("path", path); put("sha256", hash(bytes)) })
                    } })
                })
            }
            project.font?.let { font ->
                Sfnt(font.source)
                checkText(font.sourceName)
                require(font.charset in listOf("SIMPLIFIED", "WITH_TRADITIONAL")) { "工程字集不支持" }
                files["font/source.ttf"] = font.source
                put("font", buildJsonObject {
                    put("info", info(font.info)); put("name", font.sourceName)
                    put("charset", font.charset); put("normalize", font.normalize); put("preserve", font.preserve)
                    put("path", "font/source.ttf"); put("sha256", hash(font.source))
                })
            }
        }
        files["project.json"] = manifest.toString().toByteArray(Charsets.UTF_8).also { require(it.size <= 131072) { "工程清单过大" } }
        require(files.size <= MAX_ENTRIES && files.values.sumOf { it.size.toLong() } <= MAX_BYTES) { "工程超过 32 MB" }
        return ByteArrayOutputStream().apply {
            ZipOutputStream(this).use { zip -> files.forEach { (path, bytes) ->
                zip.putNextEntry(ZipEntry(path).apply { time = 0 }); zip.write(bytes); zip.closeEntry()
            } }
        }.toByteArray().also { require(it.size <= MAX_BYTES) { "工程超过 32 MB" } }
    }

    fun read(bytes: ByteArray): ChaosProject {
        require(bytes.size in 4..MAX_BYTES && bytes[0] == 0x50.toByte() && bytes[1] == 0x4b.toByte()) { "不是 Chaos 工程文件" }
        val files = linkedMapOf<String, ByteArray>()
        var total = 0
        ZipInputStream(bytes.inputStream()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                require(!entry.isDirectory && files.size < MAX_ENTRIES && entry.name !in files) { "工程条目重复或过多" }
                require(entry.name == "project.json" || entry.name == "font/source.ttf" || Regex("images/[A-Za-z0-9_]{1,40}\\.bin").matches(entry.name)) { "工程路径不合法" }
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = zip.read(buffer); if (count < 0) break
                    total += count
                    require(total <= MAX_BYTES && (entry.name != "project.json" || out.size() + count <= 131072)) { "工程展开后超过容量限制" }
                    out.write(buffer, 0, count)
                }
                files[entry.name] = out.toByteArray(); zip.closeEntry()
            }
        }
        val root = Json.parseToJsonElement(files.remove("project.json")?.toString(Charsets.UTF_8) ?: error("缺少工程清单")).jsonObject
        require(root["format"]?.jsonPrimitive?.content == "chaos-studio-project" && root["version"]?.jsonPrimitive?.int == 1) { "工程格式或版本不支持" }
        val device = DeviceTarget.fromId(root.string("device"))
        fun payload(row: JsonObject): ByteArray {
            val path = row.string("path")
            val data = files.remove(path) ?: error("缺少素材或重复引用：$path")
            require(hash(data) == row.string("sha256")) { "素材校验失败：$path" }
            return data
        }
        val icons = root["icons"]?.jsonObject?.let { row ->
            val images = linkedMapOf<String, ByteArray>()
            val list = row["images"]!!.jsonArray
            require(list.size <= 128)
            for (element in list) {
                val item = element.jsonObject; val stem = item.string("key")
                require(key.matches(stem) && stem !in images && item.string("path") == "images/$stem.bin") { "图标槽位重复或不合法" }
                images[stem] = payload(item).also { LvglIconCodec.decode(it) }
            }
            IconProject(readInfo(row["info"]!!.jsonObject), images)
        }
        val font = root["font"]?.jsonObject?.let { row ->
            require(row.string("path") == "font/source.ttf")
            val source = payload(row); Sfnt(source)
            val charset = row.string("charset")
            require(charset in listOf("SIMPLIFIED", "WITH_TRADITIONAL")) { "工程字集不支持" }
            FontProject(readInfo(row["info"]!!.jsonObject), row.string("name"), source, charset,
                row["normalize"]!!.jsonPrimitive.boolean, row["preserve"]!!.jsonPrimitive.boolean)
        }
        require(files.isEmpty() && (icons != null || font != null)) { "工程含有未声明素材或没有内容" }
        return ChaosProject(device, icons, font)
    }

    private fun JsonObject.string(name: String): String = requireNotNull(this[name]) { "工程缺少字段：$name" }.jsonPrimitive.content
        .also(::checkText)
    private fun checkText(text: String) {
        require(text.length <= 256 && text.none { it.code < 32 }) { "工程文本过长或包含控制字符" }
    }
    private fun readInfo(row: JsonObject) = PackInfo(row.string("short"), row.string("display"), row.string("title"), row.string("pkg"))
}
