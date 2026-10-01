package com.chaos.bandpack.ui.theme

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Category
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Compress
import androidx.compose.material.icons.filled.Contrast
import androidx.compose.material.icons.filled.DataUsage
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.FontDownload
import androidx.compose.material.icons.filled.FormatLineSpacing
import androidx.compose.material.icons.filled.FormatSize
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Height
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Numbers
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Pin
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Style
import androidx.compose.material.icons.filled.TaskAlt
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Warning
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.res.painterResource
import com.chaos.bandpack.R

/**
 * 语义图标。
 *
 * 界面**不许**直接写 `Icons.Filled.X` 或 `R.drawable.ic_mc_x` —— 只说要什么**含义**，
 * 由当前风格决定画哪一套：
 *
 *   [ThemeStyle.PAPER]（默认）→ MingCute 的线性图标（`ic_mc_*`，Apache-2.0，见 scripts 里的生成脚本）
 *   [ThemeStyle.MD3]          → Material 那套
 *
 * 这样换风格时图标整套跟着换，而且以后要换第三套图标集，只需要在这张表里加一列。
 *
 * 枚举名取的是**语义**（`SectionPack`、`DeleteSweep`），不是某套图标的名字 ——
 * 名字里带 `Section` 的那几个是分节标题徽标用的，与页面里的同名语义区分开是为了
 * 让"改分节图标"与"改正文图标"互不影响。
 */
enum class ChaosIcon(val mc: Int, val material: androidx.compose.ui.graphics.vector.ImageVector) {
    // 导航
    Home(R.drawable.ic_mc_home, Icons.Filled.Home),
    Font(R.drawable.ic_mc_font, Icons.Filled.FormatSize),
    Grid(R.drawable.ic_mc_grid, Icons.Filled.GridView),
    Settings(R.drawable.ic_mc_settings, Icons.Filled.Settings),

    // 主流程
    Download(R.drawable.ic_mc_download, Icons.Filled.Download),
    Tune(R.drawable.ic_mc_tune, Icons.Filled.Tune),
    Send(R.drawable.ic_mc_send, Icons.AutoMirrored.Filled.Send),
    Save(R.drawable.ic_mc_save, Icons.Filled.Save),

    // 分节徽标
    SectionFont(R.drawable.ic_mc_section_font, Icons.Filled.FontDownload),
    SectionParams(R.drawable.ic_mc_section_params, Icons.Filled.Style),
    SectionPreview(R.drawable.ic_mc_section_preview, Icons.Filled.FormatSize),
    SectionPack(R.drawable.ic_mc_section_pack, Icons.Filled.Inventory2),
    SectionSlots(R.drawable.ic_mc_section_slots, Icons.Filled.GridView),
    SectionAppearance(R.drawable.ic_mc_section_appearance, Icons.Filled.Contrast),
    SectionDefaults(R.drawable.ic_mc_section_defaults, Icons.Filled.Tune),
    SectionAbout(R.drawable.ic_mc_section_about, Icons.Filled.Info),

    // 设置项头图
    Theme(R.drawable.ic_mc_theme, Icons.Filled.Contrast),
    Palette(R.drawable.ic_mc_palette, Icons.Filled.Palette),
    Style(R.drawable.ic_mc_style, Icons.Filled.Compress),
    Charset(R.drawable.ic_mc_charset, Icons.Filled.Compress),
    LineHeight(R.drawable.ic_mc_line_height, Icons.Filled.FormatLineSpacing),
    FontSize(R.drawable.ic_mc_font_size, Icons.Filled.FormatSize),
    Height(R.drawable.ic_mc_height, Icons.Filled.Height),

    // 数据小票
    Pin(R.drawable.ic_mc_pin, Icons.Filled.Pin),
    Size(R.drawable.ic_mc_size, Icons.Filled.DataUsage),
    Chip(R.drawable.ic_mc_chip, Icons.Filled.Memory),
    GridCount(R.drawable.ic_mc_grid_count, Icons.Filled.GridView),
    Flask(R.drawable.ic_mc_flask, Icons.Filled.Science),
    Verified(R.drawable.ic_mc_verified, Icons.Filled.Verified),
    Tag(R.drawable.ic_mc_tag, Icons.Filled.Numbers),
    World(R.drawable.ic_mc_world, Icons.Filled.Language),
    Dashboard(R.drawable.ic_mc_dashboard, Icons.Filled.Category),
    Checklist(R.drawable.ic_mc_checklist, Icons.Filled.Checklist),

    // 其它
    Warning(R.drawable.ic_mc_warning, Icons.Filled.Warning),
    TaskOk(R.drawable.ic_mc_task_ok, Icons.Filled.TaskAlt),
    Check(R.drawable.ic_mc_check, Icons.Filled.Check),
    Close(R.drawable.ic_mc_close, Icons.Filled.Close),
    Image(R.drawable.ic_mc_image, Icons.Filled.Image),
    DeleteSweep(R.drawable.ic_mc_delete_sweep, Icons.Filled.DeleteSweep),
}

/**
 * 把语义图标解成当前风格该用的 painter。
 *
 * 返回 `Painter` 而不是 `ImageVector`：MingCute 那套是 VectorDrawable 资源，
 * Material 那套是代码里的 ImageVector，两条路只有 `Painter` 是共同出口。
 */
@Composable
fun chaosIcon(key: ChaosIcon): Painter = when (LocalThemeStyle.current) {
    ThemeStyle.PAPER -> painterResource(key.mc)
    ThemeStyle.MD3 -> rememberVectorPainter(key.material)
}
