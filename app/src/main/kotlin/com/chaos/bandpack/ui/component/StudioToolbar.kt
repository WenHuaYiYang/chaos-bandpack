package com.chaos.bandpack.ui.component

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.chaos.bandpack.data.Assets
import com.chaos.bandpack.data.DeviceTarget
import com.chaos.bandpack.data.displayNameOf
import com.chaos.bandpack.data.project.*
import com.chaos.bandpack.ui.screen.StudioWorkspace
import com.chaos.bandpack.ui.screen.ExportPending
import kotlinx.coroutines.*

@Composable
fun StudioToolbar(workspace: StudioWorkspace, incoming: android.net.Uri?, onConsumed: () -> Unit,
                  onImported: (ChaosProject) -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var notice by remember { mutableStateOf<String?>(null) }
    val blocked = workspace.busy || workspace.icons.busy || workspace.font.busy
    fun open(uri: android.net.Uri) {
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
                onImported(result.first)
                notice = "已打开 ${displayNameOf(ctx, uri) ?: "文件"}。切换设备后即可导出对应投递包，素材保存在同一个工程里。"
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                notice = "导入失败：${e.message}。原工作区未修改。"
            } finally { workspace.busy = false; onConsumed() }
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
    Column(
        Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
        ) {
            if (workspace.busy) CircularProgressIndicator(Modifier.size(24.dp))
            TextButton(enabled = !blocked, onClick = { opener.launch(arrayOf("*/*")) }) { Text("打开文件") }
            TextButton(enabled = !blocked, onClick = {
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
            }) { Text("保存工程") }
            if (workspace.device == DeviceTarget.NINE_PRO) TextButton(enabled = !blocked, onClick = {
                runCatching {
                    val name = "Chaos-9Pro-3.1.187-v2.1.bin"
                    ExportPending.put(Assets.nineInstaller(ctx), name); saver.launch(name)
                }
                    .onFailure { notice = "主包读取失败：${it.message}" }
            }) { Text("9 Pro 主包") }
        }
    }
    notice?.let { message ->
        AlertDialog(onDismissRequest = { notice = null }, title = { Text("Chaos 制作台") },
            text = { Text(message) }, confirmButton = { TextButton(onClick = { notice = null }) { Text("知道了") } })
    }
}
