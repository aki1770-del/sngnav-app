#!/usr/bin/env python3
"""Extract Akita-prefecture features from a Geofabrik Tohoku .osm.pbf.

Output: a compact JSON of line features (roads / rail / waterways /
coastline), water polygons, and place-label points, clipped to the Akita
bounding box. Consumed by render_akita_mbtiles.py.

Data © OpenStreetMap contributors, ODbL 1.0.
"""
import json
import sys

import osmium

# Akita prefecture + margin.
LON_MIN, LAT_MIN, LON_MAX, LAT_MAX = 139.40, 38.70, 141.20, 40.80

ROAD_CLASSES = {
    'motorway': 'motorway', 'motorway_link': 'motorway',
    'trunk': 'trunk', 'trunk_link': 'trunk',
    'primary': 'primary', 'primary_link': 'primary',
    'secondary': 'secondary', 'secondary_link': 'secondary',
    'tertiary': 'tertiary', 'tertiary_link': 'tertiary',
    'unclassified': 'minor', 'residential': 'minor', 'service': None,
}
PLACE_CLASSES = {'city': 'city', 'town': 'town', 'village': 'village'}


def in_bbox(lon, lat):
    return LON_MIN <= lon <= LON_MAX and LAT_MIN <= lat <= LAT_MAX


class Handler(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.lines = []   # {c: class, p: [[lon,lat],...]}
        self.waterpoly = []
        self.places = []  # {c, n, lon, lat}
        self.nways = 0

    def _coords(self, way):
        pts = []
        for n in way.nodes:
            try:
                lon, lat = n.lon, n.lat
            except osmium.InvalidLocationError:
                continue
            pts.append((round(lon, 6), round(lat, 6)))
        return pts

    def _clip_hit(self, pts):
        return any(in_bbox(lon, lat) for lon, lat in pts)

    def node(self, n):
        p = n.tags.get('place')
        cls = PLACE_CLASSES.get(p or '')
        if not cls:
            return
        if not in_bbox(n.location.lon, n.location.lat):
            return
        name = n.tags.get('name') or n.tags.get('name:ja') or ''
        if not name:
            return
        self.places.append({'c': cls, 'n': name,
                            'x': round(n.location.lon, 6),
                            'y': round(n.location.lat, 6)})

    def way(self, w):
        self.nways += 1
        tags = w.tags
        cls = None
        if 'highway' in tags:
            cls = ROAD_CLASSES.get(tags['highway'])
        elif tags.get('railway') == 'rail':
            cls = 'rail'
        elif tags.get('waterway') in ('river', 'canal'):
            cls = 'river'
        elif tags.get('natural') == 'coastline':
            cls = 'coast'
        elif tags.get('natural') == 'water' or tags.get('landuse') == 'reservoir':
            pts = self._coords(w)
            if len(pts) >= 3 and self._clip_hit(pts):
                self.waterpoly.append(pts)
            return
        if cls is None:
            return
        pts = self._coords(w)
        if len(pts) >= 2 and self._clip_hit(pts):
            self.lines.append({'c': cls, 'p': pts})


def main(pbf, out):
    h = Handler()
    h.apply_file(pbf, locations=True, idx='flex_mem')
    data = {'bbox': [LON_MIN, LAT_MIN, LON_MAX, LAT_MAX],
            'lines': h.lines, 'water': h.waterpoly, 'places': h.places}
    with open(out, 'w') as f:
        json.dump(data, f, separators=(',', ':'))
    counts = {}
    for l in h.lines:
        counts[l['c']] = counts.get(l['c'], 0) + 1
    print('ways scanned:', h.nways)
    print('line features:', len(h.lines), counts)
    print('water polys:', len(h.waterpoly), 'places:', len(h.places))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
