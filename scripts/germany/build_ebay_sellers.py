"""Builds exports/germany_ebay_sellers.csv from saved Adology analyze items (60-day pulls of German eBay.de seller accounts).
Run: python scripts/germany/build_ebay_sellers.py"""
import json, csv, re, os, glob, collections

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'exports', 'germany_ebay_sellers.csv')
# handle -> (account_type, what they are, from the German eBay searches)
ACCTS = {
    'airliftvintage': ('shop', 'vintage streetwear, eBay Live auctions'),
    'echtheitscheck': ('shop', 'authentication service, eBay Live events'),
    'thewatchdive': ('creator', 'luxury watches, reacts to eBay Live auctions'),
    'diegoldfrau': ('creator', 'jewelry, eBay Live streams'),
    'packmysales0': ('creator', 'reseller packing eBay.de sales'),
    'virello__shop': ('shop', 'bags, eBay.de listings'),
    'b2b_retourenbros': ('shop', 'returns pallets, live auctions'),
    'aureliehaas55': ('creator', 'eBay.de seller'),
}
EBAY = re.compile(r'e-?bay(?!\s*-?\s*kleinanzeigen)|ebaylive|ebay\.de', re.I)
KLEIN = re.compile(r'kleinanzeigen', re.I)
LIVE = re.compile(r'ebay ?live|live ?(auktion|auction|shopping|stream)|livestream|#live\b', re.I)
GER = re.compile(r"\b(und|ich|nicht|wir|euch|mit|noch|auf|für|eine?n?|mal|heute|wie|oder|habe|hab|bei|gekauft|verkauft|verkaufen|danke|sind|meine?|kein|zum|zur|vom|aber|jetzt|schon|nur|auch|ist|der|das|den|dem|des|sehr|ganz|wieder|folgen|klickt|uhr)\b|[äöüß]", re.I)
ENG = re.compile(r"\b(the|and|my|this|what|you|for|with|from|was|is|are|it|of|to|in|on|that|just|got|i)\b", re.I)


def clean(v):
    return v.encode('utf-16', 'surrogatepass').decode('utf-16', 'ignore') if isinstance(v, str) else v


def lang(t):
    t = re.sub(r'https?://\S+', ' ', t)
    body = re.sub(r'[#@][\w.]+', ' ', t)
    if not t.strip():
        return ''
    if not body.strip() or not re.search(r'[A-Za-zÄÖÜäöüß]{3,}', body):
        return 'hashtags only'
    g = len(GER.findall(t)); e = len(ENG.findall(body))
    return 'German' if g >= e and g else ('English/other' if e else 'unclear')


items = {}
for fp in sorted(glob.glob(os.path.join(ROOT, 'data', 'germany', 'ebay_sellers_items*.json'))):
    for k, it in json.load(open(fp, encoding='utf-8')).items():
        p = items.setdefault(k, {})
        for kk, v in it.items():
            if v in ('', None, {}) and p.get(kk):
                continue
            p[kk] = v

rows, seen = [], set()
for it in sorted(items.values(), key=lambda x: x.get('createdAt') or '', reverse=True):
    url = (it.get('url') or '').split('?')[0]
    m = re.search(r'tiktok\.com/@([^/]+)/(?:video|photo)/(\d+)', url)
    if not m:
        continue
    handle, vid = m.group(1).lower(), m.group(2)
    if handle not in ACCTS or vid in seen:
        continue
    seen.add(vid)
    cap = clean((it.get('headline') or '').strip()); summ = clean(it.get('contentSummary') or ''); ost = clean((it.get('textInFrame') or '')[:1500])
    alltxt = ' '.join([cap, summ, ost])
    eb = bool(EBAY.search(alltxt)); kl = bool(KLEIN.search(alltxt))
    rows.append(dict(
        account=handle, account_type=ACCTS[handle][0], account_note=ACCTS[handle][1], account_name=clean(it.get('brand', '')),
        post_date=(it.get('createdAt') or '')[:10], pulled_date='2026-10-05',
        views=it.get('views'), likes=it.get('likes'), comments=it.get('comments'), shares=it.get('shares'),
        caption_language=lang(cap),
        ebay_related='yes' if eb else ('Kleinanzeigen only' if kl else 'no'),
        ebay_live='yes' if eb and LIVE.search(alltxt) else '',
        caption=cap, ai_summary=summ, onscreen_text=ost,
        production_style=it.get('productionStyle', ''), content_type=it.get('contentType', ''), is_commercial=it.get('isCommercial', ''),
        has_adology_analysis='yes' if summ else 'no', url=url))

order = {'yes': 0, 'Kleinanzeigen only': 1, 'no': 2}
rows.sort(key=lambda r: (order[r['ebay_related']], r['account'], r['post_date']), reverse=False)
with open(OUT, 'w', newline='', encoding='utf-8-sig') as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)

C = collections.Counter
print('rows', len(rows))
print(C(r['ebay_related'] for r in rows), C(r['caption_language'] for r in rows), 'analyzed', C(r['has_adology_analysis'] for r in rows))
for a in ACCTS:
    rs = [r for r in rows if r['account'] == a]
    print(f"{a:18} n={len(rs):4} ebay={sum(r['ebay_related']=='yes' for r in rs):4} live={sum(r['ebay_live']=='yes' for r in rs):3} de={sum(r['caption_language']=='German' for r in rs):4}")
