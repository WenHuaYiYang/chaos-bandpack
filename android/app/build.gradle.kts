plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.chaos.chaos_bandpack"
    compileSdk = flutter.compileSdkVersion
    // 本机 SDK 是手动解包的(没有 package.xml), AGP 的自动补装认不出来, 会去远端
    // 拉清单并卡住。写死已解包的这版, 直接用它。
    buildToolsVersion = "36.0.0"
    // 本工程没有原生代码, 但 Flutter 的 Gradle 插件在 ndkVersion 为空时会塞一条
    // 假的 externalNativeBuild.cmake(只为骗 AGP 去下载 NDK), 那条通道要用真的
    // NDK 工具链。本机 dl.google.com 不可达, NDK 是从腾讯镜像下的 r28c, 所以这里
    // 显式写死版本, 并由构建命令传 -Pflutter.installedNdkVersions 让插件认为它已
    // 安装, 从而完全不走 CMake。strip 任务需要这个 NDK 里的 llvm-strip。
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.chaos.chaos_bandpack"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
