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
    def __init__(self, way_net=None):
        super().__init__()
        self.lines = []   # {c: class, p: [[lon,lat],...], r?, n?, b?, t?}
        self.waterpoly = []
        self.places = []  # {c, n, lon, lat}
        self.nways = 0
        self.way_net = way_net or {}

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
        if cls is None:
            return
        pts = self._coords(w)
        if len(pts) >= 2 and self._clip_hit(pts):
            feat = {'c': cls, 'p': pts}
            # Driver-service extras (2026-07-10): the route number is the one
            # datum a GPS-less driver can match to the physical 国道 sign;
            # bridges freeze before the road around them; tunnels change
            # what she sees. Carried as attributes, styled at render time.
            if 'highway' in tags:
                ref = tags.get('ref')
                if ref:
                    feat['r'] = ref.split(';')[0].strip()
                    net = self.way_net.get(w.id)
                    if net:
                        feat['n'] = net
                # bridge=yes|viaduct|... all freeze first; only 'no' is not a
                # bridge. tunnel=no / tunnel=culvert are NOT tunnels the
                # driver passes through (map review 2026-07-10).
                if tags.get('bridge') not in (None, 'no'):
                    feat['b'] = 1
                if tags.get('tunnel') not in (None, 'no', 'culvert'):
                    feat['t'] = 1
            self.lines.append(feat)


    def area(self, a):
        """Water bodies via assembled AREAS — closed ways AND multipolygon
        relations. The way-only version missed every relation lake (田沢湖,
        十和田湖, 宝仙湖, … — 393 relations in the Tohoku extract): the map
        asserted land over Japan's deepest lake (caught by the
        2026-07-10 map review). Inner rings (islands) are kept and punched back to land
        at render time."""
        tags = a.tags
        if not (tags.get('natural') == 'water'
                or tags.get('landuse') == 'reservoir'):
            return
        for outer in a.outer_rings():
            opts = []
            for n in outer:
                try:
                    opts.append((round(n.lon, 6), round(n.lat, 6)))
                except osmium.InvalidLocationError:
                    continue
            if len(opts) < 3 or not self._clip_hit(opts):
                continue
            inners = []
            for inner in a.inner_rings(outer):
                ipts = []
                for n in inner:
                    try:
                        ipts.append((round(n.lon, 6), round(n.lat, 6)))
                    except osmium.InvalidLocationError:
                        continue
                if len(ipts) >= 3:
                    inners.append(ipts)
            self.waterpoly.append({'o': opts, 'i': inners})


class RouteNetworkScan(osmium.SimpleHandler):
    """Pre-scan pass: route relations carry the network class the way tags
    cannot — 国道 (JP:national) vs 県道 (JP:prefectural). Same numbers exist
    in both (国道13 and 県道13 both run near 大曲), and a shield claiming
    国道 on a 県道 lets a GPS-less driver confirm the WRONG road (adversarial map review 2026-07-10). A separate relations-only pass (not a
    callback on the main handler) because area assembly makes the main
    apply_file two-pass and relation() fires before way() has built any
    id map — measured, not assumed: the callback version stamped 0 of
    30,010 refs. Real tag values measured in the cut: 'JP:national' (352),
    'JP:prefectural[:pref]' (120), 'JP:E'/'JP:national:expressway' (9)."""

    RANK = {'exp': 0, 'nat': 1, 'pref': 2}

    def __init__(self):
        super().__init__()
        self.way_net = {}

    def relation(self, rel):
        tags = rel.tags
        if tags.get('type') != 'route' or tags.get('route') != 'road':
            return
        network = tags.get('network', '').lower()
        if network == 'jp:e' or 'expressway' in network:
            net = 'exp'
        elif network.startswith('jp:national'):
            net = 'nat'
        elif network.startswith('jp:prefectural'):
            net = 'pref'
        else:
            return
        for m in rel.members:
            if m.type != 'w':
                continue
            cur = self.way_net.get(m.ref)
            if cur is None or self.RANK[net] < self.RANK[cur]:
                self.way_net[m.ref] = net

def main(pbf, out, cut='unpinned'):
    scan = RouteNetworkScan()
    scan.apply_file(pbf)
    print('route-network ways stamped:', len(scan.way_net))
    h = Handler(way_net=scan.way_net)
    h.apply_file(pbf, locations=True, idx='flex_mem')
    data = {'bbox': [LON_MIN, LAT_MIN, LON_MAX, LAT_MAX],
            'source_cut': cut,
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
    # argv[3]: the Geofabrik cut label (e.g. 'tohoku-260709') — PIN IT:
    # 'tohoku-latest' is a moving target; the cut travels into the MBTiles
    # metadata so the shipped map's provenance is reproducible.
    main(sys.argv[1], sys.argv[2],
         sys.argv[3] if len(sys.argv) > 3 else 'unpinned')
