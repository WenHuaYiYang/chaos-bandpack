// Chaos —— 手环投递包制作 App(字体投递表盘 / 图标投递表盘)
// 版本基准对齐本机已验证可用的组合: AGP 9.4.1 / Kotlin 2.4.20 / Compose BOM 2026.09.00
pluginManagement {
    repositories {
        // 国内直连 dl.google.com / repo1.maven.org 经常读超时, 镜像放前面
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        google {
            mavenContent {
                includeGroupAndSubgroups("androidx")
                includeGroupAndSubgroups("com.android")
                includeGroupAndSubgroups("com.google")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google {
            mavenContent {
                includeGroupAndSubgroups("androidx")
                includeGroupAndSubgroups("com.android")
                includeGroupAndSubgroups("com.google")
            }
        }
        mavenCentral()
    }
}

rootProject.name = "Chaos"
include(":app")
