"""准备群友提供的 9 Pro v2.1 源码，只解压和核对，不执行其中的程序。"""
import argparse
import hashlib
import io
import json
import struct
from pathlib import Path
from zipfile import ZipFile

RELEASE_HASH = "4337a485c49ad64a708447e7911d77cc8f04c15ba790c17c584ff9e3d02c8671"
SOURCE_HASH = "8abd126e748e9b3d28b1669280b8874ade99a83c422ef40ac2699a0f65f96425"
FIRMWARE_HASH = "6d33afe200897d6c307f98738176d95c55e86ca568c4a4fb8d8f653c43924cd2"


def checked(data, expected):
    assert hashlib.sha256(data).hexdigest() == expected, "输入不是已核对的原始文件"
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--firmware", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    data = checked(args.release.read_bytes(), RELEASE_HASH)
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    with ZipFile(io.BytesIO(data)) as release:
        source = checked(release.read("Chaos-9Pro-手机与手环完整源码.zip"), SOURCE_HASH)
    with ZipFile(io.BytesIO(source)) as archive:
        total = 0
        for entry in archive.infolist():
            path = (out / entry.filename).resolve()
            total += entry.file_size
            assert path.is_relative_to(out) and total <= 64_000_000 and "\\" not in entry.filename
            assert path.name != "keystore.properties" and path.suffix not in (".jks", ".keystore")
            if entry.is_dir():
                path.mkdir(parents=True, exist_ok=True)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(archive.read(entry))
    print("9 Pro 源码准备完成:", out / "chaos-9pro")
    if args.firmware:
        firmware = checked(args.firmware.read_bytes(), FIRMWARE_HASH)
        start = firmware.index(bytes.fromhex("5a5a5a7e") + b"3.1.187\0")
        offset, size = struct.unpack_from("<II", firmware, start + 0x54)
        assert 0 < offset < len(firmware) - start and size <= len(firmware) - start - offset
        with ZipFile(io.BytesIO(firmware[start + offset:start + offset + size])) as ap_zip:
            assert ap_zip.namelist() == ["vela_ap.bin"]
            ap = ap_zip.read("vela_ap.bin")
        fingerprints = json.loads((out / "chaos-9pro/n67/generated/firmware-fingerprints.json").read_text("utf-8"))
        def matches(image):
            return all(image[int(row["address"], 16)-0x0c080000:int(row["address"], 16)-0x0c080000+8] == bytes.fromhex(row["bytes"]) for row in fingerprints)
        broken = bytearray(ap)
        broken[int(fingerprints[0]["address"], 16)-0x0c080000] ^= 1
        assert not matches(broken), "损坏对照必须失败"
        assert matches(ap), "原始 187 镜像与入口指纹不一致"
        (out / "vela_ap_187.bin").write_bytes(ap)
        print("187 AP 指纹核对:", len(fingerprints), "项通过，损坏对照失败")


if __name__ == "__main__":
    main()
