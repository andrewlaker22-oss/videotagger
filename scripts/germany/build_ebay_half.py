"""Builds exports/germany_ebay_half.csv (Germany's direct-eBay half) from the search and seller exports, and prints the US vs Germany totals.
Run after build_ebay_search.py and build_ebay_sellers.py: python scripts/germany/build_ebay_half.py"""
import csv, os, re, statistics as st, collections

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EX = os.path.join(ROOT, 'exports')
rd = lambda f: list(csv.DictReader(open(os.path.join(EX, f), encoding='utf-8-sig')))
vid = lambda u: (re.search(r'/(?:video|photo)/(\d+)', u or '') or [None, u])[1]
num = lambda v: int(float(v)) if str(v).strip() not in ('', 'None') else None

rows, seen = [], set()


def add(tier, source, handle, r, cap, summ):
    k = vid(r['url'])
    if k in seen:
        return
    seen.add(k)
    rows.append(dict(tier=tier, source=source, handle=handle, post_date=r['post_date'], views=r['views'], likes=r['likes'],
                     comments=r['comments'], shares=r['shares'], caption=cap, ai_summary=summ, url=r['url']))


# 1) German eBay.de seller accounts (60-day pulls): posts that mention eBay
for r in rd('germany_ebay_sellers.csv'):
    if r['ebay_related'] == 'yes':
        add('German eBay (core)', 'seller account: ' + r['account_note'], r['account'], r, r['caption'], r['ai_summary'])
# 2) German eBay searches: German-language rows that mention eBay
for r in rd('germany_ebay_search.csv'):
    if r['german'] == 'German-language' and r['mentions_ebay'] == 'yes':
        tier = 'German eBay + Kleinanzeigen mixed' if r['kleinanzeigen'] else 'German eBay (core)'
        add(tier, 'search: ' + r['search_term'], r['handle'], r, r['caption'], r['ai_summary'])
    elif r['german'] == 'Germany market, not German-language' and r['mentions_ebay'] == 'yes':
        add('eBay.de market, not German creators', 'search: ' + r['search_term'], r['handle'], r, r['caption'], r['ai_summary'])

order = ['German eBay (core)', 'German eBay + Kleinanzeigen mixed', 'eBay.de market, not German creators']
rows.sort(key=lambda r: (order.index(r['tier']), -(num(r['views']) or 0)))
with open(os.path.join(EX, 'germany_ebay_half.csv'), 'w', newline='', encoding='utf-8-sig') as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)


def stats(rs):
    v = [num(r['views']) for r in rs if num(r['views']) is not None]
    return len(rs), len({r.get('handle') or r.get('account') or r.get('author', '') for r in rs}), (int(st.median(v)) if v else None)


print('Germany eBay half by tier')
for t in order:
    rs = [r for r in rows if r['tier'] == t]
    n, a, m = stats(rs)
    src = collections.Counter(r['source'].split(':')[0] for r in rs)
    print(f'  {t:40} videos={n:4} accounts={a:3} median_views={m}  {dict(src)}')

# Community half (on topic = flag blank)
de_a = [r for r in rd('germany_communities_creators.csv') + rd('pokemon_germany_creators.csv') if r['flag'] == '']
de_all = rd('germany_communities_creators.csv') + rd('pokemon_germany_creators.csv')
de_core = [r for r in rows if r['tier'] == 'German eBay (core)']
us = rd('tiktok_all.csv')
print('\nHalf A Germany: videos', len(de_all), 'on topic', len(de_a), 'median views (on topic)', stats([{**r, 'handle': r['account']} for r in de_a])[2])
print('Half A US columns:', list(us[0])[:12])
print('Half B Germany core:', len(de_core), ' with mixed:', len(de_core) + sum(r['tier'] == order[1] for r in rows))
