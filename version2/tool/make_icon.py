"""Draws the STP v2 icon: a stopwatch-style progress ring wrapped around an
open book, with a golden spark. Rendered at 4x and downsampled for smooth edges."""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter

SS = 4  # supersampling


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def gradient_bg(size):
    """Diagonal indigo -> violet -> pink gradient with a soft top-left glow."""
    final = size
    w = h = size = 256  # smooth gradient: compute small, upscale
    base = Image.new("RGBA", (w, h))
    px = base.load()
    c1, c2, c3 = (67, 56, 202), (126, 34, 206), (219, 39, 119)
    for y in range(h):
        for x in range(w):
            t = (x * 0.55 + y * 0.45) / w
            c = lerp(c1, c2, t / 0.7) if t < 0.7 else lerp(c2, c3, (t - 0.7) / 0.3 * 0.55)
            px[x, y] = c + (255,)
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((-w * 0.25, -h * 0.3, w * 0.75, h * 0.6), fill=(255, 255, 255, 60))
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.12))
    return Image.alpha_composite(base, glow).resize((final, final), Image.BICUBIC)


def bezier(p0, p1, p2, n=40):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1])
            for t in (i / n for i in range(n + 1))]


def star(cx, cy, r, inner=0.28, points=4, rot=-math.pi / 2):
    pts = []
    for i in range(points * 2):
        rr = r if i % 2 == 0 else r * inner
        a = rot + i * math.pi / points
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


def draw_symbol(layer, cx, cy, s):
    """Draw the emblem centred at (cx, cy); s = scale (1.0 ~ 1024px icon)."""
    d = ImageDraw.Draw(layer, "RGBA")
    R, W = 300 * s, 58 * s

    # Soft shadow under everything.
    sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    sd.ellipse((cx - R - W / 2, cy - R - W / 2 + 24 * s, cx + R + W / 2, cy + R + W / 2 + 24 * s),
               outline=(30, 10, 80, 110), width=int(W))
    sh = sh.filter(ImageFilter.GaussianBlur(22 * s))
    layer.alpha_composite(sh)
    d = ImageDraw.Draw(layer, "RGBA")

    # Stopwatch crown + side button.
    cw, ch = 110 * s, 56 * s
    top = cy - R - W / 2
    d.rounded_rectangle((cx - cw / 2, top - ch - 20 * s, cx + cw / 2, top - 20 * s), radius=18 * s,
                        fill=(255, 255, 255, 255))
    d.rectangle((cx - 22 * s, top - 26 * s, cx + 22 * s, top + 8 * s), fill=(255, 255, 255, 255))
    bx, by = cx + (R + W / 2) * math.cos(math.radians(-45)), cy + (R + W / 2) * math.sin(math.radians(-45))
    d.line((bx - 4 * s, by + 4 * s, bx + 34 * s, by - 34 * s), fill=(255, 255, 255, 255), width=int(34 * s))

    # Ring track.
    box = (cx - R, cy - R, cx + R, cy + R)
    tr = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(tr).ellipse((box[0] - W / 2, box[1] - W / 2, box[2] + W / 2, box[3] + W / 2),
                               outline=(255, 255, 255, 255), width=int(W))
    tr.putalpha(tr.getchannel("A").point(lambda a: a * 80 // 255))
    layer.alpha_composite(tr)
    d = ImageDraw.Draw(layer, "RGBA")

    # Progress arc: white -> gold, 280 degrees from the top.
    start, sweep = -90, 280
    steps = 220
    white, goldc = (255, 255, 255), (255, 200, 61)
    for i in range(steps):
        t = i / steps
        a0 = math.radians(start + sweep * t)
        a1 = math.radians(start + sweep * (t + 1.6 / steps))
        col = lerp(white, goldc, t ** 1.4) + (255,)
        for a in (a0, (a0 + a1) / 2, a1):
            x, y = cx + R * math.cos(a), cy + R * math.sin(a)
            d.ellipse((x - W / 2, y - W / 2, x + W / 2, y + W / 2), fill=col)

    # Glowing knob at the end of the arc.
    ae = math.radians(start + sweep)
    kx, ky = cx + R * math.cos(ae), cy + R * math.sin(ae)
    glow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((kx - 70 * s, ky - 70 * s, kx + 70 * s, ky + 70 * s), fill=(255, 214, 90, 170))
    glow = glow.filter(ImageFilter.GaussianBlur(26 * s))
    layer.alpha_composite(glow)
    d = ImageDraw.Draw(layer, "RGBA")
    d.ellipse((kx - 40 * s, ky - 40 * s, kx + 40 * s, ky + 40 * s), fill=(255, 255, 255, 255))
    d.ellipse((kx - 22 * s, ky - 22 * s, kx + 22 * s, ky + 22 * s), fill=(255, 190, 40, 255))

    # Open book.
    by0 = cy + 30 * s        # top of spine
    spine_bot = cy + 182 * s
    half = 188 * s
    lift = 38 * s
    left = (bezier((cx, by0), (cx - half * 0.5, by0 - lift * 1.6), (cx - half, by0 - lift * 0.6))
            + [(cx - half, spine_bot - lift * 0.6)]
            + bezier((cx - half, spine_bot - lift * 0.6), (cx - half * 0.5, spine_bot - lift * 1.6), (cx, spine_bot)))
    right = [(2 * cx - x, y) for x, y in left]
    # Book shadow / cover edge.
    cover = [(x, y + 14 * s) for x, y in left] + [(x, y + 14 * s) for x, y in reversed(right)]
    d.polygon(cover, fill=(255, 196, 60, 255))
    d.polygon(left, fill=(255, 255, 255, 255))
    d.polygon(right, fill=(236, 233, 255, 255))
    d.line((cx, by0, cx, spine_bot), fill=(150, 130, 230, 255), width=int(6 * s))
    # Text lines on the pages.
    for k in range(4):
        off = 32 * s + k * 26 * s
        for sign in (-1, 1):
            p0 = (cx + sign * 26 * s, by0 + off - 4 * s)
            p1 = (cx + sign * (half * 0.5), by0 + off - lift * 1.25)
            p2 = (cx + sign * (half - 26 * s - (k == 3) * 40 * s), by0 + off - lift * 0.55)
            pts = bezier(p0, p1, p2, 24)
            d.line(pts, fill=(178, 166, 238, 255), width=int(9 * s), joint="curve")

    # Golden spark above the book.
    sx, sy = cx, cy - 105 * s
    g2 = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(g2).ellipse((sx - 70 * s, sy - 70 * s, sx + 70 * s, sy + 70 * s), fill=(255, 220, 120, 150))
    g2 = g2.filter(ImageFilter.GaussianBlur(28 * s))
    layer.alpha_composite(g2)
    d = ImageDraw.Draw(layer, "RGBA")
    d.polygon(star(sx, sy, 68 * s), fill=(255, 211, 77, 255))
    d.polygon(star(sx, sy, 34 * s, inner=0.35), fill=(255, 255, 255, 255))
    d.polygon(star(sx + 92 * s, sy - 30 * s, 24 * s), fill=(255, 255, 255, 255))
    d.polygon(star(sx - 86 * s, sy + 6 * s, 16 * s), fill=(255, 236, 170, 255))


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return m


def render(size, kind):
    big = size * SS
    if kind == "full":            # legacy / store icon: rounded square
        bg = gradient_bg(big)
        draw_symbol(bg, big / 2, big / 2 + big * 0.035, big / 1024 * 0.92)
        out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        out.paste(bg, (0, 0), rounded_mask(big, int(big * 0.225)))
    elif kind == "round":
        bg = gradient_bg(big)
        draw_symbol(bg, big / 2, big / 2 + big * 0.035, big / 1024 * 0.80)
        out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        m = Image.new("L", (big, big), 0)
        ImageDraw.Draw(m).ellipse((0, 0, big - 1, big - 1), fill=255)
        out.paste(bg, (0, 0), m)
    elif kind == "fg":            # adaptive foreground: emblem inside the safe zone
        out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        draw_symbol(out, big / 2, big / 2 + big * 0.025, big / 1024 * 0.60)
    elif kind == "bg":
        out = gradient_bg(big)
    return out.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    root = sys.argv[1]
    res = f"{root}/android/app/src/main/res"
    render(1024, "full").save(f"{root}/assets/app_icon.png")
    dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, k in dens.items():
        render(int(48 * k), "full").save(f"{res}/mipmap-{name}/ic_launcher.png")
        render(int(48 * k), "round").save(f"{res}/mipmap-{name}/ic_launcher_round.png")
        render(int(108 * k), "fg").save(f"{res}/mipmap-{name}/ic_launcher_foreground.png")
        render(int(108 * k), "bg").save(f"{res}/mipmap-{name}/ic_launcher_background.png")
    print("done")
