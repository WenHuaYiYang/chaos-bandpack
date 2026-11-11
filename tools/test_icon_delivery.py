"""Run the shipped Lua in an isolated, in-memory watchface/filesystem model.

Requires lupa; never exposes the host's io/os objects to the delivery script.
"""
from pathlib import Path
import struct
import unittest

from lupa import LuaRuntime

SOURCE = Path(__file__).resolve().parents[1] / "app/src/main/pack/icon_pack.lua"
INDEX = b"/data/chaos/icons/index.txt"
TEMP = b"/data/chaos/icons/index.tmp"


def cipk(files):
    return b"CIPK" + struct.pack("<I", len(files)) + b"".join(
        struct.pack("<IB", len(data), len(name)) + name + data for name, data in files
    )


def index(rows=()):
    return b"".join(f"{n:02d} {name:<12}\n".encode() for n, name in rows).ljust(128, b" ")


def native():
    return struct.pack("<BBHHHHH", 0x19, 16, 0, 1, 1, 4, 0) + b"\x11\x22\x33\xff"


def large_animation():
    # 64 full, non-repeating frames; valid DGF1 larger than the old 512 KiB gate.
    encoded = b"".join(bytes((127,)) + bytes((2, 3)) * 64 for _ in range(72))
    count = 64
    start = 1084 + count * 12
    header = struct.pack("<4s4H4I32s", b"DGF1", 96, 96, count, 0, count * 100, 0, 1084, start, bytes(32))
    table = b"".join(struct.pack("<III", 100, start + i * len(encoded), len(encoded)) for i in range(count))
    return header + bytes(1024) + table + encoded * count


class Watch:
    def __init__(self, payload, old=index(), *, short_read=None, fail_write=False,
                 corrupt_read=False, short_index=False, fail_rename=False, fail_close=False, eof_error=False):
        self.fs = {b"/watch/pack.bin": payload, INDEX: old}
        self.short_read = short_read
        self.fail_write, self.corrupt_read = fail_write, corrupt_read
        self.short_index, self.fail_rename, self.fail_close = short_index, fail_rename, fail_close
        self.eof_error = eof_error
        self.max_read = self.max_write = self.opens = 0
        self.status = b""
        self.lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
        g = self.lua.globals()
        g.py_open, g.py_remove, g.py_rename = self.open, self.remove, self.rename
        g.py_execute, g.py_status = self.execute, self.set_status
        self.lua.execute(b"""
          local function object(parent, props)
            return {set=function(self,p) if p.text then py_status(p.text) end end,
              clear_flag=function() end, add_flag=function() end,
              onClicked=function(self,cb) test_click=cb end}
          end
          local lvgl={Object=object,Label=object,Font=function() return 0 end,
            OPA=function(x) return x end,HOR_RES=function() return 336 end,VER_RES=function() return 480 end,
            FLAG={SCROLLABLE=1,CLICKABLE=2,EVENT_BUBBLE=3},ALIGN={CENTER=1}}
          lvgl.Timer=function(props)
            test_timer={paused=true,cb=props.cb,pause=function(self) self.paused=true end,
              resume=function(self) self.paused=false end,ready=function() end}
            return test_timer
          end
          package.preload.lvgl=function() return lvgl end
          io={open=function(path,mode) return py_open(path,mode) end}
          os={execute=function(cmd) return py_execute(cmd) end,
              remove=function(path) return py_remove(path) end,
              rename=function(a,b) return py_rename(a,b) end}
          SCRIPT_PATH='/watch/'
        """)
        source = SOURCE.read_bytes().replace(b"__PACK_NAME__", b"Unit").replace(b"__PACK_TITLE__", b"Test")
        self.lua.execute(source)

    def set_status(self, text):
        self.status = text

    def remove(self, path):
        self.fs.pop(path, None)
        return True

    def rename(self, a, b):
        if self.fail_rename:
            return None
        self.fs[b] = self.fs.pop(a)
        return True

    def execute(self, cmd):
        if cmd.startswith(b"rm -rf "):
            prefix = cmd[len(b"rm -rf "):] + b"/"
            assert prefix.startswith(b"/data/chaos/icons/")
            for path in list(self.fs):
                if path.startswith(prefix):
                    del self.fs[path]
        else:
            assert cmd.startswith(b"mkdir -p /data/chaos/icons/")
        return 0

    def open(self, path, mode):
        self.opens += 1
        if mode == b"rb" and path not in self.fs:
            return None
        if mode == b"wb":
            self.fs[path] = b""
        position = [0]
        table = self.lua.table()

        def read(_, size):
            assert isinstance(size, int) and 0 <= size <= 65536, size
            self.max_read = max(self.max_read, size)
            if self.short_read:
                size = min(size, self.short_read)
            data = self.fs[path]
            if self.corrupt_read and path.startswith(b"/data/chaos/icons/") and path not in (INDEX, TEMP):
                data = bytes((data[0] ^ 1,)) + data[1:]
            result = data[position[0]:position[0] + size]
            position[0] += len(result)
            if not result and self.eof_error:
                return None, b"EIO"
            return result if result else None

        def write(_, data):
            assert len(data) <= 65536
            self.max_write = max(self.max_write, len(data))
            if self.fail_write and path != TEMP:
                return None
            if self.short_index and path == TEMP:
                data = data[:64]
            self.fs[path] += data
            return table

        def close(_):
            if self.fail_close and mode == b"wb" and path != TEMP:
                return None
            return True

        table[b"read"], table[b"write"], table[b"close"] = read, write, close
        return table

    def run(self):
        self.lua.globals().test_click()
        for _ in range(10000):
            timer = self.lua.globals().test_timer
            if timer is None or timer[b"paused"]:
                break
            timer[b"cb"](timer)
        else:
            raise AssertionError("delivery did not finish")
        return "已投递".encode() in self.status


class DeliveryTest(unittest.TestCase):
    def test_legacy_static_and_short_reads(self):
        for short in (None, 3):
            watch = Watch(cipk([(b"alarm.bin", native())]), short_read=short)
            self.assertTrue(watch.run(), watch.status)
            self.assertEqual(native(), watch.fs[b"/data/chaos/icons/01/alarm.bin"])
            self.assertEqual(index([(1, "Unit")]), watch.fs[INDEX])

    def test_dynamic_above_512_kib_is_written_and_read_back_in_chunks(self):
        animation = large_animation()
        self.assertTrue(512 * 1024 < len(animation) < 1024 * 1024)
        cover = struct.pack("<BBHHHHH", 0x19, 16, 0, 96, 96, 384, 0) + bytes(96 * 96 * 4)
        cia = struct.pack("<4s4HQ", b"CIA1", 96, 96, 38, 0, 1)
        files = [(b"activities.bin", cover), (b"activities_anim.bin", animation), (b"animations.bin", cia)]
        watch = Watch(cipk(files))
        self.assertTrue(watch.run(), watch.status)
        for name, data in files:
            self.assertEqual(data, watch.fs[b"/data/chaos/icons/01/" + name])
        self.assertEqual(65536, watch.max_read)
        self.assertEqual(65536, watch.max_write)

    def test_same_name_reuses_slot_and_full_index_is_not_overwritten(self):
        watch = Watch(cipk([(b"alarm.bin", native())]), index([(1, "Other"), (3, "Unit")]))
        self.assertTrue(watch.run(), watch.status)
        self.assertIn(b"/data/chaos/icons/03/alarm.bin", watch.fs)
        full = index([(i, f"Filled{i}") for i in range(1, 9)])
        watch = Watch(cipk([(b"alarm.bin", native())]), full)
        self.assertFalse(watch.run())
        self.assertEqual(full, watch.fs[INDEX])

    def test_bad_container_never_commits_index(self):
        cases = [
            cipk([(b"../evil.bin", native())]), cipk([(b"unknown.bin", native())]),
            cipk([(b"alarm.bin", native()), (b"alarm.bin", native())]),
            cipk([(b"alarm.bin", bytes(524289))]), cipk([(b"alarm_anim.bin", bytes(1048577))]),
            b"CIPK" + struct.pack("<I", 257), b"CIPK\x01", cipk([(b"alarm.bin", native())])[:-1],
            cipk([(b"alarm.bin", native())]) + b"extra",
            cipk([(b"animations.bin", bytes(20))]),
        ]
        old = index([(1, "Other")])
        for payload in cases:
            with self.subTest(payload_size=len(payload)):
                watch = Watch(payload, old)
                self.assertFalse(watch.run(), watch.status)
                self.assertEqual(old, watch.fs[INDEX])
                self.assertFalse(any(b".." in path for path in watch.fs))

    def test_write_readback_close_and_atomic_index_failures_keep_old_index(self):
        old = index([(1, "Other")])
        for failure in ("fail_write", "corrupt_read", "short_index", "fail_rename", "fail_close", "eof_error"):
            with self.subTest(failure=failure):
                watch = Watch(cipk([(b"alarm.bin", native())]), old, **{failure: True})
                self.assertFalse(watch.run(), watch.status)
                self.assertEqual(old, watch.fs[INDEX])
                self.assertNotIn(TEMP, watch.fs)


if __name__ == "__main__":
    unittest.main()
