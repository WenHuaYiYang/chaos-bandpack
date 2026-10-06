package com.chaos.bandpack.ui.screen

import androidx.compose.runtime.*
import com.chaos.bandpack.data.DeviceTarget
import com.chaos.bandpack.data.font.Charset
import com.chaos.bandpack.data.make.FontMake
import com.chaos.bandpack.data.project.*

class StudioWorkspace(val icons: IconDraft, val font: FontDraft) {
    var device by mutableStateOf(DeviceTarget.TEN_PRO)
    var busy by mutableStateOf(false)

    fun selectDevice(target: DeviceTarget) {
        if (device == target) return
        icons.pack = null; icons.savedAs = null; icons.toSave = null; icons.pendingStem = null
        font.pack = null; font.savedAs = null; font.toSave = null
        if (target == DeviceTarget.TEN_PRO && icons.group == com.chaos.bandpack.data.icon.IconSpec.Group.SYSTEM) {
            icons.group = com.chaos.bandpack.data.icon.IconSpec.Group.DESKTOP
        }
        device = target
    }

    fun snapshot(): ChaosProject = ChaosProject(device,
        IconProject(PackInfo(icons.short, icons.packName, icons.title, icons.pkgId), icons.picked),
        font.srcBytes?.let { FontProject(PackInfo(font.label, font.packName, font.title, font.pkgId),
            font.srcName, it, font.kind.name, font.normalize, font.preserveImported) })

    fun apply(project: ChaosProject, replace: Boolean) {
        val checked = project.font?.let { FontMake.precheck(it.source) }
        val charset = project.font?.let { Charset.Kind.valueOf(it.charset) }
        if (replace) {
            icons.picked = emptyMap(); font.srcBytes = null; font.pre = null; font.made = null
            font.srcName = ""; font.label = ""; font.packName = ""; font.title = ""; font.pkgId = ""
        }
        project.icons?.let { source ->
            icons.picked = source.images; icons.short = source.info.short; icons.packName = source.info.display
            icons.title = source.info.title; icons.pkgId = source.info.pkg
            icons.nameTouched = true; icons.titleTouched = true
        }
        project.font?.let { source ->
            font.srcBytes = source.source; font.srcName = source.sourceName
            font.label = source.info.short; font.packName = source.info.display; font.title = source.info.title; font.pkgId = source.info.pkg
            font.nameTouched = true; font.titleTouched = true
            font.kind = charset!!; font.normalize = source.normalize; font.preserveImported = source.preserve
            font.pre = checked; font.made = null
        }
        font.srcErr = null; font.err = null; font.pack = null; font.savedAs = null
        icons.pack = null; icons.savedAs = null; icons.pendingStem = null
        device = project.device
    }
}
