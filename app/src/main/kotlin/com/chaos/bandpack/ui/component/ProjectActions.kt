package com.chaos.bandpack.ui.component

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.chaos.bandpack.data.Assets
import com.chaos.bandpack.data.displayNameOf
import com.chaos.bandpack.data.project.ChaosProject
import com.chaos.bandpack.data.project.PackBinImport
import com.chaos.bandpack.data.project.ProjectCodec
import com.chaos.bandpack.ui.screen.ExportPending
import com.chaos.bandpack.ui.screen.StudioWorkspace
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 工程级动作(打开文件 / 保存工程 / 取 9 Pro 主包)与它们的即时反馈。
 *
 * 状态挂在应用外壳, 按钮画在首页: 这三件事描述的是"这一份工程"而不是"这一屏",
 * 所以它们跟着工程走而不是跟着标签页走。共享进来的文件必须在任意标签页都被接住,
 * 这也是宿主不能放进首页的原因 —— 首页可能不在组合里。
 */
@Immutable
class ProjectActions(
    val blocked: Boolean,
    val openFile: () -> Unit,
    val saveProject: () -> Unit,
    val saveNineInstaller: () -> Unit,
    val notice: String?,
    val dismissNotice: () -> Unit,
)

@Composable
fun rememberProjectActions(
    workspace: StudioWorkspace,
    incoming: Uri?,
    onConsumed: () -> Unit,
    onImported: (ChaosProject) -> Unit,
): ProjectActions {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var notice by remember { mutableStateOf<String?>(null) }
    val consumed by rememberUpdatedState(onConsumed)
    val imported by rememberUpdatedState(onImported)

    fun open(uri: Uri) {
        scope.launch {
            workspace.busy = true
            try {
                val result = withContext(Dispatchers.IO) {
                    val bytes = ctx.contentResolver.openInputStream(uri)!!.use { stream ->
                        val buffer = java.io.ByteArrayOutputStream(); val part = ByteArray(8192)
                        while (true) { val n = stream.read(part); if (n < 0) break
                            require(buffer.size() + n <= ProjectCodec.MAX_BYTES) { "文件超过 32 MB" }; buffer.write(part, 0, n) }
                        buffer.toByteArray()
                    }
                    val project = bytes.size >= 4 && bytes[0] == 0x50.toByte() && bytes[1] == 0x4b.toByte()
                    (if (project) ProjectCodec.read(bytes) else PackBinImport.read(bytes)) to project
                }
                workspace.apply(result.first, result.second)
                imported(result.first)
                notice = "已打开 ${displayNameOf(ctx, uri) ?: "文件"}。切换设备后即可导出对应投递包，素材保存在同一个工程里。"
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                notice = "导入失败：${e.message}。原工作区未修改。"
            } finally { workspace.busy = false; consumed() }
        }
    }

    val opener = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> uri?.let { open(it) } }
    val saver = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
        val pending = ExportPending.take()
        if (uri != null && pending == null) notice = "保存内容已丢失，请重新点击保存。"
        if (uri != null && pending != null) scope.launch {
            try {
                val savedName = withContext(Dispatchers.IO) {
                    ctx.contentResolver.openOutputStream(uri)!!.use { it.write(pending.bytes) }
                    displayNameOf(ctx, uri) ?: pending.name
                }
                notice = if (pending.name.endsWith(".${ProjectCodec.EXTENSION}"))
                    "已保存：$savedName。工程包含两种设备的素材，之后可重新打开继续编辑。"
                else "已保存：$savedName。这是移植版原始主包，适用 9 Pro 3.1.187。"
            } catch (e: Exception) { notice = "保存失败：${e.message}" }
        }
    }

    LaunchedEffect(incoming) { incoming?.let { open(it) } }

    val blocked = workspace.busy || workspace.icons.busy || workspace.font.busy
    return ProjectActions(
        blocked = blocked,
        openFile = { opener.launch(arrayOf("*/*")) },
        saveProject = {
            scope.launch {
                workspace.busy = true
                try {
                    val snapshot = workspace.snapshot()
                    require(snapshot.icons?.images?.isNotEmpty() == true || snapshot.font != null) { "请先选择图标或字体" }
                    val bytes = withContext(Dispatchers.Default) { ProjectCodec.write(snapshot) }
                    val name = "Chaos工程.${ProjectCodec.EXTENSION}"
                    ExportPending.put(bytes, name)
                    saver.launch(name)
                } catch (e: Exception) { notice = "保存失败：${e.message}" }
                finally { workspace.busy = false }
            }
        },
        saveNineInstaller = {
            runCatching {
                val name = Assets.NINE_INSTALLER_NAME
                ExportPending.put(Assets.nineInstaller(ctx), name); saver.launch(name)
            }.onFailure { notice = "主包读取失败：${it.message}" }
        },
        notice = notice,
        dismissNotice = { notice = null },
    )
}

/** 工程动作的结果与失败提示。挂在应用层, 这样在哪个标签页都能收到。 */
@Composable
fun ProjectNotice(actions: ProjectActions) {
    val message = actions.notice ?: return
    AlertDialog(onDismissRequest = actions.dismissNotice, title = { Text("Chaos 制作台") },
        text = { Text(message) }, confirmButton = { TextButton(onClick = actions.dismissNotice) { Text("知道了") } })
}
