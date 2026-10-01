package com.chaos.bandpack.ui.theme

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.mutableStateOf
import com.chaos.bandpack.data.font.Charset

/** 外观模式: 跟随系统 / 强制浅色 / 强制深色 */
enum class Appearance { SYSTEM, LIGHT, DARK }

/**
 * 界面风格。
 *
 *   [PAPER] —— 默认那套: 冷灰底 + 暖白卡 + 粉彩强调 + MingCute 线性图标;
 *   [MD3]   —— 上一版: 整页色场 + 同色系卡片 + Material 图标。
 *
 * 两套共用同一份 `ColorScheme` / `Shapes` / `LocalPageTone` 接口, 所以各页只写一遍,
 * 切风格是换"怎么算这些角色", 不是换一套界面代码。
 */
enum class ThemeStyle { PAPER, MD3 }

/**
 * 界面偏好(主题两项)。
 *
 * 为什么单独一个对象而不是层层传参: 就两个值、全应用读写、要跨重组与进程内重启活着。
 * 走 SharedPreferences 落盘, `mutableStateOf` 让读它的 Composable 自动跟着刷新。
 *
 * `dynamicColor` 单独可关是**品牌纪律**: Material You 按壁纸取色会把品牌蓝整个换掉,
 * 用户想要"就是 Chaos 那套颜色"时必须有关得掉的开关(清单: 动态取色可以接, 品牌色不能丢)。
 */
object UiPrefs {
    private var sp: SharedPreferences? = null

    // 状态放背后的 MutableState, 对外只读 + 显式 setter: 直接写 `var x by mutableStateOf`
    // 会让 Kotlin 生成 setX(), 与下面的具名 setter 撞成同一个 JVM 签名
    private val appearanceState = mutableStateOf(Appearance.SYSTEM)
    private val dynamicState = mutableStateOf(true)
    private val styleState = mutableStateOf(ThemeStyle.PAPER)
    // 底栏文字: 默认关(底栏只有图标, 参照用户给的深墨胶囊图), 要看名字再打开
    private val navLabelsState = mutableStateOf(false)

    /** 读它要在 Composable 里读: getter 取的是 MutableState 的值, 所以会自动跟着刷新 */
    val appearance: Appearance get() = appearanceState.value
    val dynamicColor: Boolean get() = dynamicState.value
    val themeStyle: ThemeStyle get() = styleState.value
    val navLabels: Boolean get() = navLabelsState.value

    fun init(ctx: Context) {
        val p = ctx.applicationContext.getSharedPreferences("chaos_ui", Context.MODE_PRIVATE)
        sp = p
        appearanceState.value = runCatching {
            Appearance.valueOf(p.getString("appearance", null) ?: Appearance.SYSTEM.name)
        }.getOrDefault(Appearance.SYSTEM)
        // 默认就是 PAPER: 老装机没有这个键, 落了空值也走默认
        styleState.value = runCatching {
            ThemeStyle.valueOf(p.getString("theme_style", null) ?: ThemeStyle.PAPER.name)
        }.getOrDefault(ThemeStyle.PAPER)
        dynamicState.value = p.getBoolean("dynamic", true)
        navLabelsState.value = p.getBoolean("nav_labels", false)
        kindState.value = runCatching {
            Charset.Kind.valueOf(p.getString("kind", null) ?: Charset.Kind.SIMPLIFIED.name)
        }.getOrDefault(Charset.Kind.SIMPLIFIED)
        normalizeState.value = p.getBoolean("normalize", true)
        previewSpState.value = p.getFloat("preview_sp", 24f)
    }

    fun setAppearance(v: Appearance) {
        appearanceState.value = v
        sp?.edit()?.putString("appearance", v.name)?.apply()
    }

    fun setThemeStyle(v: ThemeStyle) {
        styleState.value = v
        sp?.edit()?.putString("theme_style", v.name)?.apply()
    }

    fun setDynamicColor(v: Boolean) {
        dynamicState.value = v
        sp?.edit()?.putBoolean("dynamic", v)?.apply()
    }

    fun setNavLabels(v: Boolean) {
        navLabelsState.value = v
        sp?.edit()?.putBoolean("nav_labels", v)?.apply()
    }

    // ===== 制作默认值: 新建一条制作线时按它起头(见 FontDraft) =====

    private val kindState = mutableStateOf(Charset.Kind.SIMPLIFIED)
    private val normalizeState = mutableStateOf(true)
    private val previewSpState = mutableStateOf(24f)

    val defaultKind: Charset.Kind get() = kindState.value
    val defaultNormalize: Boolean get() = normalizeState.value
    val defaultPreviewSp: Float get() = previewSpState.value

    fun setDefaultKind(v: Charset.Kind) {
        kindState.value = v
        sp?.edit()?.putString("kind", v.name)?.apply()
    }

    fun setDefaultNormalize(v: Boolean) {
        normalizeState.value = v
        sp?.edit()?.putBoolean("normalize", v)?.apply()
    }

    fun setDefaultPreviewSp(v: Float) {
        previewSpState.value = v
        sp?.edit()?.putFloat("preview_sp", v)?.apply()
    }
}
