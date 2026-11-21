# Chaos 同步器

在 Windows 或 Android 上制作字体和图标，保存为 Chaos 专属美化包（`.chp`），
或经 **ChaosConnect v1** 的经典蓝牙直接同步到手环，不必再生成投递表盘。

这是 Kotlin 版 [chaos-bandpack](../chaos-bandpack) 的 Flutter 重写: 打包链路与 PC 脚本
逐字节一致, 动效更强, 默认主题还原 Paper 那套。

## 能做什么

底栏四格: 首页 / 资源商店 / 设置 / 设备。字体页与图标页是干完就走的活, 从首页卡片推入,
占底栏会把常用的四个入口挤掉。

| 页面 | 能力 |
| --- | --- |
| 首页 | 字体制作、图标制作、打开美化包、连接手环、打开／保存工程 |
| 字体制作 | 子集化和预览，导出独立字体 `.chp` 或直接同步 |
| 图标制作 | 按槽位制作静态或动态图标，导出独立图标 `.chp` 或直接同步 |
| 资源商店 | 空白页, 卖什么还没定 |
| 设置 | 外观(跟随系统/浅色/深色)、界面风格(纸片/色场)、导航文字开关、液态玻璃底栏、制作默认值 |
| 设备 | 列已配对设备、主动搜附近设备并就地配对、连 SPP、看能力位与权限、开发者模式 |
| 文件 | 浏览手环目录、下载单个文件或整目录(录像)、上传、新建目录、重命名、删除 |
| 安装资源包 | 直接选一份 `.chp` 安装到手环空闲槽位 |
| NSH 终端 | 全屏终端，解释 ANSI 颜色与擦行，支持 Ctrl+C 和清屏 |

宽屏（≥900 逻辑像素）把底栏换成左侧导航栏，可收起成图标条；设置里能把底栏切成
苹果 iOS 那种液态玻璃，默认仍是原来的纸片底栏。

- [`.chp` 美化包](docs/CHAOS-PACK-V1.md)：一份只能是字体或图标，含目标机型与资源校验信息。
- `.chaosproj`：可继续编辑的工程，格式不变。
- 旧投递表盘 `.bin`：从「打开工程」导入，制作页也保留兼容导出。

美化包可按 10 Pro 或 9 Pro 的资源规格生成。首版直传仅开放给支持 ChaosConnect 资源安装的
10 Pro；9 Pro 仍可走旧投递表盘。资源经手环确认和校验后安装到空闲槽位，不自动切换。

## 通信

```
手机 ──经典蓝牙 SPP/RFCOMM── 手环
      UUID 43434e31-0001-4a10-8000-4348414f5301, 通道 19

      u32LE 长度 + WearPacket(protobuf 包裹)
        └─ ChaosConnect 帧: 'CCN1' + 版本 + flags + op + status + req + len + payload + CRC-32
             └─ 16 字节帧头, 单块 ≤ 2048 字节, 8 块在途
```

帧头里的 `req` 不是独立自增的请求号 —— 固件拿它去比外层 WearPacket `packet id` 的低 16 位,
对不上就整帧静默丢弃, 连 HELLO 都不回。所以一次请求只分配一个 id, `req = id & 0xFFFF`
(`lib/protocol/cc_client.dart` 的 `_allocIds`)。

协议细节见 Chaos-Module 仓库的 `docs/CHAOSCONNECT-ANDROID.md`。本仓库的 Dart 实现在
`lib/protocol/`(帧编解码, 有金标准 hex 向量对拍)与 `lib/chaos/`(文件引擎、投递包、NSH)。

**载波是自己写的 MethodChannel**, 不走 `flutter_bluetooth_serial` —— 那个包把 UUID 写死成
SPP 默认值, 连不上手环的私有服务。两端同名同语义(方法 `adapter` / `permissions` /
`bonded` / `discover` / `pair` / `connect` / `send` / `close`, 回调 `chunk` / `closed`):

- Android: `android/app/src/main/kotlin/com/chaos/chaos_bandpack/MainActivity.kt`
- Windows: `windows/runner/spp_channel.cc`(WinSock 的 `AF_BTH` / RFCOMM)。

Windows 优先用服务 UUID 查 SDP；未发现该服务、握手前被拒绝或等待超出第一阶段的预算时，
只回退到当前固件的 ChaosConnect 专用通道 19，不试原厂串口或相机服务。
两个串口尝试共用 24 秒等待预算；设备页会把打开串口和等待 HELLO 分开显示，两步都可取消。
握手后，空闲时发 PING 续期，避免手环在 15 秒无有效请求后清掉会话、蓝牙却仍显示已连接。
失联后同步器释放旧串口，可以直接点「重连」，不会重发之前的写入或终端命令。
终端返回 BUSY 则只是手环终端正忙，不会因此关闭文件连接。

`bonded` 只读系统确认已配对的设备，不发无线信号；`discover` 才主动扫描附近设备。
Windows 的临时蓝牙连接并不等于配对，系统确认绑定后设备才会列入「已配对」。
首次配对须在手环上点「发起蓝牙配对」，页面常亮不会延长 60 秒的配对窗口。

## 目录

```
lib/
  protocol/   CRC-32、CCN1 帧、WearPacket protobuf、帧链路、客户端
  chaos/      SPP 载波、会话、文件引擎、投递包、NSH
  pack/       CIPK、容器(10 Pro / 9 Pro)、打包器、预览块
  icon/       LVGL 图标编解码、DGF1、GIF 合成、槽位表
  font/       字符集、sfnt 解析、子集化、度量归一
  make/       把上面几层串起来的用例接口
  project/    .chaosproj 工程容器、投递包反推、动作
  ui/         Paper 主题、动效、页面与外壳(底栏四格 + 推入式制作页)
```

## 构建

```bash
export PATH="/c/Users/YiYang/flutter-sdk/flutter/bin:$PATH"   # 或你自己的 flutter
dart run tool/sync_assets.dart ../Chaos-Module                  # 同步打包素材
flutter test --concurrency=1                                    # 134 个用例
bash tool/build_apk.sh release                                  # 出 apk
```

`tool/build_apk.sh` 把本机那几条绕坑参数(离线、阿里云镜像、arm64、真 NDK)固化在一起,
不要直接 `flutter build apk` —— 那会在拉 SDK 清单时无限等待。

界面按手机的 468x880 设计, 平板/桌面窗口拉到 760 逻辑像素以上时首页自动排两列,
单页内容限宽 720、底栏胶囊限宽 460 并居中。

打基础包要四件素材, 从 Chaos-Module 检出同步进 `assets/pack/`:
`chaos_sup.ko`、`chaos_icon.bin`、`font_pack.lua`、`icon_pack.lua`。
9 Pro 额外一份 `n67_importer.lua.in`。缺了会在打包时报 `MissingPackAsset`。

`chaos_icon.bin` 用 `CHAOS_ICON_SIZE=96 python tools/gen_chaos_icon.py tools/chaos.png out`
现场生成, 别拿仓库里 112px 的旧版。

## 测试

```bash
dart test        # 纯 Dart: 协议/打包/图标/字体/引擎
flutter test     # 依赖 dart:ui 的: 工程动作、UI 冒烟
```

金标准在 `test/fixtures/`, 来自 Kotlin 版 `app/src/test/resources/gif/`。
打包层的对拍是逐字节的: 同一份输入, Dart 出的容器必须和 PC 脚本/Kotlin 版完全相同。
