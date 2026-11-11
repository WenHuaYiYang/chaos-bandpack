"""Prepare the verified author's device assets without extracting artwork or keys."""
import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile

APK_SHA256 = "32ad33f485894f9ab43166c4f436b4d975e0cf4bf0360a7fad6296f85a5d40bc"
FILES = {
    "assets/pack/chaos_sup.ko": ("Chaos-Module/supervisor/chaos_sup.ko", "6de151262622f884fa810bf056f66eb14912db0e42683577f60d731de57df89d"),
    "assets/pack/chaos_icon.bin": ("Chaos-Module/chaos_icon.bin", "637e26caf59074440d54703a9425d023e4c806f2eea94021f94f043f8cdd26d2"),
    "assets/pack/font_pack.lua": ("Chaos-Module/installer/font_pack.lua", "3c9689bcf6289818b382c066ec848abbd74b9fa0d2607c608de9860894b98a69"),
    "assets/pack_n67/importer.lua.in": ("chaos-9pro/n67/importer.lua.in", "e9555cbe73229ad43a62470fe66fb45b406315b6b08c5bc19871dd778769c265"),
    "assets/pack_n67/installer.bin": ("chaos-9pro/n67/generated/resource.bin", "5aea1842f7271141b9e3f9cc9781cdeef9fa08d05c0da43f799b20ca027de27a"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if hashlib.sha256(args.apk.read_bytes()).hexdigest() != APK_SHA256:
        parser.error("APK 不是本分发版核对的原作者 1.3.0 配套包；请使用原始设备源码准备素材")
    prepared = []
    with ZipFile(args.apk) as archive:
        for source, (destination, expected) in FILES.items():
            data = archive.read(source)
            if hashlib.sha256(data).hexdigest() != expected:
                parser.error("设备素材哈希不符：" + source)
            target = args.out / destination
            if target.exists() and target.read_bytes() != data:
                parser.error("输出位置已有不同内容，请选择空目录：" + str(target))
            prepared.append((target, data, source, expected))
    for target, data, _, _ in prepared:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    manifest = {"apk_sha256": APK_SHA256, "nine_installer": "author-bundle (not the pinned v2.2 release)", "files": [
        {"asset": source, "sha256": expected, "bytes": len(data)} for _, data, source, expected in prepared
    ]}
    (args.out / "assets-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print("素材已核对并写入：", args.out)
    print("图标投递 Lua 使用 App 源码内的新版，不从旧 APK 复制。")


if __name__ == "__main__":
    main()
