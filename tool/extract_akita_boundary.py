#!/usr/bin/env python3
"""Extract the 秋田県 administrative boundary (multipolygon) from a Geofabrik
Tohoku .osm.pbf → JSON [[outer_ring], ...] (rings of [lon, lat]).

Used by render_akita_mbtiles.py's selective-z13 mode (PP4, vision-alignment
gate 2026-07-10): rural deep-zoom tiles are clipped to the prefecture so
neighbor-prefecture slivers in the bbox are not rendered for no cohort.

Data © OpenStreetMap contributors, ODbL 1.0.
"""
import json
import sys

import osmium


class Handler(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.rings = []

    def area(self, a):
        t = a.tags
        if not (t.get('boundary') == 'administrative'
                and t.get('admin_level') == '4'
                and t.get('name') == '秋田県'):
            return
        for outer in a.outer_rings():
            pts = []
            for n in outer:
                try:
                    pts.append((round(n.lon, 6), round(n.lat, 6)))
                except osmium.InvalidLocationError:
                    continue
            if len(pts) >= 3:
                self.rings.append(pts)


def main(pbf, out):
    h = Handler()
    h.apply_file(pbf, locations=True, idx='flex_mem')
    with open(out, 'w') as f:
        json.dump(h.rings, f, separators=(',', ':'))
    print('akita boundary outer rings:', len(h.rings),
          'total points:', sum(len(r) for r in h.rings))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
