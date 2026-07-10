# Offline Akita basemap — regeneration runbook

The shipped `assets/tiles/akita_offline.mbtiles` is fully reproducible from
a pinned public input. No OSM tile server is contacted at any step.
Data © OpenStreetMap contributors, ODbL 1.0.

## Pinned input

| What | Value |
|---|---|
| Extract | Geofabrik Tohoku, cut **tohoku-260709** |
| URL | `https://download.geofabrik.de/asia/japan/tohoku-260709.osm.pbf` |
| sha256 | `8d23fe35fe14b90a9d62c28b2ce3a7ea62fdff7401ee4a081b34c780af471006` |
| Size | 304,122,012 bytes |

`tohoku-latest.osm.pbf` is a moving target — always regenerate from a dated
cut and pass its label as the third argument so it lands in the archive
metadata (`source_cut`).

## Dependencies

Python 3.12 venv with: `osmium` (pyosmium), `pillow`, `shapely`
(**shapely is mandatory** — sea fill polygonization uses it even without
the boundary input). A CJK font must be installed for ja labels
(IPAGothic or Noto CJK; see FONT_CANDIDATES in the renderer).

## Steps

```bash
python -m venv venv && venv/bin/pip install osmium pillow shapely
venv/bin/python tool/extract_akita.py tohoku-260709.osm.pbf extract.json tohoku-260709
venv/bin/python tool/extract_akita_boundary.py tohoku-260709.osm.pbf boundary.json
venv/bin/python tool/render_akita_mbtiles.py extract.json akita_offline.mbtiles boundary.json
```

## Verify before shipping (the renderer enforces #1 itself)

1. **Sea-fill sanity**: the renderer prints `sea fraction of bbox: NN%` and
   REFUSES to render outside 2%–65% — a broken coastline in a future cut
   must fail loud, never silently flood or blank the map.
2. **Tile counts** (this cut): z8=6, z9=15, z10=54, z11=176, z12=672,
   z13=629 (city window + selective rural within the 秋田県 boundary);
   total 1,552; ~16.3 MB.
3. **Look at the tiles yourself — do not skip**: 田沢湖 as water
   (z11 @ 140.66,39.72); sea filled + データ範囲外 tint west of the coast
   (z9 @ 139.9,39.9); 国道13 blue plate vs unverified grey ref near 大仙
   (z12 @ 140.48,39.45); a 県道 blue hexagon (z12 @ 140.21,39.65).
4. `flutter test` — the archive contract test pins metadata + coverage;
   the render_see capture pins the offline pixel path.

## Shield honesty rule (do not weaken)

A route number renders as 国道 blue ONLY when an OSM route relation
(`network=JP:national`) verifies it, or the way class is motorway/trunk
(Japan-OSM convention trunk=国道, measured 33/33 in this cut). 県道 =
blue hexagon via `JP:prefectural*` relations. Anything unverified renders
grey — the map must never let a driver confirm the WRONG road against a
physical 国道 sign. 国道 and 県道 share numbers (both a 国道13 and a
prefectural route 13 run near 大曲); an adversarial review caught the
first version of this renderer painting them identically.

## Refresh policy

Regenerate on a new dated cut when a road-network defect is reported, or
at least once per release train; roads change. Update the pinned row above
and the tile counts; re-run the own-eyes list.
