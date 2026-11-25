# Round NL textures for the native-style window: the emblem on the site blue inside a circle.
# portrait128.tga for the window's portrait, round64.tga for the minimap button.
import sys
from PIL import Image, ImageDraw
src, out = sys.argv[1], sys.argv[2]
em = Image.open(src).convert("RGBA")
bbox = em.getbbox()
em = em.crop(bbox)
BLUE = (0x13, 0x4d, 0x75, 255)
def make(size, frac, name):
    S = size * 4
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    disc = Image.new("RGBA", (S, S), BLUE)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, S - 1, S - 1), fill=255)
    canvas.paste(disc, (0, 0), mask)
    w = int(S * frac)
    h = int(w * em.height / em.width)
    e = em.resize((w, h), Image.LANCZOS)
    canvas.alpha_composite(e, ((S - w) // 2, (S - h) // 2))
    # keep everything inside the circle
    a = canvas.getchannel("A")
    a = Image.composite(a, Image.new("L", (S, S), 0), mask)
    canvas.putalpha(a)
    img = canvas.resize((size, size), Image.LANCZOS)
    img.save(f"{out}/{name}.tga")
    img.resize((256, 256), Image.NEAREST).save(f"/tmp/{name}.png")
make(128, 0.80, "portrait128")
make(64, 0.82, "round64")
