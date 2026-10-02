import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.KotlinBaseExtension
import org.jetbrains.kotlin.gradle.plugin.KotlinBasePlugin

plugins {
    // AGP 9 起 Kotlin 支持已内置, 再套 org.jetbrains.kotlin.android 会直接被拒
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose.compiler)
}

// ===== 设备侧仓库 =====
//
// 这个 App 只做"打包", 打包要的三样东西都在设备侧: 内核模块 chaos_sup.ko、应用图标
// chaos_icon.bin、两个投递 Lua。它们**不随本仓库发布**(前两个是设备侧构建出来的产物),
// 所以构建前要先准备一份设备侧仓库, 位置按下面的顺序找:
//
//   1. -Pchaos.repo=<路径>
//   2. local.properties 里的 chaos.repo=<路径>
//   3. 环境变量 CHAOS_REPO
//   4. 默认 ../../Chaos-Module(把设备侧仓库放在 App 仓库的邻居位置)
//
// 两种目录形状都认: 设备侧工程根(里面还有一层 Chaos-Module/)与已发布的设备仓库根
// (supervisor/ 与 installer/ 就在这一层)。准备方法见 README「构建前提」。
val chaosRepoProp: String? = (findProperty("chaos.repo") as String?)
    ?: rootProject.file("local.properties").takeIf { it.exists() }?.let { f ->
        Properties().apply { f.inputStream().use { load(it) } }.getProperty("chaos.repo")
    }
    ?: System.getenv("CHAOS_REPO")

val chaosRepoDir = file(chaosRepoProp ?: "../../Chaos-Module")

/** 在两种目录形状里找一个设备侧文件 */
fun deviceSource(vararg rel: String): File? {
    val tail = rel.joinToString("/")
    return listOf(File(chaosRepoDir, "Chaos-Module"), chaosRepoDir)
        .map { File(it, tail) }
        .firstOrNull { it.isFile }
}

/**
 * 系统原图标: 从固件资源包解出来那批图(手环桌面上那些应用原本长什么样),
 * 图标页的空槽位与首页的预览都指望它 —— 默认带上。
 *
 * 素材**不进本仓库**: 构建时从设备侧仓库的 `sys_icons/stock` 同步进来, 也就是说只有
 * 手上有固件资源、自己解过的人打出来的包才有这批图。没有那份素材的构建(公开仓库 / CI)
 * 这里必然是空目录, 界面自动退成"未内置" —— 这批图不会由本仓库再分发出去, 只作本地对照。
 * 想显式排除时用 `-Pchaos.stockIcons=false`。来源与授权限制见 `THIRD_PARTY_NOTICES.md`。
 */
val stockIconsEnabled = (findProperty("chaos.stockIcons") as String?)?.toBoolean() ?: true

// 自签发布密钥: 口令与 jks 都不进仓库(见 android/.gitignore)。
// 文件不在时 release 退成"未签名", 这样换机器/CI 仍能构建, 只是产物要自己签。
val keystoreProps = Properties().apply {
    val f = rootProject.file("keystore.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

// 打包素材落在这里, 再用字符串路径挂进 assets(AGP 9 不让往 SourceSet 塞 Provider)
val packAssetsDir = layout.buildDirectory.dir("pack-assets")

/**
 * 同步打包素材。**缺什么不在这里失败**: 单元测试不需要这些素材, 构建也不该因为
 * 没准备设备侧仓库就跑不了 `test`。硬门在 [checkPackAssets], 只拦 release 打包。
 */
val syncPackAssets by tasks.registering {
    group = "chaos"
    description = "把设备侧仓库的 ko / 应用图标 / 投递 Lua 同步进 assets"
    val dest = packAssetsDir.map { it.dir("pack") }
    outputs.dir(dest)
    doLast {
        val dir = dest.get().asFile
        dir.deleteRecursively()
        dir.mkdirs()
        val wanted = linkedMapOf(
            "chaos_sup.ko" to deviceSource("supervisor", "chaos_sup.ko"),
            "chaos_icon.bin" to deviceSource("chaos_icon.bin"),
            "font_pack.lua" to deviceSource("installer", "font_pack.lua"),
            "icon_pack.lua" to deviceSource("installer", "icon_pack.lua"),
        )
        val missing = wanted.filterValues { it == null }.keys
        wanted.forEach { (name, src) -> src?.copyTo(File(dir, name), overwrite = true) }
        if (missing.isEmpty()) {
            logger.lifecycle("打包素材已同步: ${dir.absolutePath} (来自 ${chaosRepoDir.absolutePath})")
        } else {
            logger.warn(
                "缺少打包素材 $missing —— 设备侧仓库没找到/没构建(${chaosRepoDir.absolutePath})。" +
                    "debug 与单元测试仍可跑, release 会被 checkPackAssets 拦下; 准备方法见 README「构建前提」。",
            )
        }

        val stockDest = packAssetsDir.get().dir("stock_icons").asFile
        stockDest.deleteRecursively()
        if (stockIconsEnabled) {
            val stockDir = listOf(
                File(chaosRepoDir, "../sys_icons/stock"),
                File(chaosRepoDir, "sys_icons/stock"),
            ).map { it.canonicalFile }.firstOrNull { it.isDirectory }
            val pngs = stockDir?.listFiles { f -> f.extension == "png" }.orEmpty()
            if (pngs.isEmpty()) {
                logger.warn("chaos.stockIcons=true 但没找到系统原图标素材(${stockDir ?: "目录不存在"})")
            } else {
                stockDest.mkdirs()
                pngs.forEach { it.copyTo(File(stockDest, it.name), overwrite = true) }
                logger.lifecycle("系统原图标已同步: ${pngs.size} 张")
            }
        }
    }
}

/**
 * 许可文本同步: 仓库根的 `THIRD_PARTY_NOTICES.md` 与 `third_party/` 打进 `assets/legal/`,
 * 应用内"开源许可"页直接读它们 —— 单一来源, 不在 assets 里另存一份拷贝。
 *
 * 这一条不是可选的: MiSans 的许可要求"在软件中特别注明使用了 MiSans 字体",
 * 只写在仓库里对已经装了 App 的人不算履行。
 */
val syncLegalAssets by tasks.registering(Sync::class) {
    group = "chaos"
    description = "把许可与第三方声明同步进 assets/legal"
    from(rootProject.file("THIRD_PARTY_NOTICES.md"))
    from(rootProject.file("PRIVACY_POLICY.md")) { rename { "privacy_policy.md" } }
    from(rootProject.file("third_party")) { into("third_party") }
    into(layout.buildDirectory.dir("legal-assets/legal"))
}

/** release 打包的硬门: 素材不齐就**不许**出包 —— 装上了却打不出包的 App 比构建失败更糟 */val checkPackAssets by tasks.registering {
    group = "chaos"
    description = "release 前检查打包素材是否齐全"
    doLast {
        val dir = packAssetsDir.get().dir("pack").asFile
        val need = listOf("chaos_sup.ko", "chaos_icon.bin", "font_pack.lua", "icon_pack.lua")
        val missing = need.filterNot { File(dir, it).isFile }
        if (missing.isNotEmpty()) {
            throw GradleException(
                "打包素材缺失: $missing\n" +
                    "设备侧仓库位置: ${chaosRepoDir.absolutePath}(可用 -Pchaos.repo=<路径> 指定)\n" +
                    "准备方法见 README「构建前提」: 先在设备侧仓库构建出 chaos_sup.ko 与 chaos_icon.bin。",
            )
        }
    }
}

// 用本机 JDK 21 当 Kotlin/Java 的统一工具链
plugins.withType<KotlinBasePlugin> {
    extensions.configure<KotlinBaseExtension> {
        jvmToolchain(21)
    }
}

android {
    namespace = "com.chaos.bandpack"

    // AGP 9 的新写法: compileSdk 37(本机已装), targetSdk 36 = Android 16
    compileSdk {
        version = release(37)
    }

    defaultConfig {
        applicationId = "com.chaos.bandpack"
        minSdk = 26          // 通知 + Compose + SAF 都够; 再低没有实际用户
        targetSdk = 36       // Android 16
        versionCode = 2
        versionName = "1.1.0"
    }

    buildFeatures {
        buildConfig = true
    }

    // 打包素材与许可文本在构建目录里生成, 挂成 assets 源目录(源树里不留副本)
    sourceSets["main"].assets.srcDir(packAssetsDir.get().asFile)
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("legal-assets").get().asFile)

    signingConfigs {
        if (keystoreProps.isNotEmpty()) {
            create("release") {
                // storeFile 相对 android/ 工程根写(密钥就放在 keystore/ 里)
                storeFile = rootProject.file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 打包器与字体解析的线上堆栈必须可读, 等链路稳定再开混淆
            isMinifyEnabled = false
            keystoreProps.getProperty("storeFile")?.let {
                signingConfig = signingConfigs.findByName("release")
            }
        }
    }
}

// 同步素材与许可文本跟着每次构建走(素材缺失只是警告); release 打包前素材必须齐全
tasks.named("preBuild") { dependsOn(syncPackAssets, syncLegalAssets) }

// 单元测试里那几组"与设备侧对拍"的用例按 system property 找设备侧仓库 ——
// -Pchaos.repo 是 Gradle 的**工程属性**, 不传下去测试 JVM 是看不见的(会静默退回默认路径
// 然后全部按 assume 跳过, 看起来"全绿"其实一条都没验)。
tasks.withType<Test>().configureEach {
    systemProperty("chaos.repo", chaosRepoDir.absolutePath)
}
tasks.matching { it.name == "preReleaseBuild" || it.name == "assembleRelease" }.configureEach {
    dependsOn(checkPackAssets)
}

dependencies {
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.foundation)
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.util)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.animation)
    implementation(libs.material3)
    implementation(libs.icons.core)
    implementation(libs.icons.extended)
    implementation(libs.material3.window.size)

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.documentfile)
    implementation(libs.kotlinx.coroutines.android)

    // 字体子集化 / 图标转换 / 投递包容器都是纯 JVM 逻辑(不碰 android.*), 单测跑在桌面 JVM
    testImplementation(libs.junit)
    // 单测要读 PC 侧产出的 MANIFEST.json 做交叉比对
    testImplementation(libs.kotlinx.serialization.json)
    // 只为离线生成配色(官方 MCU 算法)并留下可重跑的记录, 运行时不依赖它
    testImplementation(libs.mcu)
}
