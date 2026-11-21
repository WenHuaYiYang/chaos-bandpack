#!/bin/bash
# Chaos 制作台 — Android 构建脚本
#
# 本机条件(踩过的坑都固化在这里):
#   1. dl.google.com / maven.google.com 不可达 → 仓库走阿里云镜像, 且必须 --offline
#   2. SDK 是手动解包的 → 写死 buildToolsVersion, 并传 -Pflutter.androidSdkRoot
#   3. NDK 从腾讯镜像下的 r28c(= 28.2.13676358) → 传 -Pflutter.installedNdkVersions
#      让 Flutter 的 Gradle 插件认为 NDK 已装, 不走它那条假 CMake 通道; 同时 strip 需要真的 llvm-strip
#   4. 离线缓存里只有 arm64 的引擎 → 只构建 android-arm64
#   5. Flutter 的 release 引擎 artifact 走本地 maven 仓库(C:/Users/YiYang/flutter-maven),
#      见 android/build.gradle.kts 的 allprojects.repositories

set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-debug}"   # debug | release

SDK_ROOT="${ANDROID_SDK_ROOT:-C:/Users/YiYang/AppData/Local/Android/Sdk}"
NDK_VER="28.2.13676358"

case "$MODE" in
  debug)   TASK=assembleDebug ;;
  release) TASK=assembleRelease ;;
  *) echo "用法: tool/build_apk.sh [debug|release]" >&2; exit 2 ;;
esac

cd android
./gradlew "$TASK" \
  --offline \
  --console=plain \
  -Ptarget-platform=android-arm64 \
  -Pflutter.androidSdkRoot="$SDK_ROOT" \
  -Pflutter.installedNdkVersions="$NDK_VER"

cd ..
echo
ls -la build/app/outputs/flutter-apk/*.apk 2>/dev/null || echo "没有产出 APK"
