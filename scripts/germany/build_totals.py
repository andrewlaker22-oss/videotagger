"""Builds exports/germany_totals.csv: every Germany aggregation (per account, per community/tier, per half, grand total).
Run: python scripts/germany/build_totals.py"""
import csv, os, statistics as st

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EX = os.path.join(ROOT, 'exports')
rd = lambda f: list(csv.DictReader(open(os.path.join(EX, f), encoding='utf-8-sig')))
num = lambda v: int(float(v)) if str(v).strip() not in ('', 'None') else None

# Unified rows: half, group, country, account, views, on_topic (bool), caption
U = []
for r in rd('pokemon_germany_creators.csv'):
    U.append(('A: community', 'pokemon/TCG', 'Austria' if r['account'] == 'cardhome_store' else 'Germany', r['account'], num(r['views']), r['flag'] == '', r['caption']))
for r in rd('germany_communities_creators.csv'):
    U.append(('A: community', r['community'], r['country'], r['account'], num(r['views']), r['flag'] == '', r['caption']))
for r in rd('germany_ebay_half.csv'):
    ctry = 'eBay.de market (non-German creators)' if r['tier'].startswith('eBay.de market') else 'Germany'
    U.append(('B: eBay', r['tier'], ctry, r['handle'], num(r['views']), True, r['caption']))
for r in rd('ebay_de_tiktok.csv'):
    U.append(('eBay own account', '@ebay.de', 'Germany', r['account'] or 'ebay.de', num(r['views']), True, r['caption']))


def agg(rs, level, half, group, country, account):
    v = [r[4] for r in rs if r[4] is not None]
    on = [r for r in rs if r[5]]
    vo = [r[4] for r in on if r[4] is not None]
    top = max(on or rs, key=lambda r: r[4] or 0)
    return dict(level=level, half=half, group=group, country=country, account=account,
                accounts=len({r[3] for r in rs}), videos=len(rs), on_topic=len(on),
                views_total=sum(v), views_on_topic=sum(vo), median_views_on_topic=int(st.median(vo)) if vo else '',
                top_views=top[4] or '', top_caption=' '.join((top[6] or '').split())[:90])


GROUPS = {'A: community': ['pokemon/TCG', 'toys/collectibles', 'handbags', 'coins', 'watches', 'sports cards', 'cameras', 'patches'],
          'B: eBay': ['German eBay (core)', 'German eBay + Kleinanzeigen mixed', 'eBay.de market, not German creators'],
          'eBay own account': ['@ebay.de']}
out = []
for half, groups in GROUPS.items():
    for g in groups:
        rs = [r for r in U if r[0] == half and r[1] == g]
        if not rs:
            continue
        ctry = '/'.join(sorted({r[2] for r in rs}))
        out.append(agg(rs, 'community/tier total', half, g, ctry, 'ALL'))
        # per-account rows (the non-German dropshipper tier stays one row: 37 small accounts)
        if not g.startswith('eBay.de market'):
            for acc in sorted({r[3] for r in rs}, key=lambda a: -sum(1 for r in rs if r[3] == a)):
                ars = [r for r in rs if r[3] == acc]
                out.append(agg(ars, 'account', half, g, ars[0][2], acc))
    hrs = [r for r in U if r[0] == half]
    out.append(agg(hrs, 'half total', half, 'ALL', '/'.join(sorted({r[2] for r in hrs})), 'ALL'))
gt = [r for r in U if r[0] != 'eBay own account']
out.append(agg(gt, 'GRAND TOTAL (A + B, excl. @ebay.de)', 'A + B', 'ALL', 'all', 'ALL'))
ge = [r for r in gt if r[2] == 'Germany']
out.append(agg(ge, 'GRAND TOTAL Germany only (excl. Austria, unclear, non-German creators)', 'A + B', 'ALL', 'Germany', 'ALL'))

with open(os.path.join(EX, 'germany_totals.csv'), 'w', newline='', encoding='utf-8-sig') as f:
    w = csv.DictWriter(f, fieldnames=list(out[0])); w.writeheader(); w.writerows(out)
print(len(out), 'rows')
