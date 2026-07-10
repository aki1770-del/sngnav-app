#!/usr/bin/env python3
"""Render real Akita raster tiles (MBTiles, png) from extract_akita.py JSON.

Minimal honest cartography — real OSM geometry, simple styling:
SEA fill (polygonized from OSM coastline, water-on-right rule), lakes +
rivers (blue), rail (grey), roads by class, ROUTE-NUMBER shields (the one
datum a GPS-less driver can match to the physical 国道 sign), bridge
casings + tunnel dashes (bridges freeze before the road around them —
styled as map features, never warnings), ja place labels. 256px tiles
rendered at 2x and downscaled. TMS row order per the MBTiles spec.

Coverage: Akita prefecture bbox z8-z12, plus z13 at the app's Akita-city
window (139.99..140.21, 39.63..39.81). With a boundary JSON (argv[3], from
extract_akita_boundary.py) z13 additionally covers, prefecture-wide, every
tile that carries a motorway/trunk/primary road or a place label AND
intersects the 秋田県 boundary — rural deep-zoom parity
(2026-07-10): a rural driver's rural roads get the
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

# class -> (min zoom, color, base width px at z12)
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
# Outside the data bbox: honest no-data tint — must read as neither land nor
# sea (a land-colored void beside filled sea painted a phantom landmass west
# of Akita; caught by own-eyes on the z9 coast tile, 2026-07-10).
NODATA = (226, 227, 231)
BRIDGE_CASING = (70, 70, 75)

# Route shields (2026-07-10): min zoom per carrying class.
SHIELD_MINZOOM = {'motorway': 10, 'trunk': 10, 'primary': 11, 'secondary': 12}
SHIELD_RANK = {'motorway': 0, 'trunk': 1, 'primary': 2, 'secondary': 3}
SHIELD_EXPRESSWAY = (0, 105, 62)     # Japan expressway green (E-codes)
SHIELD_NATIONAL = (26, 95, 171)      # 国道 blue (rounded rect, like the sign)
SHIELD_PREF = (26, 95, 171)          # 県道 sign is ALSO blue — a HEXAGON
SHIELD_OTHER = (120, 120, 125)       # network unverified: claim nothing
MAX_SHIELDS_PER_TILE = 4
SHIELD_EDGE_MARGIN = 14              # px at 1x: skip seam-truncated shields


def shield_style(ref, cls, net):
    """(fill, shape) for a route shield. map-review fix (2026-07-10):
    国道 and 県道 share numbers (国道13/県道13 near 大曲); an identical blue
    shield on a 県道 lets a GPS-less driver confirm the WRONG road. Style
    follows the PHYSICAL signs she matches against: 国道 = blue rounded
    onigiri-like plate, 県道 = blue hexagon. Network comes from OSM route
    relations; a numeric ref with NO relation stays grey EXCEPT on
    motorway/trunk, where Japan-OSM convention trunk=国道 held 33/33 in
    this cut — always failing toward NOT claiming 国道."""
    if ref[:1] in ('E', 'C'):
        return SHIELD_EXPRESSWAY, 'rect'
    if net == 'nat':
        return SHIELD_NATIONAL, 'rect'
    if net == 'pref':
        return SHIELD_PREF, 'hex'
    if net == 'exp':
        return SHIELD_EXPRESSWAY, 'rect'
    if ref.isdigit() and cls in ('motorway', 'trunk'):
        return SHIELD_NATIONAL, 'rect'
    return SHIELD_OTHER, 'rect'

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


def tile_bounds_lonlat(tx, ty, z):
    n = 2.0 ** z
    def lon(x):
        return x / n * 360.0 - 180.0
    def lat(y):
        t = math.pi * (1 - 2 * y / n)
        return math.degrees(math.atan(math.sinh(t)))
    return lon(tx), lat(ty + 1), lon(tx + 1), lat(ty)


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


# ---------------------------------------------------------------------------
# Sea fill (2026-07-10) — polygonize the OSM coastline against
# the bbox frame; classify faces by the OSM invariant "water lies on the
# RIGHT of the coastline direction". No external land-polygons DATA download
# (the coastline we already extract IS the land/sea truth); the shapely
# LIBRARY is a mandatory pipeline dependency since this feature.

def build_sea_polygons(data):
    from shapely.geometry import LineString, MultiLineString, box as sbox
    from shapely.ops import linemerge, polygonize, unary_union

    raw = [LineString(l['p']) for l in data['lines']
           if l['c'] == 'coast' and len(l['p']) >= 2]
    if not raw:
        return []
    # Merge touching coastline ways into continuous lines: the side test is
    # fragile at way endpoints, and merging keeps the projected foot away
    # from artificial breaks (map review 2026-07-10).
    merged = linemerge(MultiLineString([g for r in raw for g in
                                        (getattr(r, 'geoms', None) or [r])]))
    coasts = list(getattr(merged, 'geoms', None) or [merged])
    frame = sbox(*data['bbox'])
    faces = [f for f in polygonize(unary_union(coasts + [frame.boundary]))
             if f.intersects(frame)]

    def is_sea(face):
        rp = face.representative_point()
        best, best_d = None, None
        for c in coasts:
            d = c.distance(rp)
            if best_d is None or d < best_d:
                best, best_d = c, d
        eps = 1e-4
        # clamp away from endpoints so the direction segment never
        # degenerates (endpoint clamp made a==f and the cross test noise)
        s = min(max(best.project(rp), eps), best.length - eps)
        a = best.interpolate(s - eps)
        b = best.interpolate(s + eps)
        f = best.interpolate(s)
        # cross of (direction, foot->point): >0 left (land), <0 right (sea)
        cross = ((b.x - a.x) * (rp.y - f.y) - (b.y - a.y) * (rp.x - f.x))
        return cross < 0

    sea = []
    for face in faces:
        if is_sea(face):
            clipped = face.intersection(frame)
            if clipped.is_empty:
                continue
            geoms = getattr(clipped, 'geoms', [clipped])
            for g in geoms:
                if g.geom_type == 'Polygon':
                    sea.append(g)

    # Regeneration guard: a broken coastline in a future cut must fail LOUD,
    # never silently flood the land or blank the sea. Akita's sea share of
    # this bbox is ~1/4; tolerate wide drift but not nonsense.
    frac = sum(p.area for p in sea) / frame.area
    if not 0.02 <= frac <= 0.65:
        raise RuntimeError(
            f'sea-fill sanity failed: sea covers {frac:.1%} of the bbox '
            f'(expected 2%-65%). Coastline in this cut is suspect — do NOT '
            f'ship this render.')
    print(f'sea fraction of bbox: {frac:.1%}', flush=True)
    return sea


def sea_for_zoom(sea_polys, z):
    """Simplified sea rings per zoom: tolerance ≈ half a screen pixel."""
    tol = 360.0 / (2 ** z * TILE) * 0.5
    rings = []
    for p in sea_polys:
        s = p.simplify(tol, preserve_topology=True)
        if s.is_empty:
            continue
        for g in getattr(s, 'geoms', [s]):
            if g.geom_type == 'Polygon' and len(g.exterior.coords) >= 3:
                rings.append({'o': list(g.exterior.coords),
                              'i': [list(r.coords) for r in g.interiors
                                    if len(r.coords) >= 3]})
    return rings


def empty_bucket():
    return {'lines': [], 'water': [], 'places': [], 'sea': []}


def bucket_features(data, z, grid, sea_rings=None):
    """Assign each feature to the tiles its bbox overlaps at zoom z."""
    xt0, yt0, xt1, yt1 = grid
    buckets = {}

    def bucket_ring_entry(entry, xs, ys):
        for tx in range(max(xt0, int(min(xs) // TILE)),
                        min(xt1, int(max(xs) // TILE)) + 1):
            for ty in range(max(yt0, int(min(ys) // TILE)),
                            min(yt1, int(max(ys) // TILE)) + 1):
                yield tx, ty

    for ring in (sea_rings or []):
        opx = [lonlat_to_global_px(lon, lat, z) for lon, lat in ring['o']]
        xs = [p[0] for p in opx]
        ys = [p[1] for p in opx]
        entry = {'o': opx,
                 'i': [[lonlat_to_global_px(lon, lat, z) for lon, lat in r]
                       for r in ring['i']]}
        for tx, ty in bucket_ring_entry(entry, xs, ys):
            buckets.setdefault((tx, ty), empty_bucket())['sea'].append(entry)

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
                buckets.setdefault((tx, ty), empty_bucket())['lines'].append(
                    (feat, px))

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
        for tx, ty in bucket_ring_entry(entry, xs, ys):
            buckets.setdefault((tx, ty), empty_bucket())['water'].append(entry)

    for pl in data['places']:
        if z < LABEL_MINZOOM[pl['c']]:
            continue
        x, y = lonlat_to_global_px(pl['x'], pl['y'], z)
        # a label can spill into neighbours; bucket a 1-tile halo
        for tx in range(int(x // TILE) - 1, int(x // TILE) + 2):
            for ty in range(int(y // TILE) - 1, int(y // TILE) + 2):
                if xt0 <= tx <= xt1 and yt0 <= ty <= yt1:
                    buckets.setdefault((tx, ty), empty_bucket())[
                        'places'].append((pl, x, y))
    return buckets


DRAW_ORDER = ['coast', 'river', 'rail', 'minor', 'tertiary', 'secondary',
              'primary', 'trunk', 'motorway']


def draw_dashed(draw, pts, color, width, on=8.0, off=5.0):
    """Manual dashed polyline (Pillow has no native dashes)."""
    period = on + off
    carry = 0.0
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        seg = math.hypot(x1 - x0, y1 - y0)
        if seg == 0:
            continue
        ux, uy = (x1 - x0) / seg, (y1 - y0) / seg
        t = 0.0
        while t < seg:
            phase = (carry + t) % period
            if phase < on:
                run = min(on - phase, seg - t)
                draw.line([(x0 + ux * t, y0 + uy * t),
                           (x0 + ux * (t + run), y0 + uy * (t + run))],
                          fill=color, width=width)
                t += run
            else:
                t += period - phase
        carry = (carry + seg) % period


def lighten(color, amt=0.45):
    return tuple(int(c + (255 - c) * amt) for c in color)


def draw_shield(draw, sx, sy, ref, fill, shape, font):
    tb = draw.textbbox((0, 0), ref, font=font)
    tw, th = tb[2] - tb[0], tb[3] - tb[1]
    pad = 3 * SS
    x0, y0 = sx - tw / 2 - pad, sy - th / 2 - pad
    x1, y1 = sx + tw / 2 + pad, sy + th / 2 + pad
    if shape == 'hex':
        # 県道 blue hexagon (flat top/bottom, like the physical sign)
        ext = 4 * SS
        draw.polygon([(x0 - ext, sy), (x0, y0), (x1, y0),
                      (x1 + ext, sy), (x1, y1), (x0, y1)],
                     fill=fill, outline=(255, 255, 255), width=SS)
    else:
        draw.rounded_rectangle([x0, y0, x1, y1], radius=3 * SS,
                               fill=fill, outline=(255, 255, 255), width=SS)
    draw.text((sx - tw / 2 - tb[0], sy - th / 2 - tb[1]), ref,
              font=font, fill=(255, 255, 255))
    return (x0 - 4 * SS, y0, x1 + 4 * SS, y1)


def rects_overlap(a, b):
    return not (a[2] < b[0] or b[2] < a[0] or a[3] < b[1] or b[3] < a[1])


def render_tile(tx, ty, z, content, fonts):
    img = Image.new('RGB', (TILE * SS, TILE * SS), LAND)
    draw = ImageDraw.Draw(img)
    ox, oy = tx * TILE, ty * TILE

    def to_local(px):
        return [((x - ox) * SS, (y - oy) * SS) for x, y in px]

    # Out-of-coverage regions first: neither land nor sea, and SAY so —
    # an unlabeled grey is a key the driver does not have.
    fx0, fy0 = lonlat_to_global_px(PREF[0], PREF[3], z)
    fx1, fy1 = lonlat_to_global_px(PREF[2], PREF[1], z)
    lx0, ly0 = (fx0 - ox) * SS, (fy0 - oy) * SS
    lx1, ly1 = (fx1 - ox) * SS, (fy1 - oy) * SS
    E = TILE * SS
    nodata_rects = []
    if lx0 > 0:
        nodata_rects.append((0, 0, lx0, E))
    if lx1 < E:
        nodata_rects.append((lx1, 0, E, E))
    if ly0 > 0:
        nodata_rects.append((0, 0, E, ly0))
    if ly1 < E:
        nodata_rects.append((0, ly1, E, E))
    for r in nodata_rects:
        draw.rectangle(list(r), fill=NODATA)
    for r in nodata_rects:
        rw, rh = r[2] - r[0], r[3] - r[1]
        if rw * rh >= 0.25 * E * E and rw > 60 * SS and rh > 16 * SS:
            label = 'データ範囲外'
            f = fonts['village']
            tb = draw.textbbox((0, 0), label, font=f)
            draw.text(((r[0] + r[2]) / 2 - (tb[2] - tb[0]) / 2,
                       (r[1] + r[3]) / 2 - (tb[3] - tb[1]) / 2),
                      label, font=f, fill=(150, 150, 158))

    # SEA below everything.
    for poly in content['sea']:
        pts = to_local(poly['o'])
        if len(pts) >= 3:
            draw.polygon(pts, fill=WATER)
        for ring in poly['i']:
            ipts = to_local(ring)
            if len(ipts) >= 3:
                draw.polygon(ipts, fill=LAND)

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
    for feat, px in content['lines']:
        by_class.setdefault(feat['c'], []).append((feat, px))

    structures = z >= 12   # bridge/tunnel styling legible from z12
    for cls in DRAW_ORDER:
        if cls not in by_class:
            continue
        _, color, base = LINE_STYLE[cls]
        w = int(round(width_for(z, base)))
        normal, bridges, tunnels = [], [], []
        for feat, px in by_class[cls]:
            if structures and feat.get('t'):
                tunnels.append(px)
            elif structures and feat.get('b'):
                bridges.append(px)
            else:
                normal.append(px)
        # tunnels: dashed + lightened, visibly "under the ground"
        for px in tunnels:
            pts = to_local(px)
            if len(pts) >= 2:
                draw_dashed(draw, pts, lighten(color), w,
                            on=7.0 * SS, off=4.0 * SS)
        for px in normal:
            pts = to_local(px)
            if len(pts) >= 2:
                draw.line(pts, fill=color, width=w, joint='curve')
        # bridges: dark casing under the road color, drawn above its class
        for px in bridges:
            pts = to_local(px)
            if len(pts) >= 2:
                draw.line(pts, fill=BRIDGE_CASING, width=w + 2 * SS,
                          joint='curve')
                draw.line(pts, fill=color, width=w, joint='curve')

    # Route shields — one per (ref, style): 国道13 and 県道13 in one tile
    # render as TWO distinct shields, never merged (map-review fix, 2026-07-10).
    # Selection is class-ranked before distance so 県道 shields can never
    # crowd out the 国道 artery she is matching signs against; placement
    # samples along segments (not only vertices) so long straight roads
    # still get a shield; seam-margin skip avoids truncated half-numbers.
    shields = {}
    cx, cy = (TILE * SS) / 2, (TILE * SS) / 2
    margin = SHIELD_EDGE_MARGIN * SS
    E = TILE * SS
    for cls in ('motorway', 'trunk', 'primary', 'secondary'):
        if z < SHIELD_MINZOOM.get(cls, 99):
            continue
        rank = SHIELD_RANK[cls]
        for feat, px in by_class.get(cls, []):
            ref = feat.get('r')
            if not ref or len(ref) > 5:
                continue
            fill, shape = shield_style(ref, cls, feat.get('n'))
            key = (ref, shape, fill)
            pts = to_local(px)
            cands = list(pts)
            for (ax, ay), (bx, by) in zip(pts, pts[1:]):
                seg = math.hypot(bx - ax, by - ay)
                steps = int(seg // (48 * SS))
                for i in range(1, steps + 1):
                    f = i / (steps + 1)
                    cands.append((ax + (bx - ax) * f, ay + (by - ay) * f))
            for p in cands:
                if (margin <= p[0] < E - margin
                        and margin <= p[1] < E - margin):
                    d = (p[0] - cx) ** 2 + (p[1] - cy) ** 2
                    cur = shields.get(key)
                    if cur is None or (rank, d) < (cur[0], cur[1]):
                        shields[key] = (rank, d, p, fill, shape)
    sfont = fonts['shield']
    placed = []
    for (ref, _, _), (rank, d, (sx, sy), fill, shape) in sorted(
            shields.items(), key=lambda kv: (kv[1][0], kv[1][1])):
        if len(placed) >= MAX_SHIELDS_PER_TILE:
            break
        tb = draw.textbbox((0, 0), ref, font=sfont)
        w2 = (tb[2] - tb[0]) / 2 + 7 * SS
        h2 = (tb[3] - tb[1]) / 2 + 3 * SS
        rect = (sx - w2, sy - h2, sx + w2, sy + h2)
        if any(rects_overlap(rect, pr) for pr in placed):
            continue
        placed.append(draw_shield(draw, sx, sy, ref, fill, shape, sfont))

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
    """秋田県 outer rings → prepared shapely geometry. (shapely is mandatory
    for the whole pipeline since sea fill; the local import just keeps this
    optional input self-contained.)"""
    from shapely.geometry import MultiPolygon, Polygon
    from shapely.prepared import prep
    with open(boundary_json) as f:
        rings = json.load(f)
    polys = [Polygon(r) for r in rings if len(r) >= 3]
    return prep(MultiPolygon([p if p.is_valid else p.buffer(0)
                              for p in polys]))


def main(extract_json, out_mbtiles, boundary_json=None):
    with open(extract_json) as f:
        data = json.load(f)
    boundary = load_boundary(boundary_json) if boundary_json else None
    fonts = {c: load_font(LABEL_SIZE[c] * SS) for c in LABEL_SIZE}
    fonts['shield'] = load_font(11 * SS)
    sea_polys = build_sea_polygons(data)
    print(f'sea faces: {len(sea_polys)}', flush=True)
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
        sea_rings = sea_for_zoom(sea_polys, z)
        coords = {(tx, ty)
                  for tx in range(xt0, xt1 + 1)
                  for ty in range(yt0, yt1 + 1)}
        if z == 13 and boundary is not None:
            pgrid = tile_range(PREF, z)
            buckets = bucket_features(data, z, pgrid, sea_rings)
            for (tx, ty), content in buckets.items():
                if (tx, ty) in coords:
                    continue
                if not (content['places']
                        or any(f['c'] in Z13_SELECT_CLASSES
                               for f, _ in content['lines'])):
                    continue
                if boundary.intersects(
                        shapely_box(*tile_bounds_lonlat(tx, ty, z))):
                    coords.add((tx, ty))
        else:
            buckets = bucket_features(data, z, grid, sea_rings)
        n = 0
        for tx, ty in sorted(coords):
            content = buckets.get((tx, ty), empty_bucket())
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
        'version': '3',
        'attribution': '© OpenStreetMap contributors (ODbL 1.0)',
        'description': ('Real OpenStreetMap cartography for Akita prefecture '
                        '(z8-z12) + Akita city window (z13, plus selective '
                        'rural z13 within the prefecture boundary when '
                        'built with the boundary input), rendered from '
                        f'the Geofabrik Tohoku extract (cut {cut}) with a '
                        'minimal pure-Python '
                        'style (sea fill from the OSM coastline, roads by '
                        'class, route-number shields, bridge/tunnel '
                        'styling, rail, rivers, lakes, ja place labels). '
                        'Data (c) OpenStreetMap contributors, ODbL 1.0. '
                        'Style is intentionally simple; not a full '
                        'OSM-carto render.'),
    }
    db.executemany('INSERT INTO metadata VALUES (?,?)', meta.items())
    db.commit()
    db.close()
    print('total tiles:', total)
    print('size MB:', round(os.path.getsize(out_mbtiles) / 1e6, 2))


if __name__ == '__main__':
    # argv[3] (optional): 秋田県 boundary JSON from extract_akita_boundary.py
    # — enables the prefecture-wide selective z13 (rural deep-zoom parity).
    main(sys.argv[1], sys.argv[2],
         sys.argv[3] if len(sys.argv) > 3 else None)
