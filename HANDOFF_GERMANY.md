# Handoff: wrap up Germany (eBay x VaynerMedia TikTok research), as of 2026-10-05

Paste this into a new chat, or point the chat at this file. Everything needed is in this repo and in Adology.

## 1. Goal
Finish the Germany TikTok dataset so it mirrors the US structure:
- **Half A, community buckets:** done (Germany: 1,111 videos, 974 on topic).
- **Half B, "direct eBay" content:** started. The US eBay half was 1,007 videos from 13 eBay searches. Germany search gave only ~42 German-language videos, so the plan is to pull German eBay.de seller accounts (section 6).
- **Deliver:** final CSVs, a totals table (US vs Germany, both halves), and a short write-up of the split and caveats.

## 2. Working rules (from the user, keep them)
- Don't analyze videos yourself. Any sorting or bucketing comes only from captions and Adology's text fields (contentSummary, textInFrame, productionStyle, contentType, isCommercial).
- One CSV per pull, deduped by video ID, sent with a short preview. Commit and push each one.
- Be concise. No em-dashes.
- Adology credits: no need to ask under 500. Above 500, quote and get a yes. Exception: for the Germany eBay half the user approved up to 5,000 credits total without quotes; 821 is already used, so ~4,179 is left for it.
- Python for the user's machine: save to `C:\Users\andre\OneDrive\Desktop` and give `cd C:\Users\andre\OneDrive\Desktop` then `python <file>.py`. Code must never loop forever.
- Never propose browser console/devtools JavaScript on work systems.
- Keep Claude cost down: write raw Adology results to disk (JSON) as you go instead of re-reading them, and don't re-page data that's already saved.

## 3. Environment
- Repo `andrewlaker22-oss/videotagger`, branch `claude/determined-curie-f3xkwb`. Exports go in `exports/`.
- Adology portfolio `cb16ed412aae5177a79f6e35`. Projects:
  - `ee7a3209-e87b-4f26-b590-751f3014d83b` main project (all account pulls, Pokemon, communities). Its `feedNames` filter no longer works; filter by `brand` (display name, not handle, e.g. "Jessi💛✨🌕").
  - `56c70366-6df9-489b-b905-58eb54e66398` Germany eBay searches round 1 (18 terms, 806 items).
  - `845bdde5-334c-44d3-ac74-ed3ef24aaf74` Germany eBay searches round 2 (12 terms, 364 items).
- Adology balance after this work: 50,289.

## 4. Adology recipes and gotchas
- Pull: `pull_data(projectId, quoteOnly:true, candidates:[...], dateRangeDays)` then `confirm_pull(previewId, projectId, confirmedByUser:true, maxCredits)` then `check_pull(runId)`. Refunds for unused quota land later as `scout_fast_fetch_reconcile` (check with `list_charges`). Quotes expire after ~15 min.
- Search candidate: `{"kind":"search","platform":"tiktok","handleOrTerm":"<term>"}`. Settings matched to the US: `dateRangeDays: 365`, ~102 credits per term.
- Account pulls used a 60-day window: about 100 credits per creator, 40 per shop, most of it refunded for low posters. Check the `pull_data` tool description for the account candidate kind.
- To read just one pull, make a project pinned to it: `create_project` then `update_project_scope` with `replace: [{"scraper":"tiktok","id":term,"term":term}]`.
- Read (free): `analyze(projectId, query, distribution:"exhaustive", sortBy:"firstActiveAt", feedTypes:["search"] or ["brand"], fields:["contentSummary","productionStyle","contentType","isCommercial"], limit:20, offset)`. Responses are capped near 25KB: limit 30 packs only ~23 items, and adding `textInFrame` drops it to ~16. Page by offset.
- The search term of a search item is in its thumbnail URL: `/search/tiktok/<term>/`.
- A pull that "succeeds" in ~15 seconds with 0 items is an Adology outage (it happened Oct 5 ~16:24 UTC; James fixed it). A failed pull locks that search or account for 12 hours.
- TikTok search can't target a country. German terms mostly return US/English videos. Account pulls of known German creators are what work.
- Some accounts come back empty even after retries (likely private or inactive): thatsonyi, alexavius, slap.auction, paulasenfkorn.

## 5. Files in the repo (current state)
| File | Rows | What it is |
|---|---|---|
| `exports/germany_communities_creators.csv` | 802 | Half A minus Pokemon. 7 communities, 16 accounts, 60 days to Oct 5. `country` column: Germany 631, Austria 143 (vintageconnaisseur), DE/AT unclear 28 (jessikunterbunt). `flag` blank = topic named in caption. |
| `exports/pokemon_germany_creators.csv` | 309 | Half A, Pokemon/TCG. 6 accounts, 303 on topic. dave_mps's toy rows were moved to the communities file. |
| `exports/germany_ebay_search.csv` | 1,169 | Half B attempt: 30 German eBay search terms (365 days). `german` column: German-language 42, Germany market 56, hashtags only 70, not German 1,001. |
| `exports/ebay_de_tiktok.csv` | 17 | @ebay.de's own posts (Aug 7 to Sep 18). Kept separate. |
| `exports/tiktok_all.csv` (+ per-topic files) | 1,838 | US Half A: patches 688, coins 492, watches 486, ducks 172. 1,738 on topic. |
| `exports/pokemon_germany_search.csv`, `pokemon_germany_tests_oct5.csv`, `pokemon_en*_captions.csv`, `tiktok_europe_test.csv` | small | Earlier tests, for reference only. |
| `data/germany/ebay_search_items.json` | 1,169 | Raw Adology items behind the eBay search CSV (with `_term`). |
| `scripts/germany/build_ebay_search.py` | | Rebuilds the eBay search CSV from `data/germany/ebay_search_items*.json`. Verified to reproduce the current CSV exactly. |

**Not in the repo:** the US eBay half (1,007 videos) and the master file `FINAL_eBay_Research_All_9_Datasets.xlsx` are on the user's laptop (`C:\Users\andre\Documents\ebay_research`).

### eBay search CSV columns
search_term, us_equivalent, post_date, pulled_date, handle, account_name, views, likes, comments, shares, german, caption_language, mentions_ebay (yes / no / Kleinanzeigen only), kleinanzeigen, mentions_vinted, community_guess, caption, ai_summary, onscreen_text, production_style, content_type, is_commercial, has_adology_analysis, url.

German classification (in the script): German-language if the caption reads as German, or the summary says "a German creator", "in German", "German-speaking" and the like. Germany market if it mentions ebay.de, Deutschland, euros or a German/Austrian city, or "German classifieds/marketplace". A "German beer stein" or "vintage cologne" doesn't count.

## 6. Germany totals so far
**Half A, community buckets (60-day account pulls)**
| Community | Accounts | Videos | On topic | Median views (on topic) |
|---|---|---|---|---|
| Pokemon/TCG | 6 | 309 | 303 | 3,734 |
| Sports cards | 2 | 39 | 39 | 5,187 |
| Toys/collectibles | 4 | 247 | 201 | 18,300 |
| Handbags | 2 | 178 | 140 | 3,023 |
| Watches | 3 | 143 | 104 | 400 |
| Coins | 2 | 137 | 136 | 2,685 |
| Cameras | 2 | 40 | 39 | 904 |
| Patches | 1 | 18 | 12 | 582 |
| **Total** | **21** | **1,111** | **974** (Germany only 811) | **3,228** |

Accounts: sandrosir, pkchomps, cardhome_store (Vienna), hypegen.87, nilopacks, dave_mps (Pokemon rows) | smexycards, ndbreakstcg | anime.mura2 (shop), sabrinasammer, jessikunterbunt, dave_mps (toy rows) | alina_dorn, vintageconnaisseur (Vienna shop) | aronstoico, benjaminwatches, frankfurt_timepieces | davidgeorge988, sammlungseltenermunzen (shop) | vintageloopshopde (shop, real eBay seller), foto_paf | blasphemy_patches. Dropped: soniatallk, vextacy_ (off topic), elsaa.shh, keinpart2, crispyrob.

**Half B, German eBay searches (30 terms, 1,169 videos)**
- Terms, round 1 (German versions of the 13 US terms plus 5 extras): ebay deutschland, ebay vintage deutsch, ebay haul deutsch, ebay kamera, ebay sneaker, ebay autoteile, auf ebay kaufen, ebay schnäppchen, auf ebay gefunden, auf ebay gekauft, ebay echtheitsprüfung, ebay pokemon karten, ebay funde, ebay verkaufen, ebay live deutsch, ebay fund, bei ebay bestellt, ebay erfahrung.
- Round 2: ebaydeutschland, ebay de, ebay live deutschland, ebay auktion, ebay verkäufer, ebay paket, ebay bestellung, ebay rückgabe, auf ebay verkauft, ebay käufer, ebay betrug, ebay gebühren.
- US terms (for reference): ebay, ebay vintage, ebay haul, ebay camera, ebay sneakers, ebay motors, how to buy on ebay, ebay gem, found on ebay, bought on ebay, ebay authentic, ebay pokemon, ebay finds.
- Result: 42 German-language videos. 21 mention eBay, but about a third of those are really Kleinanzeigen (FcAmos car sketches, scam videos, afrim.com). 9 more are Kleinanzeigen only. Only ~10 to 12 are clearly eBay.de. Best terms: "ebay vintage deutsch" (12), "ebay deutschland" (8), "ebay haul deutsch" (6), "ebay betrug" (6). Ten terms found 0 German videos.
- 56 "Germany market" rows are mostly South Asian dropshippers selling on eBay.de (royishere_, aureliehaas55, ahsanecomerce...), plus packmysales0.
- Kleinanzeigen is a separate company now and must not count as eBay.

**Credits spent on Germany (net):** about 2,540. That's Pokemon search 111, tests 61, Pokemon accounts 317, community discovery 26, community batches 694, cameras/patches/@ebay.de 111, beef-up 396, eBay searches 821.

## 7. Germany wrap-up (done 2026-10-05)
- Pulled 8 German eBay.de seller accounts (60 days, project `a29a16a6-a7f6-4b99-8591-921e94a13885`): 299 videos, 336 credits net. Only 48 mention eBay (captions only; Adology summarized just 5 of 299). Files: `exports/germany_ebay_sellers.csv`, raw `data/germany/ebay_sellers_items.json`, script `scripts/germany/build_ebay_sellers.py`.
  - packmysales0 19/19 eBay, aureliehaas55 11/28, b2b_retourenbros 10/70, airliftvintage 6/12 (5 eBay Live), echtheitscheck 1/66, virello__shop 1/1, thewatchdive 0/89, diegoldfrau 0/14.
  - The "eBay Live" sellers mostly stream elsewhere too: airliftvintage also runs Whatnot streams, Retourenbros pushes TikTok Live/TikTok Shop, echtheitscheck sells via Instagram live and TikTok Shop.
- Germany eBay half: `exports/germany_ebay_half.csv` (script `scripts/germany/build_ebay_half.py`), deduped by video ID, in 3 tiers:
  - German eBay (core): 64 videos, 16 accounts (48 seller posts + 16 German-language search videos), median 1,420 views.
  - German eBay + Kleinanzeigen mixed: 8 (any eBay row that also mentions Kleinanzeigen).
  - eBay.de market, not German creators (mostly South Asian dropshippers): 50, reported separately.
- Split: Germany is about 6% eBay / 94% community (64 vs 974 on-topic), or 11% / 89% counting all 3 tiers. The US was 50/50.
- Full Germany totals table (per account, community, half): `exports/germany_totals.csv` (script `scripts/germany/build_totals.py`).
- Germany credits, all work: about 2,876 net. eBay half: 1,157 of the 5,000 approved.
- Still open for the user: whether Austria counts (DACH), and whether the dropshipper tier counts.

## 8. After Germany
Next countries in order: UK, France, Italy. Use the same method: free check of what's already in Adology, a few local hashtag searches only to find accounts, a shortlist the user approves, then 60-day account pulls in batches under 500 credits. Start each country in a fresh chat with a brief like this one.
