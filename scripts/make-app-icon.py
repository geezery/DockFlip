import io, struct, sys
from PIL import Image, ImageDraw, ImageFilter

S = 2048          # supersampled canvas
k = S / 1024      # scale from the 1024 design grid

def R(x0, y0, x1, y1):
    return [int(x0*k), int(y0*k), int(x1*k), int(y1*k)]

def vertical_gradient(size, top, bottom):
    w, h = size
    g = Image.new("RGBA", size)
    px = g.load()
    for y in range(h):
        t = y / (h - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        for x in range(w):
            px[x, y] = c
    return g

def build():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # Soft drop shadow under the squircle (macOS icon grid: 824 px body, 100 px margin).
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(R(100, 112, 924, 936), radius=int(185*k), fill=(16, 32, 64, 90))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18*k)))

    # Body: light, cool white.
    body_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(body_mask).rounded_rectangle(R(100, 100, 924, 924), radius=int(185*k), fill=255)
    body = vertical_gradient((S, S), (255, 255, 255), (226, 233, 244))
    img.paste(body, (0, 0), body_mask)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(R(100, 100, 924, 924), radius=int(185*k), outline=(15, 23, 42, 28), width=int(3*k))

    def window(x0, y0, x1, y1, accent):
        # shadow
        sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle(R(x0, y0+14, x1, y1+14), radius=int(34*k), fill=(16, 32, 64, 60))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(14*k)))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle(R(x0, y0, x1, y1), radius=int(34*k), fill=(255, 255, 255, 255), outline=(198, 208, 224, 255), width=int(5*k))
        # title bar
        d.rounded_rectangle(R(x0+3, y0+3, x1-3, y0+64), radius=int(31*k), fill=(238, 242, 248, 255))
        d.rectangle(R(x0+3, y0+40, x1-3, y0+64), fill=(238, 242, 248, 255))
        d.line(R(x0+3, y0+64, x1-3, y0+64), fill=(214, 222, 234, 255), width=int(4*k))
        for i, c in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
            cx, cy = x0 + 42 + i*34, y0 + 33
            d.ellipse(R(cx-11, cy-11, cx+11, cy+11), fill=c + (255,))
        # content
        if accent:
            d.rounded_rectangle(R(x0+44, y0+102, x0+44+(x1-x0)*0.42, y0+128), radius=int(13*k), fill=(31, 111, 235, 255))
        for j, frac in enumerate([0.78, 0.64, 0.71]):
            yy = y0 + (150 if accent else 110) + j*44
            if yy + 18 > y1 - 30:
                break
            d.rounded_rectangle(R(x0+44, yy, x0+44+(x1-x0-88)*frac, yy+18), radius=int(9*k), fill=(220, 227, 238, 255))

    window(236, 214, 676, 552, accent=False)
    window(336, 300, 790, 650, accent=True)

    # The plinth: the taskbar every window stands on.
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(R(176, 716, 848, 812), radius=int(36*k), fill=(16, 50, 120, 90))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(12*k)))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(R(176, 700, 848, 800), radius=int(36*k), fill=(31, 111, 235, 255))
    for i, cx in enumerate([392, 472, 552, 632]):
        a = 255 if i == 1 else 170
        d.rounded_rectangle(R(cx-27, 723, cx+27, 777), radius=int(13*k), fill=(255, 255, 255, a))
    d.rounded_rectangle(R(472-16, 784, 472+16, 790), radius=int(3*k), fill=(255, 255, 255, 255))
    return img

def png_bytes(img, size):
    out = io.BytesIO()
    img.resize((size, size), Image.LANCZOS).save(out, format="PNG", optimize=True)
    return out.getvalue()

def main(out_icns, out_png):
    master = build()
    master.resize((1024, 1024), Image.LANCZOS).save(out_png)
    entries = [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256),
               ("ic09", 512), ("ic10", 1024), ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)]
    chunks = b""
    for kind, size in entries:
        data = png_bytes(master, size)
        chunks += kind.encode() + struct.pack(">I", len(data) + 8) + data
    with open(out_icns, "wb") as f:
        f.write(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
