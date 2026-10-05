"""Builds exports/germany_ebay_search.csv from saved Adology analyze items. Run: python scripts/germany/build_ebay_search.py"""
import json, csv, re, os, glob, urllib.parse, collections, statistics as st
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT=os.path.join(ROOT,'exports','germany_ebay_search.csv')
US={'ebay deutschland':'ebay','ebay vintage deutsch':'ebay vintage','ebay haul deutsch':'ebay haul','ebay kamera':'ebay camera',
 'ebay sneaker':'ebay sneakers','ebay autoteile':'ebay motors','auf ebay kaufen':'how to buy on ebay','ebay schnäppchen':'ebay gem',
 'auf ebay gefunden':'found on ebay','auf ebay gekauft':'bought on ebay','ebay echtheitsprüfung':'ebay authentic',
 'ebay pokemon karten':'ebay pokemon','ebay funde':'ebay finds','ebay verkaufen':'(German extra)','ebay live deutsch':'(German extra)',
 'ebay fund':'(German extra)','bei ebay bestellt':'(German extra)','ebay erfahrung':'(German extra)',
 'ebaydeutschland':'(German round 2)','ebay de':'(German round 2)','ebay live deutschland':'(German round 2)','ebay auktion':'(German round 2)','ebay verkäufer':'(German round 2)','ebay paket':'(German round 2)','ebay bestellung':'(German round 2)','ebay rückgabe':'(German round 2)','auf ebay verkauft':'(German round 2)','ebay käufer':'(German round 2)','ebay betrug':'(German round 2)','ebay gebühren':'(German round 2)'}
# Input: data/germany/ebay_search_items*.json (Adology analyze items keyed by item id, each with _term = search term).
# To add new pulls, save the new analyze items to another ebay_search_items_<name>.json file in the same shape; ids merge, non-empty fields win.
an={}
for fp in sorted(glob.glob(os.path.join(ROOT,'data','germany','ebay_search_items*.json'))):
    for k,it in json.load(open(fp,encoding='utf-8')).items():
        if '_term' not in it:
            m=re.search(r'/search/tiktok/([^/]+)/',it.get('thumbnail') or '')
            it['_term']=urllib.parse.unquote(m.group(1)).strip() if m else ''
        if it['_term'] not in US: continue
        p=an.setdefault(k,{})
        for kk,v in it.items():
            if v in ('',None,{}) and p.get(kk): continue
            p[kk]=v
GER=re.compile(r"\b(und|ich|nicht|wir|euch|mit|noch|auf|für|eine?n?|mal|heute|wie|oder|habe|hab|bei|gekauft|gefunden|verkauft|verkaufen|schnäppchen|deutsch|deutschland|flohmarkt|danke|geil|liebe|sind|meine?|dein|kein|zum|zur|vom|aber|jetzt|schon|nur|auch|ist|der|das|den|dem|des|sehr|ganz|wieder|endlich|fürdich|trödelmarkt|kleinanzeigen)\b|[äöüß]",re.I)
ENG=re.compile(r"\b(the|and|my|this|what|you|for|with|from|found|bought|thrift|goodwill|reseller|haul|was|is|are|it|of|to|in|on|that|just|got|i)\b",re.I)
def lang(t):
    t=re.sub(r"https?://\S+","",t)
    if not t.strip(): return ''
    words=re.sub(r"#\w+|@\S+","",t)
    g=len(GER.findall(t)); e=len(ENG.findall(words))
    if not words.strip(): return 'hashtags only' if not g else 'German'
    return 'German' if g>e else ('English/other' if e>0 else ('German' if g else 'unclear'))
SUMDE=re.compile(r"\b(a|the) German(-speaking)? (creator|user|tiktoker|influencer|seller|reseller|youtuber|comedian|speaker|teacher|couple|man|woman|guy|girl|family)\b|\bGerman-speaking\b|\bGerman-language\b|\bin German\b|\bGerman (voiceover|dialogue|narration|text|captions?)\b",re.I)
SUMMKT=re.compile(r"\b(Berlin|Stuttgart|Munich|Hamburg|Cologne|Frankfurt|Dresden|Austria|Vienna)\b|\bGerman (classifieds|marketplace|platform|secondhand|second-hand|online|eBay|market|television|TV|ad)\b|Kleinanzeigen")
MARKETDE=re.compile(r"ebay\.de\b|ebay ?germany|ebaygermany|ebay deutschland|ebaydeutschland|germany|deutschland|€|\beuros?\b",re.I)
COMM=[('pokemon/TCG',r'pok[eé]mon|tcg|booster|yu-?gi-?oh|one piece card|magic the gathering|sammelkarte'),
 ('sports cards',r'topps|panini|sportscard|sports card|fu(ß|ss)ballkarte|bundesliga|prizm'),
 ('sneakers',r'sneaker|jordan|\bnike\b|adidas|yeezy|new balance|dunk|schuhe|shoes'),
 ('cameras',r'kamera|camera|digicam|objektiv|\blens|leica|canon|nikon|analog|polaroid|instax'),
 ('car parts',r'autoteil|auto|\bcar\b|kfz|motor|felge|reifen|tuning|bmw|vw\b|golf|audi|mercedes'),
 ('watches',r'\buhr|watch|rolex|omega|seiko|casio'),
 ('coins',r'münz|coin|numismat'),
 ('handbags/luxury',r'tasche|handbag|\bbags?\b|louis vuitton|\blv\b|gucci|chanel|prada|dior|herm[eè]s|designer|luxus|luxury'),
 ('toys/collectibles',r'lego|funko|figur|spielzeug|\btoys?\b|blind ?box|plüsch|sammlung|collectible|vintage spielzeug'),
 ('fashion/vintage',r'vintage|kleidung|klamotten|jacke|clothing|thrift|second ?hand|vinted'),
 ('electronics',r'iphone|handy|konsole|playstation|\bps5\b|nintendo|switch|laptop|elektronik|grafikkarte')]
COMM=[(k,re.compile(v,re.I)) for k,v in COMM]
rows=[];seen=set()
for i in sorted(an.values(),key=lambda x:x.get('createdAt') or '',reverse=True):
    url=(i.get('url') or '').split('?')[0]
    m=re.search(r'tiktok\.com/@([^/]+)/video/(\d+)',url)
    vid=m.group(2) if m else url
    if vid in seen: continue
    seen.add(vid)
    cap=(i.get('headline') or '').strip(); summ=i.get('contentSummary') or ''; ost=(i.get('textInFrame') or '')[:1500]
    alltxt=' '.join([cap,summ,ost])
    cl=lang(cap)
    lang_de = cl=='German' or bool(SUMDE.search(summ))
    mkt_de = bool(MARKETDE.search(alltxt)) or bool(SUMMKT.search(summ))
    german = 'German-language' if lang_de else ('Germany market, not German-language' if mkt_de else ('unclear (hashtags only)' if cl in ('hashtags only','') else 'not German'))
    comm=next((k for k,r in COMM if r.search(alltxt)),'other/general')
    rows.append(dict(search_term=i['_term'],us_equivalent=US[i['_term']],post_date=(i.get('createdAt') or '')[:10],pulled_date='2026-10-05',
        handle=m.group(1) if m else '',account_name=i.get('brand',''),views=i.get('views',''),likes=i.get('likes',''),comments=i.get('comments',''),shares=i.get('shares',''),
        german=german,caption_language=cl,
        mentions_ebay=('Kleinanzeigen only' if re.search(r'kleinanzeigen',alltxt,re.I) and not re.search(r'e-?bay(?! ?kleinanzeigen)',alltxt,re.I) else ('yes' if re.search(r'e-?bay',alltxt,re.I) else 'no')),
        kleinanzeigen='yes' if re.search(r'kleinanzeigen',alltxt,re.I) else '',
        mentions_vinted='yes' if re.search(r'vinted',alltxt,re.I) else '',
        community_guess=comm,caption=cap,ai_summary=summ,onscreen_text=ost,production_style=i.get('productionStyle',''),
        content_type=i.get('contentType',''),is_commercial=i.get('isCommercial',''),has_adology_analysis='yes' if summ else 'no',url=url))
order=list(US)
rows.sort(key=lambda r:(['German-language','Germany market, not German-language','unclear (hashtags only)','not German'].index(r['german']),order.index(r['search_term']),r['post_date']))
def clean(v): return v.encode('utf-16','surrogatepass').decode('utf-16','ignore').encode('utf-8','ignore').decode('utf-8') if isinstance(v,str) else v
rows=[{k:clean(v) for k,v in r.items()} for r in rows]
with open(OUT,'w',newline='',encoding='utf-8-sig') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
print('items',len(an),'rows',len(rows))
C=collections.Counter
print(C(r['german'] for r in rows))
print(C((r['german'],r['mentions_ebay']) for r in rows))
print('analysis',C(r['has_adology_analysis'] for r in rows))
for t in order:
    x=[r for r in rows if r['search_term']==t]
    if x: print(f"{t:24s} n={len(x):3d} DE-lang={sum(r['german']=='German-language' for r in x):3d} DE-mkt={sum(r['german'].startswith('Germany') for r in x):3d}")
g=[r for r in rows if r['german']=='German-language' and r['mentions_ebay']=='yes']
print('German-language + eBay mention:',len(g), C(r['community_guess'] for r in g).most_common())
