#!/usr/bin/env python3
"""Render real Akita raster tiles (MBTiles, png) from extract_akita.py JSON.

Minimal honest cartography — real OSM geometry, simple styling:
water fill + rivers (blue), coastline, rail (dashed grey), roads by class,
place labels (ja) at zoom-appropriate levels. 256px tiles rendered at 2x and
downscaled for antialiasing. TMS row order per the MBTiles spec.

Coverage: Akita prefecture bbox z8-z12, plus z13 at the app's Akita-city
window (139.99..140.21, 39.63..39.81). With a boundary JSON (argv[3], from
extract_akita_boundary.py) z13 additionally covers, prefecture-wide, every
tile that carries a motorway/trunk/primary road or a place label AND
intersects the 秋田県 boundary — the PP4 rural deep-zoom dignity repair
(vision-alignment gate 2026-07-10): the anchor cohort's rural roads get the
same z13 the city has, without rendering neighbor-prefecture slivers.

Data © OpenStreetMap contributors, ODbL 1.0 (Geofabrik Tohoku extract).
"""
import json
import math
import os
import sqlite3
import sys
from io import BytesIO

from PIL import Image, ImageDraw, ImageFont

PREF = (139.40, 38.70, 141.20, 40.80)
CITY = (139.99, 39.63, 140.21, 39.81)

SS = 2          # supersample factor
TILE = 256

# class -> (min zoom, color, base width px at z12, label?)
LINE_STYLE = {
    'motorway':  (8,  (216, 130, 60),  5.0),
    'trunk':     (8,  (220, 150, 70),  4.2),
    'primary':   (9,  (235, 185, 90),  3.6),
    'secondary': (10, (200, 200, 120), 3.0),
    'tertiary':  (11, (180, 180, 180), 2.4),
    'minor':     (12, (200, 200, 200), 1.8),
    'rail':      (10, (120, 120, 130), 1.6),
    'river':     (10, (120, 170, 220), 2.0),
    'coast':     (8,  (90, 140, 200),  2.4),
}
LABEL_MINZOOM = {'city': 8, 'town': 11, 'village': 12}
LABEL_SIZE = {'city': 15, 'town': 12, 'village': 11}
LAND = (248, 246, 242)
WATER = (190, 215, 235)

FONT_CANDIDATES = [
    '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc',
]


def lonlat_to_global_px(lon, lat, z):
    n = 2.0 ** z * TILE
    x = (lon + 180.0) / 360.0 * n
    lat = max(min(lat, 85.05), -85.05)
    s = math.sin(math.radians(lat))
    y = (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * n
    return x, y


def tile_range(bbox, z):
    x0, y0 = lonlat_to_global_px(bbox[0], bbox[3], z)
    x1, y1 = lonlat_to_global_px(bbox[2], bbox[1], z)
    return (int(x0 // TILE), int(y0 // TILE),
            int(x1 // TILE), int(y1 // TILE))


def load_font(size):
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                continue
    return ImageFont.load_default()


def width_for(z, base):
    return max(1, base * SS * (2.0 ** (z - 12)) if z < 12 else base * SS)


def bucket_features(data, z, grid):
    """Assign each feature to the tiles its bbox overlaps at zoom z."""
    xt0, yt0, xt1, yt1 = grid
    buckets = {}
    for feat in data['lines']:
        style = LINE_STYLE[feat['c']]
        if z < style[0]:
            continue
        px = [lonlat_to_global_px(lon, lat, z) for lon, lat in feat['p']]
        xs = [p[0] for p in px]
        ys = [p[1] for p in px]
        pad = width_for(z, style[2]) / SS + 2
        for tx in range(max(xt0, int((min(xs) - pad) // TILE)),
                        min(xt1, int((max(xs) + pad) // TILE)) + 1):
            for ty in range(max(yt0, int((min(ys) - pad) // TILE)),
                            min(yt1, int((max(ys) + pad) // TILE)) + 1):
                buckets.setdefault((tx, ty), {'lines': [], 'water': [],
                                              'places': []})['lines'].append(
                    (feat['c'], px))
    for poly in data['water']:
        if z < 9:
            continue
        opx = [lonlat_to_global_px(lon, lat, z) for lon, lat in poly['o']]
        xs = [p[0] for p in opx]
        ys = [p[1] for p in opx]
        # skip sub-pixel ponds
        if max(xs) - min(xs) < 2 and max(ys) - min(ys) < 2:
            continue
        entry = {'o': opx,
                 'i': [[lonlat_to_global_px(lon, lat, z) for lon, lat in ring]
                       for ring in poly['i']]}
        for tx in range(max(xt0, int(min(xs) // TILE)),
                        min(xt1, int(max(xs) // TILE)) + 1):
            for ty in range(max(yt0, int(min(ys) // TILE)),
                            min(yt1, int(max(ys) // TILE)) + 1):
                buckets.setdefault((tx, ty), {'lines': [], 'water': [],
                                              'places': []})['water'].append(
                    entry)
    for pl in data['places']:
        if z < LABEL_MINZOOM[pl['c']]:
            continue
        x, y = lonlat_to_global_px(pl['x'], pl['y'], z)
        # a label can spill into neighbours; bucket a 1-tile halo
        for tx in range(int(x // TILE) - 1, int(x // TILE) + 2):
            for ty in range(int(y // TILE) - 1, int(y // TILE) + 2):
                if xt0 <= tx <= xt1 and yt0 <= ty <= yt1:
                    buckets.setdefault((tx, ty), {'lines': [], 'water': [],
                                                  'places': []})[
                        'places'].append((pl, x, y))
    return buckets


DRAW_ORDER = ['coast', 'river', 'rail', 'minor', 'tertiary', 'secondary',
              'primary', 'trunk', 'motorway']


def render_tile(tx, ty, z, content, fonts):
    img = Image.new('RGB', (TILE * SS, TILE * SS), LAND)
    draw = ImageDraw.Draw(img)
    ox, oy = tx * TILE, ty * TILE

    def to_local(px):
        return [((x - ox) * SS, (y - oy) * SS) for x, y in px]

    for poly in content['water']:
        pts = to_local(poly['o'])
        if len(pts) >= 3:
            draw.polygon(pts, fill=WATER)
        # inner rings = islands: punch back to land
        for ring in poly['i']:
            ipts = to_local(ring)
            if len(ipts) >= 3:
                draw.polygon(ipts, fill=LAND)
    by_class = {}
    for cls, px in content['lines']:
        by_class.setdefault(cls, []).append(px)
    for cls in DRAW_ORDER:
        if cls not in by_class:
            continue
        _, color, base = LINE_STYLE[cls]
        w = int(round(width_for(z, base)))
        for px in by_class[cls]:
            pts = to_local(px)
            if len(pts) >= 2:
                draw.line(pts, fill=color, width=w, joint='curve')
    for pl, gx, gy in content['places']:
        f = fonts[pl['c']]
        x, y = (gx - ox) * SS, (gy - oy) * SS
        r = 2.5 * SS
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(70, 70, 70))
        # halo for readability
        tx_, ty_ = x + 5 * SS, y - LABEL_SIZE[pl['c']] * SS * 0.7
        for dx in (-SS, 0, SS):
            for dy in (-SS, 0, SS):
                draw.text((tx_ + dx, ty_ + dy), pl['n'],
                          font=f, fill=(255, 255, 255))
        draw.text((tx_, ty_), pl['n'], font=f, fill=(40, 40, 40))
    img = img.resize((TILE, TILE), Image.LANCZOS)
    # Palette-quantize: these flat-styled tiles compress ~3-4x smaller with no
    # visible loss, keeping the bundled APK asset honest in size.
    img = img.convert('P', palette=Image.ADAPTIVE, colors=64)
    buf = BytesIO()
    img.save(buf, 'PNG', optimize=True)
    return buf.getvalue()


# z13 selective mode: road classes that earn a rural deep-zoom tile.
Z13_SELECT_CLASSES = {'motorway', 'trunk', 'primary'}


def load_boundary(boundary_json):
    """秋田県 outer rings → prepared shapely geometry (import kept local so
    the boundary-less render path needs no shapely)."""
    from shapely.geometry import MultiPolygon, Polygon
    from shapely.prepared import prep
    with open(boundary_json) as f:
        rings = json.load(f)
    polys = [Polygon(r) for r in rings if len(r) >= 3]
    return prep(MultiPolygon([p if p.is_valid else p.buffer(0)
                              for p in polys]))


def tile_bounds_lonlat(tx, ty, z):
    n = 2.0 ** z
    def lon(x):
        return x / n * 360.0 - 180.0
    def lat(y):
        t = math.pi * (1 - 2 * y / n)
        return math.degrees(math.atan(math.sinh(t)))
    return lon(tx), lat(ty + 1), lon(tx + 1), lat(ty)


def main(extract_json, out_mbtiles, boundary_json=None):
    with open(extract_json) as f:
        data = json.load(f)
    boundary = load_boundary(boundary_json) if boundary_json else None
    fonts = {c: load_font(LABEL_SIZE[c] * SS) for c in LABEL_SIZE}
    if os.path.exists(out_mbtiles):
        os.remove(out_mbtiles)
    db = sqlite3.connect(out_mbtiles)
    db.execute('CREATE TABLE metadata (name text, value text)')
    db.execute('CREATE TABLE tiles (zoom_level integer, tile_column integer,'
               ' tile_row integer, tile_data blob)')
    db.execute('CREATE UNIQUE INDEX tile_index ON tiles'
               ' (zoom_level, tile_column, tile_row)')

    if boundary is not None:
        from shapely.geometry import box as shapely_box

    total = 0
    for z in range(8, 14):
        bbox = PREF if z <= 12 else CITY
        grid = tile_range(bbox, z)
        xt0, yt0, xt1, yt1 = grid
        coords = {(tx, ty)
                  for tx in range(xt0, xt1 + 1)
                  for ty in range(yt0, yt1 + 1)}
        if z == 13 and boundary is not None:
            pgrid = tile_range(PREF, z)
            buckets = bucket_features(data, z, pgrid)
            for (tx, ty), content in buckets.items():
                if (tx, ty) in coords:
                    continue
                if not (content['places']
                        or any(c in Z13_SELECT_CLASSES
                               for c, _ in content['lines'])):
                    continue
                if boundary.intersects(
                        shapely_box(*tile_bounds_lonlat(tx, ty, z))):
                    coords.add((tx, ty))
        else:
            buckets = bucket_features(data, z, grid)
        n = 0
        for tx, ty in sorted(coords):
            content = buckets.get((tx, ty),
                                  {'lines': [], 'water': [], 'places': []})
            png = render_tile(tx, ty, z, content, fonts)
            tms_y = (2 ** z - 1) - ty
            db.execute('INSERT INTO tiles VALUES (?,?,?,?)',
                       (z, tx, tms_y, sqlite3.Binary(png)))
            n += 1
        total += n
        print(f'z{z}: {n} tiles', flush=True)

    cut = data.get('source_cut', 'unpinned')
    meta = {
        'name': 'Akita offline basemap (OSM render)',
        'source_cut': f'geofabrik/{cut}',
        'format': 'png',
        'minzoom': '8',
        'maxzoom': '13',
        'bounds': f'{PREF[0]:.5f},{PREF[1]:.5f},{PREF[2]:.5f},{PREF[3]:.5f}',
        'center': '140.10000,39.72000,11',
        'type': 'baselayer',
        'version': '2',
        'attribution': '© OpenStreetMap contributors (ODbL 1.0)',
        'description': ('Real OpenStreetMap cartography for Akita prefecture '
                        '(z8-z12) + Akita city window (z13), rendered from '
                        f'the Geofabrik Tohoku extract (cut {cut}) with a '
                        'minimal pure-Python '
                        'style (roads by class, rail, rivers, water, '
                        'coastline, ja place labels). Data (c) OpenStreetMap '
                        'contributors, ODbL 1.0. Style is intentionally '
                        'simple; not a full OSM-carto render.'),
    }
    db.executemany('INSERT INTO metadata VALUES (?,?)', meta.items())
    db.commit()
    db.close()
    print('total tiles:', total)
    print('size MB:', round(os.path.getsize(out_mbtiles) / 1e6, 2))


if __name__ == '__main__':
    # argv[3] (optional): 秋田県 boundary JSON from extract_akita_boundary.py
    # — enables the prefecture-wide selective z13 (PP4).
    main(sys.argv[1], sys.argv[2],
         sys.argv[3] if len(sys.argv) > 3 else None)
