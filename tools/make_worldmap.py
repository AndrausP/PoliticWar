"""Gera src/shared/WorldMap.luau a partir do Natural Earth (tools/data/countries50.geojson).
Uso: python tools/make_worldmap.py"""
import json, os
from collections import Counter
from PIL import Image, ImageDraw

W, H = 800, 320
LAT_TOP, LAT_BOT = 84.0, -60.0
SS = 4  # supersampling
here = os.path.dirname(os.path.abspath(__file__))
data = json.load(open(os.path.join(here, 'data', 'countries50.geojson'), encoding='utf-8'))

feats = []
for f in data['features']:
    p = f['properties']
    if p['NAME'] in ('Antarctica',):
        continue
    g = f['geometry']
    polys = g['coordinates'] if g['type'] == 'MultiPolygon' else [g['coordinates']]
    area = 0
    for poly in polys:
        ring = poly[0]
        a = 0
        for i in range(len(ring)):
            x1, y1 = ring[i - 1]; x2, y2 = ring[i]
            a += x1 * y2 - x2 * y1
        area += abs(a) / 2
    feats.append((area, p.get('NAME_PT') or p['NAME'], polys, float(p.get('POP_EST') or 0), float(p.get('GDP_MD') or 0)))
feats.sort(key=lambda t: -t[0])  # grandes primeiro, pequenos por cima

img = Image.new('I', (W * SS, H * SS), 0)
dr = ImageDraw.Draw(img)
names = []
def proj(lon, lat):
    return ((lon + 180) / 360 * W * SS, (LAT_TOP - lat) / (LAT_TOP - LAT_BOT) * H * SS)
pops, gdps = [], []
for area, name, polys, pop, gdp in feats:
    names.append(name)
    pops.append(round(pop / 1e6, 2))
    gdps.append(round(gdp / 1e3, 1))
    cid = len(names)
    for poly in polys:
        dr.polygon([proj(*pt) for pt in poly[0]], fill=cid)
        for hole in poly[1:]:
            dr.polygon([proj(*pt) for pt in hole], fill=0)

px = img.load()
grid = []
for y in range(H):
    for x in range(W):
        c = Counter(px[x * SS + i, y * SS + j] for i in range(SS) for j in range(SS))
        land = sum(v for k, v in c.items() if k)
        if land >= SS * SS * 0.4:
            cid = max((k for k in c if k), key=lambda k: c[k])
        else:
            cid = 0
        grid.append(cid)

runs, cur, n = [], grid[0], 0
for v in grid:
    if v == cur:
        n += 1
    else:
        runs.append(f'{cur}x{n}'); cur, n = v, 1
runs.append(f'{cur}x{n}')
used = sorted(set(grid) - {0})
print('terra:', sum(1 for v in grid if v), 'de', W * H, '| países com terra:', len(used))

def q(s):
    return json.dumps(s, ensure_ascii=False)
out = os.path.join(here, '..', 'src', 'shared', 'WorldMap.luau')
with open(out, 'w', encoding='utf-8') as f:
    f.write('-- Gerado por tools/make_worldmap.py (Natural Earth, domínio público). Não editar à mão.\n')
    f.write(f'return {{\n\tW = {W},\n\tH = {H},\n\tnames = {{ ' + ', '.join(q(n) for n in names) + ' },\n')
    f.write('\tpops = { ' + ', '.join(str(v) for v in pops) + ' }, -- milhões de habitantes\n')
    f.write('\tgdps = { ' + ', '.join(str(v) for v in gdps) + ' }, -- PIB em bilhões de US$\n')
    f.write(f'\tlatTop = {LAT_TOP},\n\tlatBot = {LAT_BOT},\n')
    f.write('\trle = "' + ','.join(runs) + '",\n}\n')
print('ok', out, os.path.getsize(out), 'bytes')
# prévia
prev = Image.new('RGB', (W, H))
pp = prev.load()
for i, v in enumerate(grid):
    pp[i % W, i // W] = (60, 120, 190) if v == 0 else ((v * 53) % 200 + 40, (v * 97) % 200 + 40, (v * 31) % 200 + 40)
prev.resize((W * 4, H * 4), Image.NEAREST).save(os.path.join(here, 'data', 'preview.png'))
