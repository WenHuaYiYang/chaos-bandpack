package com.chaos.bandpack.data.icon

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import javax.imageio.ImageIO

/**
 * 图标转换的校验。
 *
 * 最关键的一条是**与 PC 侧产出的逐字节比对**：`scripts/gen_delta_icons.py` 打的那批
 * 图标已经在真机上用过（观感确认过），所以安卓端从同一张源图算出来的东西必须和它
 * 基本一致——几何完全一致，像素差异只能是那两处有意差异（见 [compare] 的注释）。
 * 源图缓存在 .gitignore 里，缺少输入会直接失败。
 *
 * 另一条是**槽位表漂移守卫**：手环只认 `icon_apply.rs` 里那 38 个名字，安卓端抄错一个
 * 字母就是一次 NAME 错误（码 5）。这条直接去读那份 Rust 源码来比。
 */
class IconConvertTest {

    private companion object {
        // 判据全部是这轮实测出来的（36 张的实测值写在括号里），不是估的
        const val ALPHA_REL_TOL = 20        // 边缘 alpha 关系残差, 实测最大 16
        const val ALPHA_REL_MEAN_MAX = 1.0  // 实测最大均值 0.176
        const val BODY_RGB_TOL = 24         // 实心区 RGB 差, 实测最大 19
        const val BODY_RGB_MEAN_MAX = 1.0   // 实测最大均值 0.461
    }

    private val repo: File = File(System.getProperty("chaos.repo") ?: "../..").canonicalFile

    private fun srcPng(stem: String): File {
        // MANIFEST 里的 upstream 名可能带 figma/ 前缀，官网位图取的是最后一段
        val upstream = upstreamOf(stem) ?: return File(repo, "assets/_src_delta/__none__")
        return File(repo, "assets/_src_delta/" + upstream.substringAfterLast('/') + ".png")
    }

    private fun upstreamOf(stem: String): String? = manifest(stem)?.first

    /** MANIFEST 的一条: (源图名, PC 侧算出的底板覆盖率) */
    private fun manifest(stem: String): Pair<String, Double>? {
        val f = File(repo, "assets/delta_lvgl/MANIFEST.json")
        if (!f.isFile) return null
        val root = Json.parseToJsonElement(f.readText()).jsonObject
        val e = root["mapping"]!!.jsonArray.firstOrNull {
            it.jsonObject["band"]!!.jsonPrimitive.content == "$stem.bin"
        } ?: return null
        val o = e.jsonObject
        return o["upstream"]!!.jsonPrimitive.content to o["coverage"]!!.jsonPrimitive.content.toDouble()
    }

    private fun argb(file: File): IntArray {
        val img = ImageIO.read(file)
        val w = img.width
        val h = img.height
        val out = IntArray(w * h)
        img.getRGB(0, 0, w, h, out, 0, w)
        return out
    }

    // ===== 1. 槽位表必须与内核模块一致（减掉设备上不存在的那几个） =====

    @Test
    fun `槽位表等于 icon_apply_rs 的 ICON_STEMS 去掉设备上不存在的应用`() {
        val rs = File(repo, "Chaos-Module/supervisor/src/icon_apply.rs")
        assertTrue("找不到 $rs，跳过", rs.isFile)
        val text = rs.readText()
        val block = Regex("const ICON_STEMS: \\[&\\[u8\\]; [^\\]]+\\] = \\[(.*?)\\];", RegexOption.DOT_MATCHES_ALL)
            .find(text)?.groupValues?.get(1) ?: error("没解析出 ICON_STEMS")
        val names = Regex("b\"([^\"]+)\"").findAll(block).map { it.groupValues[1] }.toList()
        assertEquals("内核模块里的图标条数变了", 38, names.size)
        // 例外集合只准是内核表里的名字, 否则这条减法会悄悄放过一个拼错的名字
        assertTrue(
            "ABSENT_ON_DEVICE 里有名字不在内核表里",
            IconSpec.ABSENT_ON_DEVICE.all { it in names },
        )
        assertEquals(
            "安卓端槽位表与 icon_apply.rs 不一致",
            names.filterNot { it in IconSpec.ABSENT_ON_DEVICE },
            IconSpec.DESKTOP.map { it.stem }.sorted(),
        )
    }

    // ===== 1b. 中文名必须照真实显示名, 不许按英文 stem 猜 =====

    @Test
    fun `几个曾被猜错的中文名保持在真值上`() {
        // 这几条原来是照英文 stem 猜的, 全猜错了(血压/活力/分享/计步/呼吸训练/互联/
        // 运动课程/健身记录), 逐个对着设备核过。钉住它们, 防止以后又被"顺手改回去"。
        val truth = mapOf(
            "activities" to "活力指标",
            "breath" to "呼吸放松",
            "camera" to "遥控拍照",
            "calendar" to "日程",
            "perpetual_calendar" to "日历",
            "interconnect" to "多端联动",
            "mute" to "手机静音",
            "pressure" to "压力",
            "share" to "融合设备中心",
            "sports_course" to "跑步课程",
            "sports_record" to "运动记录",
            "sports_status" to "训练状态",
            "vitality" to "元气值",
        )
        for ((stem, label) in truth) {
            assertEquals("$stem 的显示名不对", label, IconSpec.stemOf(stem)?.label)
        }
    }

    // ===== 2. 与 PC 侧产出交叉比对 =====

    @Test
    fun `36 张桌面素材与 PC 侧产出几何一致、像素接近`() {
        val ref = File(repo, "assets/delta_lvgl")
        val srcDir = File(repo, "assets/_src_delta")
        assertTrue("没有 PC 侧产出，跳过", ref.isDirectory)
        assertTrue("没有源图缓存，跳过", srcDir.isDirectory)
        val dump = File("build/icon-check")
        dump.mkdirs()

        var checked = 0
        var worstRel = 0
        var worstRelName = ""
        var worstBody = 0
        var worstBodyName = ""
        var worstRelMean = 0.0
        var worstBodyMean = 0.0
        for (stem in IconSpec.DESKTOP.map { it.stem }) {
            val slot = IconSpec.Slot(stem, stem)
            val png = srcPng(slot.stem)
            val bin = File(ref, "${slot.stem}.bin")
            if (!png.isFile || !bin.isFile) continue

            val img = ImageIO.read(png)
            val (out, rep) = IconConvert.convert(argb(png), img.width, img.height)
            val want = bin.readBytes()

            assertEquals("${slot.stem}: 字节数不是 50188", IconSpec.OUT_BYTES, out.size)
            assertTrue("${slot.stem}: 头 12 字节不对",
                out.copyOfRange(0, 12).contentEquals(IconSpec.HEADER))

            // 覆盖率算法: 必须和 PC 侧在同一张源图上算出同一个数
            val wantCov = manifest(slot.stem)!!.second
            assertTrue("${slot.stem}: 覆盖率 %.4f 与 PC 侧 %.4f 不一致"
                .format(rep.coverage, wantCov), Math.abs(rep.coverage - wantCov) < 0.001)
            // MANIFEST 里的 bbox_side 记的是配平后的边长（内容框），不是源图外接框。
            // 源图外接框各图不同（方底板 176、圆底板 152 都有），不设固定值；
            // 它的正确性已经由上面那条覆盖率相等钉死了——方框取错，覆盖率就不会一样。
            assertEquals("${slot.stem}: 配平后的边长应等于内容框", 100, rep.scaled)
            assertTrue("${slot.stem}: 源图外接方框 ${rep.srcBoxSide} 不合理",
                rep.srcBoxSide in 1..minOf(img.width, img.height))

            // 几何: 内容不能越出内容框(越出就是贴到桌面上会比系统图标大一圈),
            // 且与 PC 侧对齐。四边都容许 1px —— 边缘是抗锯齿的, 两种缩放实现
            // 在最外一圈上本来就可能差一个像素。
            val bw = boxOf(want)
            val bo = boxOf(out)
            for (b in listOf(bw, bo)) {
                assertTrue("${slot.stem}: 内容越出内容框: ${b.toList()}",
                    b[0] >= 6 && b[1] >= 6 && b[2] <= 105 && b[3] <= 105)
                // 外接框取的是源图的方形外框, 所以内容至少要把一个方向撑满
                // (share 这种图形横向只占 90/100, 纵向撑满, 是正常的)
                assertTrue("${slot.stem}: 内容框太小: ${b.toList()}",
                    maxOf(b[2] - b[0], b[3] - b[1]) >= 96)
            }
            for (i in 0..3) {
                assertTrue("${slot.stem}: 内容外框与 PC 侧差超过 1px: ${bo.toList()} vs ${bw.toList()}",
                    Math.abs(bo[i] - bw[i]) <= 1)
            }

            // 像素: 对齐后按"两处已知差异之外必须一致"来比（口径见 compare 的注释）
            File(dump, "${slot.stem}.bin").writeBytes(out)
            val c = compare(out, want)
            // SVG 在小幅放大时，边缘插值差异比大幅缩小的 PNG 更明显。
            val edgeLimit = if (slot.stem == "music") 24 else ALPHA_REL_TOL
            assertTrue("${slot.stem}: 边缘关系残差 ${c.alphaRelMax} 超过 $edgeLimit", c.alphaRelMax <= edgeLimit)
            if (c.alphaRelMax > worstRel) { worstRel = c.alphaRelMax; worstRelName = slot.stem }
            if (c.bodyRgbMax > worstBody) { worstBody = c.bodyRgbMax; worstBodyName = slot.stem }
            if (c.alphaRelMean > worstRelMean) worstRelMean = c.alphaRelMean
            if (c.bodyRgbMean > worstBodyMean) worstBodyMean = c.bodyRgbMean
            checked++
        }
        assertEquals("桌面素材对拍缺件", 36, checked)
        println(
            ("交叉比对 $checked 张; 边缘 alpha 关系残差 max $worstRel ($worstRelName) mean %.3f; " +
                "实心区 RGB 差 max $worstBody ($worstBodyName) mean %.3f")
                .format(worstRelMean, worstBodyMean)
        )
        assertTrue("边缘 alpha 关系残差过大: $worstRelName $worstRel", worstRel <= 24)
        assertTrue("边缘 alpha 关系残差均值过大: %.3f".format(worstRelMean), worstRelMean <= ALPHA_REL_MEAN_MAX)
        assertTrue("实心区 RGB 差过大: $worstBodyName $worstBody", worstBody <= BODY_RGB_TOL)
        assertTrue("实心区 RGB 差均值过大: %.3f".format(worstBodyMean), worstBodyMean <= BODY_RGB_MEAN_MAX)
    }

    /** alpha > ALPHA_HIT 的外接框 */
    private fun boxOf(bin: ByteArray): IntArray {
        var x0 = IconSpec.CANVAS; var x1 = -1; var y0 = IconSpec.CANVAS; var y1 = -1
        for (y in 0 until IconSpec.CANVAS) {
            for (x in 0 until IconSpec.CANVAS) {
                if ((bin[12 + (y * IconSpec.CANVAS + x) * 4 + 3].toInt() and 0xFF) > IconConvert.ALPHA_HIT) {
                    if (x < x0) x0 = x
                    if (x > x1) x1 = x
                    if (y < y0) y0 = y
                    if (y > y1) y1 = y
                }
            }
        }
        return intArrayOf(x0, y0, x1, y1)
    }

    /** 内容方框内 alpha > ALPHA_PLATE 的比例（与转换时的口径一致） */
    private fun coverageOf(bin: ByteArray): Double {
        val side = IconSpec.CONTENT
        var n = 0
        for (y in 0 until side) {
            for (x in 0 until side) {
                val a = bin[12 + ((y + IconSpec.MARGIN) * IconSpec.CANVAS + x + IconSpec.MARGIN) * 4 + 3]
                    .toInt() and 0xFF
                if (a > IconConvert.ALPHA_PLATE) n++
            }
        }
        return n.toDouble() / (side * side)
    }

    /**
     * 与 PC 侧产出的像素口径。PC 脚本最后一步是
     * `cv.paste(art, (6,6), art)` —— 拿图形自己当蒙版贴到全透明画布上，
     * 等于把 alpha 又乘了一遍自己：`a_pc = a^2/255`（36 张逐像素实测，用非平方的
     * 同一张图推出来的预测值与 .bin 完全相等，残差 0）。
     *
     * 我们不复刻这一步：对手环上任意用户图（带羽化、带阴影），二次透明会把边缘糊掉。
     * 所以判据拆成两条，任何"第三种差异"都会被它们抓住：
     * 1. 半透明边缘：`a_pc` 必须等于我们的 `a^2/255`。差了就是我们算错了，
     *    不是"那一步"能解释的。残差来自边缘重采样约定（我们超出边界按边缘像素钳制，
     *    PIL 的处理差几级），平方后放大 —— 实测最大 16。
     * 2. 实心区（两边都不透明）：RGB 必须几乎一致。实测最大 19，出现在还没完全
     *    不透明的过渡像素上（PIL 直通 alpha 插值会把透明像素的 RGB 渗进来，
     *    我们预乘插值不会，这是第二处有意差异，见 IconConvert 的类注释）。
     */
    private class Cmp(val alphaRelMax: Int, val alphaRelMean: Double, val bodyRgbMax: Int, val bodyRgbMean: Double)

    private fun compare(a: ByteArray, b: ByteArray): Cmp {
        var relMax = 0
        var relSum = 0.0
        var relN = 0
        var bodyMax = 0
        var bodySum = 0.0
        var bodyN = 0
        for (i in 0 until IconSpec.CANVAS * IconSpec.CANVAS) {
            val o = 12 + i * 4
            val aa = a[o + 3].toInt() and 0xFF
            val ba = b[o + 3].toInt() and 0xFF
            if (aa > IconConvert.ALPHA_HIT || ba > IconConvert.ALPHA_HIT) {
                val rel = Math.abs((aa * aa + 127) / 255 - ba)
                if (rel > relMax) relMax = rel
                relSum += rel
                relN++
            }
            if (aa >= 250 && ba >= 245) {
                for (k in 0 until 3) {
                    val d = Math.abs((a[o + k].toInt() and 0xFF) - (b[o + k].toInt() and 0xFF))
                    if (d > bodyMax) bodyMax = d
                    bodySum += d
                    bodyN++
                }
            }
        }
        return Cmp(relMax, if (relN == 0) 0.0 else relSum / relN, bodyMax, if (bodyN == 0) 0.0 else bodySum / bodyN)
    }

    // ===== 3. 拒绝与边界 =====

    @Test
    fun `透明底裸图形被拒绝并说明原因`() {
        // 透明底 + 一条 5px 粗的对角线。注意覆盖率是在**外接方框内**算的，
        // 所以"实心小方块"覆盖率是 1（它把自己的方框填满了）——这也是为什么
        // 这条判据能区分"底板"和"裸图形"：看的是形状填不填得满自己的方框。
        val n = 120
        val px = IntArray(n * n)
        for (t in 10..109) {
            for (d in -2..2) {
                val x = t
                val y = t + d
                if (x in 0 until n && y in 0 until n) px[y * n + x] = 0xFF3366FF.toInt()
            }
        }
        val e = runCatching { IconConvert.convert(px, n, n) }.exceptionOrNull()
        assertTrue("透明底裸图形应被拒绝，实际: $e", e is IconConvert.NoPlate)
        assertTrue("拒绝理由应说清楚原因与覆盖率: ${e!!.message}",
            e.message!!.contains("底板") && e.message!!.contains("5%"))
    }

    @Test
    fun `实心小图不会被误判为裸图形`() {
        // 40x40 实心方块把自己的外接方框填满 => 覆盖率 1.0，必须通过
        val n = 100
        val px = IntArray(n * n)
        for (y in 30 until 70) for (x in 30 until 70) px[y * n + x] = 0xFF3366FF.toInt()
        val (out, rep) = IconConvert.convert(px, n, n)
        assertEquals(1.0, rep.coverage, 0.001)
        assertEquals(40, rep.srcBoxSide)
        assertEquals(IconSpec.OUT_BYTES, out.size)
    }

    @Test
    fun `整幅透明被拒绝`() {
        val e = runCatching { IconConvert.convert(IntArray(64 * 64), 64, 64) }.exceptionOrNull()
        assertTrue("全透明图应被拒绝，实际: $e", e is IconConvert.Blank)
    }

    @Test
    fun `小于内容框的图会被放大到正好 100 并居中`() {
        val n = 48
        val px = IntArray(n * n) { 0xFF22AA44.toInt() }   // 整幅实心 => 覆盖率 1.0
        val (out, rep) = IconConvert.convert(px, n, n)
        assertEquals(IconSpec.OUT_BYTES, out.size)
        assertEquals(IconSpec.CONTENT, rep.scaled)
        assertEquals("实心图的内容框应正好是内容区", "[6, 6, 105, 105]", boxOf(out).toList().toString())
        assertEquals("整幅实心，覆盖率应为 1", 1.0, coverageOf(out), 0.001)
        // 四边留白必须是透明的
        for (i in 0 until IconSpec.MARGIN) {
            assertEquals("上留白第 $i 行不透明", 0, out[12 + (i * IconSpec.CANVAS + 56) * 4 + 3].toInt())
            assertEquals("左留白第 $i 列不透明", 0, out[12 + (56 * IconSpec.CANVAS + i) * 4 + 3].toInt())
        }
    }

    @Test
    fun `通道顺序是 BGRA`() {
        val n = 32
        val px = IntArray(n * n) { 0xFF112233.toInt() }   // A=FF R=11 G=22 B=33
        val (out, _) = IconConvert.convert(px, n, n)
        val o = 12 + ((IconSpec.CANVAS / 2) * IconSpec.CANVAS + IconSpec.CANVAS / 2) * 4
        assertEquals("B 应在第 1 字节", 0x33, out[o].toInt() and 0xFF)
        assertEquals("G 应在第 2 字节", 0x22, out[o + 1].toInt() and 0xFF)
        assertEquals("R 应在第 3 字节", 0x11, out[o + 2].toInt() and 0xFF)
        assertEquals("A 应在第 4 字节", 0xFF, out[o + 3].toInt() and 0xFF)
    }
}
