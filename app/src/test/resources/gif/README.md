# Independent protocol fixtures

The GIFs are synthetic colored shapes/palettes, with a seeded interlaced image and deliberate invalid cases.
`reference.json` and each `.rgba` contain Pillow 13's composited RGBA pixels, frame delays and total play count.
They include disposal 0/1/2/3, partial first frames, local palettes, interlacing and absent/finite/infinite loops.
Transparent RGB channels are ignored when comparing invisible pixels; alpha is still checked exactly.

`valid.dgf` is independently constructed with Python `struct`, two frames at the 1/60000 ms bounds,
and the unsigned maximum loop count. `animated-pack.cipk` is a literal little-endian CIPK encoding.
`animated-pack.bin` is generated with public Chaos-Module `tools/p67_pack.py` at commit
`bcff1385721cbbcb9d402040fbe4789ac1e03084`; the preview is taken from the existing shell golden.
`native-stems.txt` pins the 106 static resource stem names from the same commit's `res_hook.rs`.

Regenerate reference results with:

```sh
python tools/generate_icon_references.py --p67-tools /path/to/Chaos-Module/tools
```

These fixtures are test resources and are not packaged in the APK.
