# 10 Pro 静态与动态图标

适用设备为小米手环 10 Pro（p67）、固件 **3.101.043**。本制作台只生成投递包。
动态播放需要手环上先安装支持 DGF1/CIA1 的配套 Chaos 模块；旧模块使用静态封面。
本次更新没有修改或编译设备侧原生模块，也没有进行手环真机验收。

## 手机制作

1. 在设备选择中选 10 Pro，进入图标页。
2. 点桌面槽位选择 PNG、GIF 或原生 BIN；也可以批量选择并按文件名匹配。
3. 新图片和 GIF 使用完整画布，等比居中到 96×96，不补底、不切圆角，保留透明度。
4. 点击图标下方的“动态 · N 帧”查看预览，可暂停或重播；退出预览或切到后台会停止播放。
5. 导出 `.bin`，使用 AstroBox 等侧载工具送入手环。不要直接安装内部 CIPK。
6. 打开投递表盘并点击“投递图标”，完成后到 Chaos 的桌面图标设置中选择该包。

覆盖同名包前先切回系统原图标，投递完成后重新选择包，等待资源应用批次完成。
图标包清单仍为 8 个槽位；同名包复用包号，满槽时需先删除一包。

## 批量素材

```text
activities.gif          动画和默认首帧封面
activities.png          可选自定义封面，与 GIF 一起选入
alarm.png               静态图标
weather.bin             已转换的静态原生图，保留原尺寸
weather_anim.bin        已转换的 DGF1，需要同时提供或已选择 96×96 封面
ctrl_setting.bin        静态系统资源
```

文件名精确匹配桌面 stem、系统资源 stem 或分类中文名。
同一 stem 不能同时有多个封面（包括 PNG 与 BIN），也不能同时有 GIF 与 `_anim.bin`。
有冲突或任何一项不合法时，该槽位整组不导入，原选择保留，其余组继续处理。
单张选择静态图会替换该槽原来的动画；自定义动画封面请用上述批量配对方式。
清空槽位会同时移除其动画，勿扰的派生资源也一起移除。

原生资源页接受设备映射中的原尺寸 BIN。系统 UI 只支持静态素材，不将 GIF 转成系统动画。
旧的 112×112 等 p67 原生 BIN 可以原样复用，不会因为新默认尺寸而重新缩放。

## 9 Pro 与工程

9 Pro 继续按固件 3.1.187 的原始协议导出静态素材，不输出 DGF1/CIA1。
带动画的工程切到 9 Pro 后使用静态封面，并列出未导出的动画；动画字节仍保存在工程中。
新工程格式版本为 2，仍能打开版本 1。可以从新两资源投递包或旧四槽投递包恢复素材。
输入包的 Lua 和原生模块不会执行。

本分发构建保留作者公开 APK 的 9 Pro 配套主包，并标注“作者配套版”。它与上游 release
任务固定的 v2.2 哈希不同；原有 release 校验没有被关闭。交付 APK 为调试构建。

## 协议与边界

- GIF 为 1–256 帧，每帧 1–60000 ms；保留逐帧合成、局部调色板、交错帧、disposal 和循环次数。
- GIF 源文件最多 32 MB，逻辑画布最多 4194304 像素、单边最多 4096；文本绘制扩展会明确拒绝。
- DGF1 使用一张共享的 256 项 BGRA 调色板。颜色较多时在手机端量化，帧数、时长和循环数不变。
- 静态文件最多 512 KiB，动画最多 1 MiB；不会自动抽帧或降低 96×96 输出分辨率来凑上限。
- CIPK 最多 256 个文件，文件名最多 64 个 ASCII 字节；含头和文件记录的总长度最多 16777215 字节。
- 每个新包都带 20 字节 CIA1 索引，纯静态包位图为零。38 个桌面 stem 的 bit 顺序固定，不使用 UI 顺序。
- 外容器只放 `_lua/xiaomi-band-10-pro/main.lua` 与 `pack.bin`，字体投递仍沿用原来的容器。
- 投递脚本按最多 64 KiB 分块写入、关闭并分块回读所有文件，之后才以临时文件、回读和 rename 提交 128 字节清单。
- 文件路径、重复名、未知 stem、越界长度、DGF1 帧表、压缩数据、总时长和 CIA1 位图都会核对。

## 验证

`GifIconsTest` 使用独立 Pillow 合成的参考像素与时序，`Dgf1Test` 使用 Python 按 ABI
构造的独立二进制样本。`AnimatedPackTest` 将相同预览、Lua 和素材与公开 `p67_pack.py`
构造的容器逐字节比较，并检查工程保存、旧包导入及跨设备静态回退。
`tools/test_icon_delivery.py` 用 Lupa 执行实际内嵌 Lua，io/os 全部替换为内存模型，不写设备或主机文件。

```sh
./gradlew testDebugUnitTest --tests '*GifIconsTest' --tests '*Dgf1Test' \
  --tests '*AnimatedPackTest' --tests '*IconInputNamesTest' \
  --tests '*NativeIconRenderingTest' --tests '*SystemIconsTest'
python3 -m venv .venv
.venv/bin/python -m pip install -r tools/requirements-test.txt
.venv/bin/python tools/test_icon_delivery.py
```

原有依赖私人 PC 产物、源字体或 9 Pro 原始金标准的集成对拍仍需准备相应输入；
不能将缺样本或跳过视为完整验证。桌面动画的实际帧率、功耗、转场和低内存表现需在配套模块真机上验证。
