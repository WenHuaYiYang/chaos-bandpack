# 预览字体（MiSans 子集）不放这里

投递包的缩略图里那几行字用 **MiSans** 渲染，因为这个手环的系统字体就是 MiSans，
用它预览最接近真机观感。

但 **MiSans 是小米的专有字体**（《MiSans 字体知识产权许可协议》），条款里有两条要紧的：

- 内嵌进软件**可以**，但必须在软件中特别注明使用了 MiSans 字体；
- **不得单独**将字体软件或其任何副本对外分发、再许可或售卖（随应用整体分发不在禁止之列）。

所以本仓库**不存放这个字体文件**（放一个 `.ttf` 在公开仓库里最接近"单独分发字体副本"这一条），
构建时把它放进这个目录即可。

## 怎么准备

1. 从官方页面下载 MiSans：<https://hyperos.mi.com/font/download>（选 MiSans Regular），
   得到 `MiSans-Regular.ttf`。
2. 裁成 GB2312 + ASCII 的子集 —— 只需要覆盖"预览里的固定文案 + 任意中文/ASCII 短名"。
   用 fontTools：

   ```bash
   pip install fonttools brotli
   # 字集按 GB2312 常用汉字区 + ASCII + 常用标点; 也可以直接拿一份 GB2312 文本当 --text-file
   pyftsubset MiSans-Regular.ttf \
     --unicodes="U+0020-007E,U+00A0-00FF,U+2000-206F,U+3000-303F,U+4E00-9FA5,U+FF00-FFEF" \
     --output-file=MiSans-Regular-subset.ttf --layout-features='*' --no-hinting
   ```

   **不要改字体里的名字与版权字段**：家族名要仍是 `MiSans`、版权声明要原样保留
   （这一点与 OFL 字体正好相反 —— 那边要求改作物必须改掉保留字体名）。
3. 把产物放到本目录，文件名固定为 `MiSans-Regular-subset.ttf`。

## 不放会怎样

不影响构建与功能：预览会回退到系统无衬线字体（见 `data/pack/PreviewFactory.kt`），
打出来的包、图标转换、字体子集化这些都不受影响 —— 只是缩略图里的字形不那么像真机。

## 许可

用了这个字体，就要在软件里注明（应用内「设置 → 关于 → 开源许可」已经有这一段）。
逐条声明见仓库根的 `THIRD_PARTY_NOTICES.md`，许可全文见 `third_party/MiSans-LICENSE.txt`。
