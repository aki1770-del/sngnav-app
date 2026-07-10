#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# make_placeholder_mbtiles.py
#
#
# SUPERSEDED 2026-07-10: the bundled asset is now REAL OSM cartography
# (assets/tiles/akita_offline.mbtiles) built by tool/extract_akita.py +
# tool/render_akita_mbtiles.py. This placeholder generator is kept for
# the record of the wiring-PoC era only.
# Generate a valid, standard-schema MBTiles archive of HONEST PLACEHOLDER
# raster tiles covering a small Akita bbox, so the sngnav-app offline-basemap
# WIRING can be proven (offline_tiles' OfflineTileProvider consumes the bundle
# and the map renders tiles OFFLINE, not blank).
#
# ***  THESE TILES ARE PLACEHOLDERS, NOT REAL AKITA CARTOGRAPHY.  ***
# Every tile image is a grid + the literal text "PLACEHOLDER (EIE: real
# tiles)". There is NO OpenStreetMap render in this environment (gdal /
# tilemaker / an OSM style stack are absent) and NOTHING is downloaded from
# the public OSM tile server (tile.openstreetmap.org) — that usage policy is
# exactly what the tileset-provenance escalation avoided. Real Akita/Tohoku
# raster tiles are EIE's Geofabrik-extract ODbL-render production; this script
# only proves the MECHANISM (schema + provider consumption + offline render).
#
# Standard MBTiles schema (github.com/mapbox/mbtiles-spec):
#   metadata(name text PRIMARY KEY, value text)      -- name/format/bounds/...
#   tiles(zoom_level, tile_column, tile_row, tile_data)  -- tile_row is TMS Y
#
# The Y stored in `tile_row` is TMS (flipped) Y, per the spec and per the
# offline_tiles resolver, which queries getTile(z, x, y=(2^z-1)-y_xyz).
# ---------------------------------------------------------------------------

import io
import math
import os
import sqlite3
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("Pillow is required: pip install Pillow")

# --- Coverage: a small Akita corridor around HER mother's city -------------
CENTER_LAT = 39.72
CENTER_LON = 140.10
HALF_LAT = 0.09   # ~20 km N-S
HALF_LON = 0.11   # ~19 km E-W at this latitude
WEST = CENTER_LON - HALF_LON
EAST = CENTER_LON + HALF_LON
SOUTH = CENTER_LAT - HALF_LAT
NORTH = CENTER_LAT + HALF_LAT
MIN_ZOOM = 8
MAX_ZOOM = 13
TILE = 256

ATTRIBUTION = "© OpenStreetMap contributors (ODbL) — placeholder render"
OUT_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets", "tiles", "akita_offline_placeholder.mbtiles",
)


def deg2num(lat_deg, lon_deg, zoom):
    """WGS84 lat/lon -> slippy-map XYZ tile (Y=0 at north)."""
    lat_rad = math.radians(lat_deg)
    n = 1 << zoom
    xtile = int((lon_deg + 180.0) / 360.0 * n)
    ytile = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    xtile = max(0, min(n - 1, xtile))
    ytile = max(0, min(n - 1, ytile))
    return xtile, ytile


def _font(size):
    for path in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                pass
    return ImageFont.load_default()


BG = (233, 238, 230)       # pale green-grey "land"
GRID = (176, 190, 168)     # muted grid
BORDER = (120, 140, 110)
INK = (60, 74, 52)
STAMP = (150, 60, 40)      # red-brown "PLACEHOLDER" stamp


def render_tile(z, x, y):
    """256x256 PNG bytes: pale background + grid + honest placeholder text."""
    img = Image.new("RGB", (TILE, TILE), BG)
    d = ImageDraw.Draw(img)
    # inner grid so adjacent tiles visibly tessellate when rendered
    for g in range(0, TILE + 1, 64):
        d.line([(g, 0), (g, TILE)], fill=GRID, width=1)
        d.line([(0, g), (TILE, g)], fill=GRID, width=1)
    d.rectangle([0, 0, TILE - 1, TILE - 1], outline=BORDER, width=2)

    big = _font(18)
    mid = _font(15)
    small = _font(12)
    d.text((10, 12), "AKITA OFFLINE", font=big, fill=INK)
    d.text((10, 40), "z%d/%d/%d" % (z, x, y), font=mid, fill=INK)
    d.text((10, 210), "© OSM (ODbL)", font=small, fill=INK)
    # The honest stamp: this is NOT real cartography.
    d.text((10, 150), "PLACEHOLDER", font=big, fill=STAMP)
    d.text((10, 176), "(EIE: real tiles)", font=small, fill=STAMP)

    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def main():
    if os.path.exists(OUT_PATH):
        os.remove(OUT_PATH)
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)

    db = sqlite3.connect(OUT_PATH)
    cur = db.cursor()
    cur.execute("CREATE TABLE metadata (name text PRIMARY KEY, value text);")
    cur.execute(
        "CREATE TABLE tiles "
        "(zoom_level integer, tile_column integer, tile_row integer, "
        "tile_data blob, "
        "PRIMARY KEY (zoom_level, tile_column, tile_row));"
    )

    meta = {
        "name": "Akita offline placeholder (wiring PoC)",
        "format": "png",
        "minzoom": str(MIN_ZOOM),
        "maxzoom": str(MAX_ZOOM),
        # MBTiles spec bounds order: left,bottom,right,top (W,S,E,N)
        "bounds": "%.5f,%.5f,%.5f,%.5f" % (WEST, SOUTH, EAST, NORTH),
        "center": "%.5f,%.5f,%d" % (CENTER_LON, CENTER_LAT, 12),
        "type": "baselayer",
        "version": "1",
        "attribution": ATTRIBUTION,
        "description": (
            "PLACEHOLDER wiring proof — NOT real Akita cartography. "
            "Grid+text tiles prove the MBTiles schema + offline_tiles "
            "OfflineTileProvider consumption + offline (non-blank) render. "
            "Real Akita/Tohoku raster tiles are EIE's Geofabrik ODbL-render "
            "production. No OSM tile server was contacted; nothing downloaded."
        ),
        "placeholder": "true",
    }
    cur.executemany(
        "INSERT INTO metadata (name, value) VALUES (?, ?);", list(meta.items())
    )

    count = 0
    for z in range(MIN_ZOOM, MAX_ZOOM + 1):
        x_min, y_top = deg2num(NORTH, WEST, z)   # NW corner -> min x, min(xyz)y
        x_max, y_bot = deg2num(SOUTH, EAST, z)   # SE corner -> max x, max(xyz)y
        for x in range(min(x_min, x_max), max(x_min, x_max) + 1):
            for y in range(min(y_top, y_bot), max(y_top, y_bot) + 1):
                png = render_tile(z, x, y)
                tms_y = (1 << z) - 1 - y          # XYZ Y -> TMS Y (flip)
                cur.execute(
                    "INSERT INTO tiles "
                    "(zoom_level, tile_column, tile_row, tile_data) "
                    "VALUES (?, ?, ?, ?);",
                    (z, x, tms_y, sqlite3.Binary(png)),
                )
                count += 1

    db.commit()
    db.close()

    size = os.path.getsize(OUT_PATH)
    print("PLACEHOLDER MBTiles (NOT real Akita cartography):")
    print("  path        : %s" % OUT_PATH)
    print("  bbox W,S,E,N : %.5f,%.5f,%.5f,%.5f" % (WEST, SOUTH, EAST, NORTH))
    print("  zoom levels  : z%d..z%d" % (MIN_ZOOM, MAX_ZOOM))
    print("  tile count   : %d" % count)
    print("  file size    : %d bytes (%.1f KiB)" % (size, size / 1024.0))


if __name__ == "__main__":
    main()
