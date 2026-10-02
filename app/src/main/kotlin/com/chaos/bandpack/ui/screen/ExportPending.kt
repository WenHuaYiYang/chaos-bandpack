package com.chaos.bandpack.ui.screen

/**
 * 导出字节的中转站。
 *
 * 为什么不继续存在 [FontDraft] / [IconDraft] 里: 导出要跳出 App 去开系统的保存界面,
 * 这一步**允许 Activity 被重建**(转屏、内存回收、开发者选项里的"不保留活动")。
 * 工作区由上层 remember 还活着, 但要写的字节跟着状态一起重建的话, 选完文件回来
 * 回调拿到的是 null, 然后什么都不做 —— 用户看到的就是"点了导出没反应", 连提示都没有。
 *
 * 顺带把**我们建议的文件名**也存进来: SAF 回给 App 的 content URI 的 `lastPathSegment`
 * 往往是媒体库行号(实测显示成"已保存：9"), 自己记名字才是能读的回执。
 *
 * 字节挂在这个进程级对象上: 点导出时放进来, 写盘回调取走并清空(几 MB 不能一直挂着)。
 * 取不到时回调必须**报出来**, 不许静默返回。
 */
object ExportPending {
    data class Pending(val bytes: ByteArray, val name: String)

    @Volatile
    private var pending: Pending? = null

    fun put(data: ByteArray, name: String) {
        pending = Pending(data, name)
    }

    /** 取走并清空: 一次导出只允许被写一次 */
    fun take(): Pending? = pending.also { pending = null }
}
