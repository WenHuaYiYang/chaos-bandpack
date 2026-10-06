# Chaos 制作台（Android）

在手机上给**小米手环 10 Pro 和 9 Pro** 制作投递表盘：挑一份字体或一组图标，在本地打成手环能收下的
`.bin`，再走手环官方的表盘侧载通道投进去。全程离线 —— 不联网、不上传、不依赖手机厂商的云。

- 设备：小米手环 10 Pro（p67），固件 **3.101.043**
- 设备：小米手环 9 Pro（n67），固件 **3.1.187**；沿用提供的 v2.1 移植，尚无真机验收
- 许可：**AGPL-3.0**（`LICENSE`）；第三方内容见 `THIRD_PARTY_NOTICES.md`
- 版本：1.3.0 / versionCode 4（`com.chaos.bandpack`，沿用原签名）

## 它做什么

| 制作页 | 输入 | 产出 |
|---|---|---|
| 更换字体 | 一份 `.ttf` / `.otf` | 字体投递包：子集化 + 垂直度量归一化，可选保留繁体 |
| 图标制作 | 图片或已制作的图标投递 BIN | 桌面、控制中心和设置共用一个包，按所选设备的尺寸和格式转换 |
| 继续编辑 | 图标／字体投递 BIN 或 `.chaosproj` | 恢复素材和参数，可切换设备重新导出 |

两种包都是手环的表盘容器。投递之后在**表盘管理**里切过去、点一下按钮就生效 ——
换字体、换桌面图标都不需要重刷主包、不需要重启。

**只做制作，不做传输**：导出 `.bin` 之后用你手上那条侧载通道（官方 App 或社区工具）送进手环。

界面里能当场看到结果：字体有样张预览，图标有设备外框预览，每个包都有自己的缩略图
（表盘列表里显示的那张图就是它）。

## 构建前提：先准备设备侧仓库

打包要的三样东西在设备侧（内核模块、应用图标、两个投递 Lua），**本仓库不放任何二进制**：

```bash
git clone https://github.com/WenHuaYiYang/Chaos-Module.git
cd Chaos-Module

sh tools/build_ko.sh                 # 内核模块 -> supervisor/chaos_sup.ko（需 nightly + rust-src）
python3 tools/gen_chaos_icon.py      # 应用图标 -> chaos_icon.bin（需 Pillow）
```

构建 App 时把设备侧仓库的位置告诉它：

```bash
./gradlew assembleDebug -Pchaos.repo=/path/to/Chaos-Module -Pchaos.n67.repo=/path/to/chaos-9pro
```

也可以写进 `local.properties`（`chaos.repo=/path/to/Chaos-Module`）或用环境变量 `CHAOS_REPO`；
默认值是 `../../Chaos-Module`（把两个仓库放成邻居）。两种目录形状都认：设备侧工程根
（里面还有一层 `Chaos-Module/`）与已发布的仓库根（`supervisor/`、`installer/` 就在这一层）。

测试和 release 构建均须准备两种设备的输入。双设备对拍还使用移植源码旁的原始手机端
测试样本，以及设备侧旧图标包和字体样本；缺少样本会失败，不能把跳过视为验证通过。

### 可选：预览用的字体

缩略图里的文字默认用系统无衬线字体渲染。想让它跟真机一样（手环系统字体是 MiSans），
按 `app/src/main/assets/fonts/README.md` 从官方渠道取一份 MiSans、裁成 GB2312+ASCII 子集，
放到那个目录即可。**这个字体不随仓库分发**（小米的条款禁止单独分发字体副本），
不放也不影响任何功能。

## 构建

```bash
./gradlew test -Pchaos.repo=<10Pro设备侧根> -Pchaos.n67.repo=<9Pro移植源码根>
./gradlew assembleDebug -Pchaos.repo=<10Pro设备侧根> -Pchaos.n67.repo=<9Pro移植源码根>
./gradlew assembleRelease -Pchaos.repo=<10Pro设备侧根> -Pchaos.n67.repo=<9Pro移植源码根>
```

| 项 | 取值 |
|---|---|
| JDK | 21（`jvmToolchain(21)`） |
| Android SDK | compileSdk 37 / targetSdk 36 / minSdk 26 |
| Compose BOM | 2026.09.00 |
| material3 | 1.5.0-alpha29（Expressive 入口只有 alpha 轨公开，稳定版把它标成了 internal） |

依赖走 Google / Maven Central。直连慢的话在 `gradle.properties` 里换镜像 —— 那里也放宽了超时。

## 产物长什么样

两种设备的投递包都是表盘容器。10 Pro 布局为：

```
[头部][包名 12B][显示名 64B][主题表][记录表][缩略图块][文件区]
                      四个槽: 投递 Lua / 内核模块 / 应用图标 / 载荷(字体或图标包)
```

10 Pro 壳由 `ShellBuilder` 从零合成，**不依赖任何外部模板**（主题表那几个指针与计数本来就能从文件
条数算出来）。格式的完整规则与设备侧实现见设备侧仓库的 `tools/container_shell.py`。

**与 PC 脚本的等价性**是这一行的验收线：同一份输入，App 打出的图标包与 PC 脚本打的
**逐字节一致**（`PackWriterTest` 里钉着这条；预览图像素各端各自渲染，不比字节）。
包号由载荷哈希推导，所以同一份内容的包身份稳定、不同内容自动分开。9 Pro 使用
原始移植的壳布局和导入 Lua，图标逐张保存为 DAT、字体分块；导入只写空槽。

## 代码结构

| 路径 | 内容 |
|---|---|
| `data/font/` | SFNT 解析、子集化（glyf/loca/hmtx/hhea/head/maxp/post/cmap 重写）、字集两档、度量归一化 |
| `data/icon/` | 图片 -> 112×112 BGRA、槽位表与文件名对号（不做模糊匹配，认不出就报） |
| `data/pack/` | `ShellBuilder`（容器壳自建）/ `ShellWriter`（字段口径与包名哈希）/ `Cipk`（图标包容器）/ `PackBuilders`（两种包组装）/ `PreviewFactory`（缩略图） |
| `ui/` | MD3 Expressive 界面：首页、两个制作页、设置（含开源许可） |
| `app/src/test/` | 单元测试；`resources/shell/*.bin` 是容器壳的金标准样本 |

## 已知限制

- 10 Pro 适配固件 **3.101.043**，9 Pro 适配移植版的 **3.1.187**。换固件需要重新验证地址与结构。
- 图标槽位是设备上实际存在的那批；文件名认不出来时**不猜**，会把对不上的报出来让你改名。
- 图片只做缩放 / 居中 / 覆盖率检查：不补底、不切圆角、不换色，不合适就给出可读原因。
- 图标页空槽位与首页预览里的"原图"是**从固件资源包里解出**的手环应用图标（不可再分发，
  也**不是**本项目素材）。素材不随本仓库分发：构建时从设备侧的素材目录同步，手上有固件
  资源、自己解过才有这批图；没有时界面落到"未内置"占位，其余功能不受影响。
  `-Pchaos.stockIcons=false` 可显式排除。来源与授权限制见 `THIRD_PARTY_NOTICES.md`。

## 隐私

不联网、不上传、不采集。App 只读你亲手选的文件，产物写到你选的目录。

完整政策见 [`PRIVACY_POLICY.md`](PRIVACY_POLICY.md)，构建期随 `syncLegalAssets` 进
`assets/legal/`（改名 `privacy_policy.md`，与代码里读取的路径一致）。履行方式：

- **首次启动**：全屏同意页（`PrivacyConsentGate`）——三条要点 + 政策全文 + 
  「同意并继续 / 不同意」；不同意则应用不可用，可重新查看或退出；
- 同意记录在 `UiPrefs`（`privacy_agreed_v1`，键名带版本，政策大改时升版本重新征求）；
- **随时回看**：设置页「隐私政策」入口（`PrivacyPolicyDialog`）；
- 最终 APK 未申请网络、短信、安装应用或危险权限；AndroidX 仅声明本包签名权限，用于限制动态广播接收者。

## 许可

源码按 **AGPL-3.0** 提供（`LICENSE`，GNU 官方文本逐字未改）。

第三方内容各有各的许可，**不在 AGPL-3.0 的授权范围内**：MiSans 字体子集（小米，专有许可，
内嵌需注明使用了 MiSans —— 应用内「设置 → 关于 → 开源许可」里有全文）、MingCute 图标
（Apache-2.0）、AndroidX / Compose / Material 3（Apache-2.0）等。逐条见
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。


## 1.2.0 图标制作

图标页按桌面、控制中心、设置分组，共 55 个选择槽（桌面 36、控制中心 9、设置 10），所有分类共用一个投递包。蓝牙与固件中没有对应入口的心率广播不提供选择槽。
桌面按 112×112 画布和 100×100 内容框转换；普通系统图标按 64×64 转换，允许透明图形并保留透明边缘。
日程与日历是两个独立应用，分别导出 calendar.bin 与 perpetual_calendar.bin。日历是一张自选静态图，未选择时保留系统绘制的日历；单独选择日历不会改动日程。
控制中心勿扰选择一张图片，自动生成 ctrl_disturb.bin 和 160×124 I8/RLE 的 ctrl_dnd.bin，覆盖关闭、动画和结束态。
因此已选槽位数与入包文件数分别显示，全部选择为 55 槽、56 文件；清空槽位会移除该槽及它的自动生成资源。

批量导入精确匹配英文素材名或分类中文名，例如 ctrl_disturb.png、控制中心_勿扰.png、设置_勿扰.png。
无分类的重复中文名（如勿扰、手电筒）不匹配；同批命中同槽的多张图片全部跳过并报告重名，不覆盖原选择。
calendar.png 和日程.png 匹配日程；perpetual_calendar.png 和日历.png 匹配日历，也支持桌面_日程.png、桌面_日历.png。两者分别选择和清空。

构建显式指定设备侧仓库。需要对拍的图标和容器测试缺素材会失败；本地 SVG 需先用设备侧生成器的渲染口径补齐 PNG。
syncPackAssets 把源文件和系统素材配置列为输入；release 先核对同步文件，再回读最终签名 APK 与源文件逐字节核对。
外发构建使用 -Pchaos.stockIcons=false。1.2.0 是此前的三分类版本；当前发布版本为 1.3.0 / versionCode 4，使用原私有签名文件覆盖安装。

## 1.3.0 双设备与工程

点击显示当前型号的悬浮按钮打开选择面板，选择 10 Pro / 9 Pro。按钮可拖动，不占页面布局高度。面板显示对应固件，以及当前图标可导出和保留在工程的数量；切换保留素材并清除上一设备的导出结果。点击“打开文件”选择旧图标投递 BIN、字体投递 BIN 或 `.chaosproj` 工程。旧包中的图标恢复到槽位，可单张替换、批量导入或清空，再导出所选设备的投递包。输入文件中的 Lua 和 ko 不会执行。

“保存工程”将图标、字体源、参数及设备选择一起保存到 `.chaosproj`。两种设备共用同一工程：同义槽位转换名称、尺寸和图像头；目标没有的素材会显示未导出名单，工程仍保留它们。9 Pro 没有 10 Pro 的独立日历槽，日历素材保留在工程中，9 Pro 的日程单独对应 schedule。字体从旧包导入时默认“保留字体原字节”，避免重复裁剪；修改字集或归一化选项会改为重新处理。

10 Pro 维持 55 槽、CIPK 及原投递链；9 Pro 开放 81 槽，包括控制中心、设置和系统应用，继续排除两个蓝牙连接槽。9 Pro 导出为 LVGL 8 BGRA + 独立 DAT，字体采用 64000 字节分块，最大 8 MB。9 Pro 须先安装 Chaos v2.1；顶部“9 Pro 主包”可导出原始安装容器，其内容未修改。9 Pro 导入器只写空槽，同名包需另取短名。

准备 9 Pro 构建输入：

```bash
python tools/prepare_nine_source.py --release <Chaos-9Pro-手机与手环-v2.1-发布包.zip> --firmware <187固件.bin> --out <本机准备目录>
```

将 `-Pchaos.n67.repo` 指向准备目录中的 `chaos-9pro`。工具校对 ZIP、源码与固件哈希，以及全部 66 个入口指纹；只解压，不执行附带程序。独立容器对拍使用同目录下 `chaos-bandpack-9pro/app/src/test/resources/n67` 的原始样本，不允许缺件跳过。旧 35 图标包导入回归另需 `~/Downloads/chaos-iconpack-pure.bin`，字体回归优先使用设备仓库的 `Chaos-Module/fonts/lxgw-wenkai-band.ttf`（须小于 8 MB）；均为本机测试输入，不在仓库再分发。

release 会核对最终 APK 内 10 Pro ko / Lua 以及 9 Pro 模板和原始安装容器与源文件逐字节一致。9 Pro 仅完成离线核对，没有真机验收；不支持其他固件强行安装。

个人使用构建可启用 `-Pchaos.stockIcons=true`。设备侧先运行 `scripts/extract_stock_sys_icons.py`，
按固件目录提取控制中心、设置原图，并与原固件解码像素核对。再运行 `scripts/extract_stock_calendar.py` 提取日历背景；App 按日历布局绘制当天星期和日期作为预览，日程继续读取它自己的 `calendar.png`。背景仅用于预览，不自动加入导出包。
控制中心白色原图使用深色预览底面。当前固件资源缺少心率广播原图，且设备没有该设置入口，App 不保留它的槽位。
构建会回读最终 APK，核对系统原图名单与每张 PNG 字节；关闭预览素材时核对 APK 没有残留图片。
