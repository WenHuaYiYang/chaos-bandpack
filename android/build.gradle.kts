allprojects {
    repositories {
        // Flutter 的 release 引擎产物(flutter_embedding_release / arm64_v8a_release)
        // 在 storage.googleapis.com 上, 本机 TLS 经常被 reset, Gradle 会卡在下载不返回。
        // 这两个 artifact 已用 curl 预先取到本地仓库, 放在最前面让 Gradle 直接命中。
        maven { url = uri("file:///C:/Users/YiYang/flutter-maven") }
        // 同 settings.gradle.kts: 先走可达的镜像, 再退回官方源。
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    // 插件子项目(如 file_picker)在自己的 build.gradle 里写死了 buildscript repositories
    // = google() + mavenCentral(), 这两个源在本机不可达。这里在评估前把镜像插到最前面,
    // 让同一批 artifact 走能连通的地址。
    buildscript {
        repositories {
            maven { url = uri("https://maven.aliyun.com/repository/google") }
            maven { url = uri("https://maven.aliyun.com/repository/central") }
            google()
            mavenCentral()
        }
    }
}

subprojects {
    // 本机只能 --offline 构建(google() 不可达), 缓存里只落了 androidx.datastore 1.2.1。
    // shared_preferences_android 默认要 1.1.7, 离线解析必然失败, 这里统一抬到缓存里
    // 已有的版本。datastore 1.2.x 与 1.1.x 的 API 兼容, 插件只是用它存键值。
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group.startsWith("androidx.datastore")) {
                useVersion("1.2.1")
                because("离线构建, 缓存里只有 1.2.1")
            }
        }
    }
}

subprojects {
    // offline 构建缺 com.android.tools.lint:lint-gradle 缓存, 而 AGP 的 lint 任务
    // (以及 :file_picker:extractDebugAnnotations 里对 lintTool 的解析)会去拉它。
    // assembleDebug 不需要 lint, 直接禁用。
    tasks.configureEach {
        // sync*LibJars 是插件 AAR 的发布链任务, 它的输入 typedef 清单来自
        // extractDebugAnnotations(同样依赖 lint-gradle)。装 APK 用不到, 一并关掉。
        val aarPackaging = name.startsWith("sync") && name.endsWith("LibJars")
        // extractDebugAnnotations / extractReleaseAnnotations 都要关: 两个变体各一份,
        // 只关 debug 那份在 assembleRelease 时仍会去拉 lint-gradle 而失败。
        val annotations = name.startsWith("extract") && name.endsWith("Annotations")
        if (aarPackaging ||
            annotations ||
            name.startsWith("lint") ||
            name.contains("Lint")
        ) {
            enabled = false
        }
        // strip 任务不再禁用: 真 NDK(r28c = 28.2.13676358)已装好, llvm-strip 可用。
        // 之前禁用 strip 会让 libflutter.so / libapp.so 根本不进 APK, 那种包装上必崩。
    }
}

subprojects {
    // 插件子项目自带 compileSdk 34/35(file_picker、jni 就是这样), 而本机只解包了
    // android-36: 统一抬到 36。这些插件都是纯 Java 源码, 用 36 编译没有问题。
    // 必须在这里(afterEvaluate)注册, 而且要早于下面的 evaluationDependsOn, 否则 :app
    // 已经被评估过, 注册 afterEvaluate 会直接抛 'project is already evaluated'。
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        val cls = android.javaClass
        val getter = cls.getMethod("getCompileSdkVersion")
        if (getter.invoke(android) != "android-36") {
            cls.getMethod("compileSdkVersion", Int::class.javaPrimitiveType).invoke(android, 36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
