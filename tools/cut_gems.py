#!/usr/bin/env python3
"""Cuts a 3x2 gem sheet on a flat magenta background into the addon's six gem textures.

Usage: python3 tools/cut_gems.py <sheet.png> [out_dir]   (needs Pillow + numpy)
Sheet order: Amber, Amethyst, Emerald / Ruby, Sapphire, Topaz. Output: 128 px RGBA TGA, uncompressed
(media/gems/<Name>.tga). The background is flood-filled from the border, so gem colours close to
magenta (amethyst) survive; a 1 px fringe is eaten and the soft edge despilled.
"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

NAMES = [["Amber", "Amethyst", "Emerald"], ["Ruby", "Sapphire", "Topaz"]]
SIZE, MARGIN = 128, 6


def runs(v, min_len=40):
    out, start = [], None
    for i, x in enumerate(v):
        if x and start is None:
            start = i
        if not x and start is not None:
            if i - start > min_len:
                out.append((start, i))
            start = None
    if start is not None:
        out.append((start, len(v)))
    return out


def main():
    src = Image.open(sys.argv[1]).convert("RGB")
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "media/gems"
    w, h = src.size
    mark = (0, 255, 0)
    flood = src.copy()
    for seed in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]:
        if flood.getpixel(seed) != mark:
            ImageDraw.floodfill(flood, seed, mark, thresh=110)
    a = np.asarray(src).astype(np.float32)
    bg = np.all(np.asarray(flood) == np.array(mark), axis=2)
    bg &= np.sqrt(((a - np.array([255, 0, 255])) ** 2).sum(axis=2)) < 200
    alpha = Image.fromarray(((~bg) * 255).astype(np.uint8), "L")
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    al = np.asarray(alpha).astype(np.float32) / 255
    spill = np.clip(np.minimum(a[..., 0], a[..., 2]) - a[..., 1], 0, 255) * (al < 0.97)
    a[..., 0] -= spill * 0.85
    a[..., 2] -= spill * 0.85
    full = Image.fromarray(np.dstack([np.clip(a, 0, 255), al * 255]).astype(np.uint8), "RGBA")
    solid = al > 0.5
    rows = runs(solid.any(axis=1))
    if len(rows) != 2:
        sys.exit("expected 2 rows of gems, found %d" % len(rows))
    for ri, (y0, y1) in enumerate(rows):
        cols = runs(solid[y0:y1].any(axis=0))
        if len(cols) != 3:
            sys.exit("expected 3 gems in row %d, found %d" % (ri + 1, len(cols)))
        for ci, (x0, x1) in enumerate(cols):
            gem = full.crop((x0 - 4, y0 - 4, x1 + 4, y1 + 4))
            gem = gem.crop(gem.getbbox())
            k = min((SIZE - 2 * MARGIN) / gem.width, (SIZE - 2 * MARGIN) / gem.height)
            gem = gem.resize((round(gem.width * k), round(gem.height * k)), Image.LANCZOS)
            out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
            out.paste(gem, ((SIZE - gem.width) // 2, (SIZE - gem.height) // 2), gem)
            path = "%s/%s.tga" % (out_dir, NAMES[ri][ci])
            out.save(path, compression=None)
            print("wrote", path)


main()
