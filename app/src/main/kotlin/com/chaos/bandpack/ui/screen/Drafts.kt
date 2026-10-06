package com.chaos.bandpack.ui.screen

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.chaos.bandpack.data.font.Charset
import com.chaos.bandpack.data.make.FontMake
import com.chaos.bandpack.data.pack.FontPackBuilder
import com.chaos.bandpack.data.pack.IconPackBuilder
import com.chaos.bandpack.ui.theme.UiPrefs

/**
 * 两条制作线的**工作区**。
 *
 * 为什么提到界面外面: 加了底部导航栏之后, 字体页与图标页变成同级标签页, 用户会来回切。
 * 状态如果还留在各自 Composable 里, 一切走再切回来就重新挂载 —— 那份 3 秒才处理完的
 * 字体、调好的参数全没了。标签页必须保状态, 所以工作区由 `ChaosApp` 记住并传进来。
 *
 * 字段用 `by mutableStateOf`, 因此读写它们本身就是快照观察点; 界面侧用
 * `var x by draft::x` 直接转发, 不必把每个引用都改成 `draft.x`。
 */
class FontDraft {
    var srcBytes by mutableStateOf<ByteArray?>(null)
    var srcName by mutableStateOf("")
    var pre by mutableStateOf<FontMake.Precheck?>(null)
    var srcErr by mutableStateOf<String?>(null)

    var label by mutableStateOf("")
    var packName by mutableStateOf("")
    var title by mutableStateOf("")
    var pkgId by mutableStateOf("")
    var nameTouched by mutableStateOf(false)
    var titleTouched by mutableStateOf(false)

    // 起点取自设置页的默认值(新建一条制作线时才读, 之后这条线自己说了算)
    var kind by mutableStateOf(UiPrefs.defaultKind)
    var normalize by mutableStateOf(UiPrefs.defaultNormalize)
    var preserveImported by mutableStateOf(false)

    var made by mutableStateOf<FontMake.Made?>(null)
    var busy by mutableStateOf(false)
    var err by mutableStateOf<String?>(null)

    var pack by mutableStateOf<FontPackBuilder.Result?>(null)
    var savedAs by mutableStateOf<String?>(null)
    var toSave by mutableStateOf<ByteArray?>(null)

    /** 样张字号(sp): 是用户拧出来的偏好, 切标签页不该被重置 */
    var previewSp by mutableStateOf(UiPrefs.defaultPreviewSp)
}

class IconDraft {
    var group by mutableStateOf(com.chaos.bandpack.data.icon.IconSpec.Group.DESKTOP)
    var picked by mutableStateOf<Map<String, ByteArray>>(emptyMap())
    var short by mutableStateOf("MyIcons")
    var packName by mutableStateOf("图标:MyIcons")
    var title by mutableStateOf("图标投递 MyIcons")
    var pkgId by mutableStateOf("")
    var nameTouched by mutableStateOf(false)
    var titleTouched by mutableStateOf(false)

    var busy by mutableStateOf(false)
    var pack by mutableStateOf<IconPackBuilder.Result?>(null)
    var toSave by mutableStateOf<ByteArray?>(null)
    var savedAs by mutableStateOf<String?>(null)
    var pendingStem by mutableStateOf<String?>(null)
}
