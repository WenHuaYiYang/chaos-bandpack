# 第三方组件与许可

本仓库（Chaos 制作台）整体按 **AGPL-3.0** 发布（见 `LICENSE`）。下面这些是随包使用的
第三方内容，**各自按自己的许可**，不在 AGPL-3.0 的授权范围内。

应用内「设置 → 关于 → 开源许可」页会把这些条目一并列出 —— 有些许可（比如 MiSans）
要求"在软件中注明"，所以声明必须出现在应用里，不能只写在这个文件里。

---

## MiSans（MiSans-Regular 子集）

- 版权所有者：小米科技有限责任公司（Xiaomi Inc.）
- 来源：<https://hyperos.mi.com/font/download>
- 许可：《MiSans 字体知识产权许可协议》（MiSans Fonts Intellectual Property License Agreement）
  - 官方正文：<https://hyperos.mi.com/font/download>
  - 官方 PDF：<https://hyperos.mi.com/font-download/MiSans字体知识产权许可协议.pdf>
  - 许可全文随附：`third_party/MiSans-LICENSE.txt`

本应用（打出来的 APK）在 `app/src/main/assets/fonts/MiSans-Regular-subset.ttf` 内嵌了
MiSans-Regular 的**子集**字体文件，**只用于在应用内渲染表盘缩略图的预览**，不作其他用途。

> 本**源码**仓库不存放该字体文件：MiSans 的条款禁止"单独将字体软件或其任何副本对外分发"，
> 把裸字体放进公开仓库最贴近这一条。构建时按 `app/src/main/assets/fonts/README.md`
> 从官方渠道取得并裁成子集即可；不放也不影响功能（预览回退系统无衬线字体）。

我们对该文件做的改动：只做子集化（按 GB2312 字符集加 ASCII 范围裁剪字形表，约 1.6 MB）。
保留字形的轮廓、度量与字体内的命名（家族名仍是 `MiSans`、版权声明原样）一律未改。

该子集文件不作为独立字体产品对外分发或售卖，只随本应用整体分发。

依据《MiSans 字体知识产权许可协议》，本应用在此特别注明**使用了 MiSans 字体**。小米授予的是
"不可转让、非独占、免版税、**可撤销**、全球性"的版权许可，许可全文随本声明附上。

> 注意：MiSans 字体及其子集文件**不在本项目的 AGPL-3.0 授权范围内**，它们完全受
> 《MiSans 字体知识产权许可协议》约束；AGPL-3.0 不对其授予任何权利。
>
> 该字体只影响"预览图里的文字"这一件事：若把该 asset 删掉重新构建，应用会回退到系统
> 无衬线字体渲染预览，其余功能不受影响。

## MingCute 图标

- 来源：<https://github.com/Richard9394/MingCute>
- 许可：Apache License 2.0
- 随附：`app/src/main/assets/licenses/mingcute-LICENSE.txt`、`mingcute-NOTICE.txt`

应用界面用的图标取自 MingCute。改动：只取用到的子集、去掉不渲染的水印路径、填充色归一。

## AndroidX / Jetpack Compose / Material 3

- 来源：<https://github.com/androidx/androidx>、<https://github.com/material-components>
- 许可：Apache License 2.0

包括 `androidx.compose.*`（foundation / ui / animation / material3 / material-icons）、
`androidx.core:core-ktx`、`androidx.activity:activity-compose`、`androidx.documentfile`、
`androidx.compose.material3:material3-window-size-class`。

## Kotlin / kotlinx

- 来源：<https://github.com/JetBrains/kotlin>、<https://github.com/Kotlin/kotlinx.serialization>
- 许可：Apache License 2.0（Kotlin 编译器与标准库、`kotlinx-coroutines-android`、
  `kotlinx-serialization-json`）

## material-color-utilities

- 来源：<https://github.com/material-foundation/material-color-utilities>
- 许可：Apache License 2.0
- 用途：**只在测试里**离线生成配色表（生成结果以文本形式留在仓库里，运行时不依赖它）

## JUnit 4

- 来源：<https://github.com/junit-team/junit4>
- 许可：Eclipse Public License 1.0
- 用途：单元测试

## 内核模块 chaos_sup.ko（构建期同步，不随本仓库发布）

本仓库**不含**任何设备侧二进制。打包投递包要用到的 `chaos_sup.ko`（以及应用图标
`chaos_icon.bin`、两个投递 Lua）在构建时从设备侧仓库同步进来（见 README「构建前提」）。

- `chaos_sup.ko`：本项目自研内核模块，按 **AGPL-3.0** 发布，源码在设备侧仓库
  （`Chaos-Module`）的 `supervisor/` 下。
- `chaos_icon.bin`：由设备侧仓库的 `tools/gen_chaos_icon.py` 从 `tools/chaos.png` 生成，
  同属本项目。

## 手环桌面、控制中心与设置图标原图（系统原图标）

这批图是**小米固件里的画面资源**，不是本项目创作的素材。它们只作为"某个槽位原本长什么样"
的参照：图标制作页的空槽位与首页预览显示的就是它们。图**不进本仓库**，构建时从本机解出的
素材目录同步进来 —— 只有手上有固件资源、自己解过的人打出来的包才有；没有这份素材的构建
（公开仓库、CI）界面落到"未内置"占位，其余功能不受影响。

| 项 | 内容 |
|---|---|
| 来源 | 小米手环 10 Pro 官方固件包里的资源段（`vela_resource.bin`） |
| 提取方式 | 按 12 字节 LVGL 头解索引色图（BGRA 调色板 + 索引区／小米 RLE），转成 PNG |
| 改动画面 | 只做格式转换，未改 PNG 构图、配色与轮廓；控制中心白色图形放在深色预览底面上显示 |
| 授权归属 | 著作权归小米科技有限责任公司；不属于任何开源许可，本项目的 AGPL-3.0 对其不授予任何权利 |
| 使用限制 | 不可再分发，不得当作自有素材或改色后当原创使用；仅限本地对照 |

发布纪律：这批图**不随 App 仓库分发**，只在本地构建时从设备侧素材目录同步。要用
`-Pchaos.stockIcons=false` 显式排除。完整来龙去脉（含重解固件用的脚本与自查条件）
记在设备侧仓库的 `sys_icons/README.md`。
