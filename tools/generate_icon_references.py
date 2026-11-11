"""Refresh independent Pillow pixels and Python p67/DGF1 ABI test fixtures.

The small synthetic GIF inputs are versioned in app/src/test/resources/gif.
Pass --p67-tools pointing to Chaos-Module/tools to also refresh the container golden.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import struct
import tempfile

from PIL import Image, ImageSequence

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "app/src/test/resources/gif"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--p67-tools", type=Path)
    args = parser.parse_args()
    names = json.loads((OUT / "reference.json").read_text())
    reference = {}
    for name in names:
        with Image.open(OUT / (name + ".gif")) as image:
            loop = image.info.get("loop")
            delays, pixels = [], bytearray()
            for frame in ImageSequence.Iterator(image):
                delays.append(frame.info.get("duration", 100))
                pixels.extend(frame.convert("RGBA").tobytes())
        (OUT / (name + ".rgba")).write_bytes(pixels)
        reference[name] = {"delays": delays, "plays": 1 if loop is None else (0 if loop == 0 else loop + 1)}
    (OUT / "reference.json").write_text(json.dumps(reference, indent=2))
    if not args.p67_tools:
        return
    spec = importlib.util.spec_from_file_location("p67_reference", args.p67_tools / "p67_pack.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if module.VERSION != 0x10107:
        parser.error("请使用 Chaos-Module bcff1385721cbbcb9d402040fbe4789ac1e03084 的 p67_pack.py")
    # DGF1 fixture: runs of index 1, then literal alternation of indices 2 and 3.
    frames = [bytes((255, 1)) * 72, (bytes((127,)) + bytes((2, 3)) * 64) * 72]
    header = struct.pack("<4s4H4I32s", b"DGF1", 96, 96, 2, 0, 60001, 0xffffffff, 1084, 1108, bytes(range(32)))
    palette = b"".join(bytes((i ^ 85, 255 - i, i, 0 if i == 0 else 255)) for i in range(256))
    at, table = 1108, bytearray()
    for delay, frame in zip((1, 60000), frames):
        table.extend(struct.pack("<III", delay, at, len(frame))); at += len(frame)
    animation = header + palette + table + b"".join(frames)
    cover = struct.pack("<BBHHHHH", 25, 16, 0, 96, 96, 384, 0) + struct.pack("<I", 0x80402010) * 9216
    legacy = struct.pack("<BBHHHHH", 25, 16, 0, 112, 112, 448, 0) + struct.pack("<I", 0xff132739) * 12544
    cia = struct.pack("<4s4HQ", b"CIA1", 96, 96, 38, 0, 1)
    for name, data in (("valid.dgf", animation), ("cover96.bin", cover), ("legacy112.bin", legacy)):
        (OUT / name).write_bytes(data)
    files = [(b"activities.bin", cover), (b"alarm.bin", legacy), (b"activities_anim.bin", animation), (b"animations.bin", cia)]
    cipk = b"CIPK" + struct.pack("<I", len(files)) + b"".join(struct.pack("<IB", len(data), len(name)) + name + data for name, data in files)
    (OUT / "animated-pack.cipk").write_bytes(cipk)
    raw = (ROOT / "app/src/test/resources/shell/golden-one.bin").read_bytes()
    start = struct.unpack_from("<I", raw, 0x20)[0]
    length = struct.unpack_from("<I", raw, start + 8)[0]
    (OUT / "reference-preview.block").write_bytes(raw[start:start + 12 + length])
    build = ROOT / "app/build"
    build.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=build) as directory:
        temp = Path(directory)
        (temp / "pack.bin").write_bytes(cipk)
        (temp / "main.lua").write_bytes(b'local PACK_NAME = "Demo"\nlocal PACK_TITLE = "Icons Demo"\n')
        module.build({"preview": str(OUT / "reference-preview.block"), "id": "123456789012", "name": "Icons Demo", "styleName": "样式1", "files": [
            {"name": "_lua/xiaomi-band-10-pro/main.lua", "path": str(temp / "main.lua")},
            {"name": "_lua/xiaomi-band-10-pro/pack.bin", "path": str(temp / "pack.bin")},
        ]}, OUT / "animated-pack.bin")


if __name__ == "__main__":
    main()
