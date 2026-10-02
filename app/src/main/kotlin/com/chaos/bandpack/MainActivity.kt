package com.chaos.bandpack

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import androidx.compose.runtime.CompositionLocalProvider
import com.chaos.bandpack.data.Incoming
import com.chaos.bandpack.ui.component.PrivacyConsentGate
import com.chaos.bandpack.ui.theme.ChaosTheme
import com.chaos.bandpack.ui.theme.UiPrefs
import com.chaos.bandpack.ui.ChaosApp
import com.chaos.bandpack.ui.LocalWidthClass
import com.chaos.bandpack.ui.WidthClass

@OptIn(androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi::class)
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 16 起强制 edge-to-edge: 内容画到系统栏下面, 由各页自己吃 WindowInsets
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // "用 Chaos 打开"/分享进来时, 先收下这个文件(界面消费一次后清掉)
        Incoming.from(intent)?.let { Incoming.uri = it }
        // 主题偏好要在第一个 Composable 读它之前落好
        UiPrefs.init(applicationContext)
        setContent {
            // 按窗口宽度档位自适应(紧凑/中等/宽屏): 列数、边距、是否分栏都跟着它走
            val wsc = calculateWindowSizeClass(this).widthSizeClass
            val width = when (wsc) {
                WindowWidthSizeClass.Expanded -> WidthClass.EXPANDED
                WindowWidthSizeClass.Medium -> WidthClass.MEDIUM
                else -> WidthClass.COMPACT
            }
            if (!UiPrefs.privacyAgreed) {
                // 首启隐私同意: 未同意前不渲染任何业务界面(先告知、先同意, 不同意可退出)。
                // 放在 setContent 这层而不是 ChaosApp 内部: 同意门不需要窗口档位, 也避免在
                // 非 inline 的主题 lambda 里提前 return。
                ChaosTheme {
                    PrivacyConsentGate(onAgree = { UiPrefs.setPrivacyAgreed(true) })
                }
            } else {
                CompositionLocalProvider(LocalWidthClass provides width) {
                    ChaosApp()
                }
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        Incoming.from(intent)?.let { Incoming.uri = it }
    }
}