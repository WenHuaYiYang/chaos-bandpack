# Chaos Beauty Pack V1 (.chp)

A CHP file contains one installable **font** or one set of **icons** for one
explicit device target. It is not a watch-face, ZIP, Lua script, project, or
firmware image. The extension is lowercase .chp; content identification uses
magic, not the filename. The name is a display label, never a destination.

## Wire layout

| Offset | Size | Meaning |
| --- | --- | --- |
| 0 | 4 | ASCII CHP1 (hex 43 48 50 31) |
| 4 | 4 | Unsigned little-endian manifest byte length M |
| 8 | M | Canonical UTF-8 JSON, no BOM, 1–65,536 bytes |
| 8 + M | sum of entry sizes | Raw, uncompressed resources in manifest order |

There are no resource offsets, gaps, padding, or trailing bytes. The payload
may be at most 33,554,432 bytes (32 MiB); the whole file may be at most
33,619,976 bytes. Verify sizes against the bytes already present before slicing
or allocating. Validate the entire manifest, digests, and resource headers
before accepting any resources.

## Manifest

Keys are mandatory and appear in the exact order shown. The diagram below is
also the manifest for the example at the end of this document:

~~~json
{"version":1,"kind":"icon","device":"p67","name":"Blue","files":[{"name":"alarm.bin","size":16,"sha256":"727b1ed56f6df11c185f0cf89d1f2c800e67c92c2c71e1a07217e9e9b6b11422"}]}
~~~

- **version** is the integer 1; other versions are unsupported.
- **kind** is exactly "font" or "icon".
- **device** is exactly "p67" (10 Pro) or "n67" (9 Pro).
- **name** is 1–12 UTF-8 bytes. A font label cannot end in ASCII space and
  cannot contain U+0000–001F, U+007F–009F, U+202A–202E, or U+2066–2069.
  Icon labels use only printable non-space ASCII (0x21–0x7E).
- **files** contains exactly one entry for a font, or 1–256 entries for icons,
  sorted by ascending, case-sensitive ASCII filename. Names also must be unique
  under ASCII case folding. A font file is exactly font.ttf. Icon names match
  the whole pattern [A-Za-z0-9_]{1,60} followed by .bin. These are leaf IDs,
  not paths; no separators, traversal, extra dots, or whitespace are allowed.
  For both devices use the PackMake resource filename (CipkIcon.fileName);
  n67 legacy .dat names and installed aliases are not a container convention.
- Each **size** is a positive JSON integer in bytes. Maximum: p67 font
  16,777,215; n67 font 8,000,000; each icon entry 1,048,576.
- Each **sha256** is exactly 64 lowercase ASCII hexadecimal characters: the
  SHA-256 digest of that entry's raw bytes, with no prefix or salt. It is an
  integrity checksum, not a signature or proof of provenance.

V1 canonical JSON has no inter-token whitespace or final newline, no unknown
or repeated keys, integers in ordinary decimal notation, and strings encoded
with literal Unicode scalar values except quote and backslash, which are
escaped as backslash–quote and double backslash respectively. Strings are not
normalized. Control characters are not allowed by any V1 field. Requiring one
representation avoids duplicate-key ambiguity between decoders.

## Resource checks

The following checks follow the resource-delivery rules in firmware
(supervisor/bridge/chaos_package.inc) and the output of PackMake's two device
builders. Static icon IDs are not a slot allowlist; the downstream consumer
still determines which IDs it uses. Target metadata does not imply a target
supports the app's delivery transport.

- **Font:** a standalone sfnt. The p67 signatures are 0x00010000, OTTO, or
  true; n67 accepts only 0x00010000 per the 9 Pro builder. The 12-byte header
  and the 1–256 complete 16-byte table records must fit. Each record's u32be
  offset and length (at record offsets 8 and 12) must be in bounds.
- **n67 icon:** no animations. Its u32le header is 5 | (width << 10) |
  (height << 21), with 11 bits each for width and height, each 1–512.
  Exactly width × height × 4 BGRA bytes must follow. Do not confuse this
  with the p67 LVGL header or send it to a p67-only installer.
- **p67 static icon:** 12-byte LVGL image header: 0x19 at byte 0, pixel format
  at byte 1, u16le flags at 2, width at 4, height at 6, stride at 8. Width
  and height are 1–512. Format 16 with flags 0 requires stride ≥ 4 × width
  and exactly stride × height pixel bytes. Format 10 with flags 0 requires
  stride ≥ width and exactly 1,024 + stride × height palette/index bytes.
  Format 10 with flags 8 requires width ≤ stride ≤ 512 and three additional
  u32le fields at offsets 12, 16 and 20: compression type 1, size of the
  nonempty compressed stream at offset 24, and raw size 1,024 + stride × height.
- **p67 _anim.bin:** DGF1 header, 96 × 96, u16le frame count 1–256 at 8,
  reserved zero at 10, u32le frame-table start 1,084 at 20 and payload start
  1,084 + 12 × frame count at 24. The table and at least one payload byte must
  fit. Each animation requires the corresponding supported desktop stem,
  a matching 96 × 96 static cover, and a set bit in animations.bin.
- **p67 animations.bin:** optional for static-only sets (if present, mask
  must be zero). Exactly 20 bytes: CIA1, u16le width and height 96, u16le
  stem count 38, u16le zero, then a u64le bitmask in the firmware desktop
  animation order (same as AnimatedIcons.stems). Bits 38–63 must be zero;
  bits 0–37 must match exactly the included _anim.bin stems. An index alone
  is not an icon pack. Both reserved suffix and filename are case-sensitive.

Import does not rasterize fonts or unpack LVGL RLE or DGF1 frames. This keeps
pack validation bounded by encoded size without invoking rendering/parsing
code on untrusted resources; these checks prove container integrity and
header-level compatibility, not renderability. Device installers/consumers
must still enforce their own policy, compatibility checks, and payload checks
before installation and use. No contents are executed or extracted to paths.

## Test vector

For the manifest above (exactly 173 bytes, excluding the document's newline),
the entire file is these eight header bytes, then the manifest, then the 16
payload bytes below:

~~~text
43 48 50 31 ad 00 00 00
19 10 00 00 01 00 01 00 04 00 00 00 33 22 11 ff
~~~
