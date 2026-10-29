"""Generates the VoiceLog app icon: a "V" holding a red recording dot.

    python tools/make_icon.py

Writes:
- windows/runner/resources/app_icon.ico (16-256 px)
- Android launcher icons: legacy mipmap-*/ic_launcher.png, and adaptive
  foreground + monochrome layers (Android 8+ / 13+ themed icons)
- tools/icon_preview.png (1024 px)

Requires Pillow.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"

BG = (23, 24, 27)          # VL.surface
BORDER = (48, 50, 55)      # VL.border
V = (232, 232, 234)        # VL.text
RED = (224, 88, 79)        # VL.red
WHITE = (255, 255, 255)

ICO_SIZES = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]

# Launcher density buckets: legacy icon is 48 dp, adaptive layers are 108 dp.
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

# Adaptive icons may be masked to a circle of 66/108 of the layer; the glyph
# is shrunk to stay well inside it.
ADAPTIVE_SCALE = 0.62


def draw(size: int, *, tile: bool = True, mono: bool = False, scale: float = 1.0) -> Image.Image:
    """Draws on a 4x canvas and downsamples for smooth edges.

    tile: draw the rounded graphite background (off for adaptive layers).
    mono: single-color glyph for Android themed icons.
    scale: glyph size relative to the full design.
    """
    s = size * 4
    u = s / 1024 * scale  # design units are on a 1024 grid
    off = s / 2 - 512 * u  # keeps the glyph centered when scaled
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def p(x: float, y: float) -> tuple[float, float]:
        return off + x * u, off + y * u

    # Small icons get a thicker V so they stay readable.
    small = size <= 32
    stroke = (150 if small else 118) * u
    dot_r = (118 if small else 108) * u

    if tile:
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=230 * s / 1024, fill=BG,
                            outline=BORDER, width=max(1, round(10 * s / 1024)))

    left, bottom, right = p(250, 288), p(512, 760), p(774, 288)
    glyph = WHITE if mono else V
    r = stroke / 2
    # Each arm is an exact quad (Pillow's wide diagonal lines come out thin),
    # with round caps and joint.
    for (ax, ay), (bx, by) in ((left, bottom), (bottom, right)):
        length = ((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5
        nx, ny = -(by - ay) / length * r, (bx - ax) / length * r
        d.polygon([(ax + nx, ay + ny), (bx + nx, by + ny), (bx - nx, by - ny), (ax - nx, ay - ny)], fill=glyph)
    for x, y in (left, right, bottom):
        d.ellipse([x - r, y - r, x + r, y + r], fill=glyph)

    # The dot sits in the V's opening, clear of both arms.
    cx, cy = p(512, 318)
    d.ellipse([cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r], fill=WHITE if mono else RED)

    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    frames = [draw(n) for n in ICO_SIZES]
    ico = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    frames[-1].save(ico, format="ICO", sizes=[(n, n) for n in ICO_SIZES],
                    append_images=frames[:-1])

    for bucket, factor in DENSITIES.items():
        out = RES / f"mipmap-{bucket}"
        out.mkdir(parents=True, exist_ok=True)
        draw(round(48 * factor)).save(out / "ic_launcher.png")
        layer = round(108 * factor)
        draw(layer, tile=False, scale=ADAPTIVE_SCALE).save(out / "ic_launcher_foreground.png")
        draw(layer, tile=False, mono=True, scale=ADAPTIVE_SCALE).save(out / "ic_launcher_monochrome.png")

    draw(1024).save(ROOT / "tools" / "icon_preview.png")
    print("icons written")


if __name__ == "__main__":
    main()
