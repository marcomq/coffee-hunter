#!/usr/bin/env python3
"""Measure the real frame rectangles of the generated hero sprite sheets.

The sheets are not laid out on an even 4x4 grid: the figures drift, and slicing
by `size / 4` drags the next row's hat into the frame above it. This prints the
`HERO_SHEET_FRAMES` table for scripts/main.gd. Re-run it whenever a sheet is
regenerated.

    uvx --with pillow python tools/measure_hero_frames.py
"""

from PIL import Image

SHEETS = [
    ("HERO_TEXTURE", "assets/art/source/hero-walk-sheet-v1.png"),
    ("HERO_COFFEE_CHARGE_TEXTURE", "assets/art/source/hero-coffee-charge-sheet-v1.png"),
    ("HERO_COFFEE_THROW_TEXTURE", "assets/art/source/hero-coffee-throw-sheet-v1.png"),
]
ALPHA_FLOOR = 40
GRID = 4


def bands(flags):
    """Runs of True in `flags`, as [start, end) pairs."""
    out, start = [], None
    for i, on in enumerate(flags):
        if on and start is None:
            start = i
        elif not on and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, len(flags)))
    return out


def spans(mask, w, h, along_rows):
    """One [start, end) span per row (or column) of the grid, merged over the
    strips of the other axis so every frame in a row shares one rectangle."""
    merged = [None] * GRID
    for strip in range(GRID):
        lo = int(strip * (h if not along_rows else w) / GRID)
        hi = int((strip + 1) * (h if not along_rows else w) / GRID)
        if along_rows:
            flags = [any(mask[y][x] for x in range(lo, hi)) for y in range(h)]
        else:
            flags = [any(mask[y][x] for y in range(lo, hi)) for x in range(w)]
        found = bands(flags)
        if len(found) != GRID:
            # Rows that touch (a mug thrown low into the row below) merge into
            # one band; fall back to the nominal split for those.
            found = [(int(i * len(flags) / GRID), int((i + 1) * len(flags) / GRID)) for i in range(GRID)]
        for i, (start, end) in enumerate(found):
            if merged[i] is None:
                merged[i] = [start, end]
            else:
                merged[i][0] = min(merged[i][0], start)
                merged[i][1] = max(merged[i][1], end)
    # Where neighbours overlap, split the difference: neither may reach into the
    # other, which is the whole point of measuring.
    for i in range(GRID - 1):
        if merged[i][1] > merged[i + 1][0]:
            middle = (merged[i][1] + merged[i + 1][0]) // 2
            merged[i][1] = middle
            merged[i + 1][0] = middle
    return [tuple(s) for s in merged]


def main():
    print("const HERO_SHEET_FRAMES := {")
    for name, path in SHEETS:
        im = Image.open(path).convert("RGBA")
        w, h = im.size
        alpha = im.split()[3].load()
        mask = [[alpha[x, y] > ALPHA_FLOOR for x in range(w)] for y in range(h)]
        rows = spans(mask, w, h, along_rows=True)
        cols = spans(mask, w, h, along_rows=False)
        width = max(end - start for start, end in cols)
        xs = []
        for i, (start, end) in enumerate(cols):
            x = start - (width - (end - start)) // 2
            low = 0 if i == 0 else cols[i - 1][1]
            xs.append(max(low, min(x, w - width)))
        ys = [start for start, _ in rows]
        heights = [end - start for start, end in rows]
        print("\t%s: {" % name)
        print('\t\t"x": %s, "width": %d,' % (xs, width))
        print('\t\t"y": %s, "heights": %s,' % (ys, heights))
        print("\t},")
    print("}")


if __name__ == "__main__":
    main()
