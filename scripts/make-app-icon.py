"""Builds Resources/AppIcon.icns from a 1024 × 1024 PNG of Resources/AppIcon.svg.

The icon is "Steps": three window tiles stepping back — the ⌘Tab stack — in
white on emerald. The SVG is the source; render it to a 1024 px PNG with any
SVG renderer, for example on a Mac:

    qlmanage -t -s 1024 -o /tmp Resources/AppIcon.svg   # writes /tmp/AppIcon.svg.png
    python3 scripts/make-app-icon.py /tmp/AppIcon.svg.png Resources/AppIcon.icns

Needs Pillow (pip install pillow).
"""
import io
import struct
import sys

from PIL import Image

# icns entry types and their pixel sizes (PNG payloads).
ENTRIES = [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256),
           ("ic09", 512), ("ic10", 1024), ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)]


def png_bytes(master, size):
    out = io.BytesIO()
    master.resize((size, size), Image.LANCZOS).save(out, format="PNG", optimize=True)
    return out.getvalue()


def main(master_png, out_icns):
    master = Image.open(master_png).convert("RGBA")
    if master.size != (1024, 1024):
        master = master.resize((1024, 1024), Image.LANCZOS)
    chunks = b""
    for kind, size in ENTRIES:
        data = png_bytes(master, size)
        chunks += kind.encode() + struct.pack(">I", len(data) + 8) + data
    with open(out_icns, "wb") as f:
        f.write(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
