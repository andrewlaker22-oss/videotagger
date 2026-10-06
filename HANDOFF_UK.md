# Handoff: UK TikTok pull (eBay x Strategy research), as of 2026-10-06

Paste this into a new chat with the Adology MCP connected. Germany is done; this repeats it for the UK.

## 1. Goal
Build the UK dataset in the same shape as the US and Germany:
- **Community half:** UK creators in these categories: Pokémon/TCG, toys/collectibles, handbags/luxury, coins, watches, sports cards, cameras, patches, sneakers.
- **eBay half:** UK TikTok videos about eBay (eBay searches + UK eBay sellers).
- **Final output:** CSVs plus one table with these columns: category | videos | on topic | on-topic views | median views. Category rows first, then "Communities video total", then the eBay rows, "eBay searches total", "TOTAL (communities + eBay)". Same layout as `exports/germany_totals_simple.csv`.

## 2. Rules
- Adology credits: under 500 per pull, go ahead. Over 500, quote and ask Andy first.
- Always quote first. Never set a small cap on the number of videos (small caps return almost nothing).
- Sort or bucket videos only from captions and Adology's text fields (contentSummary, textInFrame). Never analyze the videos yourself.
- Dedupe by video ID. One CSV per pull, with a short preview. Columns as in section 5.
- No em-dashes. Keep replies short.
- Start a new chat per task. Save raw results to disk so nothing gets re-read.

## 3. Adology how-to
- Portfolio: `cb16ed412aae5177a79f6e35`. Make a new project per pull: `create_project`, then pin it with `update_project_scope` (replace).
- Pull: `pull_data(projectId, quoteOnly:true, candidates, dateRangeDays)` -> `confirm_pull(previewId, projectId, confirmedByUser:true, maxCredits)` -> `check_pull(runId)`.
  - Search candidate: `{"kind":"search","platform":"tiktok","handleOrTerm":"<term>"}`, `dateRangeDays: 365`. About 100 credits per term, mostly refunded.
  - Account candidate: `kind:"influencer"` (person) or `"brand"` (shop), `dateRangeDays: 60`. About 100 per creator, 40 per shop, partly refunded.
- Read (free): `analyze(projectId, query, distribution:"exhaustive", sortBy:"firstActiveAt", feedTypes:["search"] or ["brand","influencer"], fields:["contentSummary","productionStyle","contentType","isCommercial"], limit:20 to 30, offset)`. Page with `nextOffset`. If a page says it packed fewer items, continue from the offset it gives so nothing is skipped.
- A search item's term is in its thumbnail URL: `/search/tiktok/<term>/`.
- Check refunds with `list_charges`.
- 0 videos in about 15 seconds = Adology outage. It's refunded. Tell Andy/James.
- A failed or repeated pull of the same search or account is locked for 12 hours.
- Adology summaries can lag hours behind the videos. Re-read later (free).

## 4. What we already know about the UK
- **No location filter in Adology.** UK searches will mix in US videos. Flag UK rows by text: £, UK, Royal Mail, Evri, ebay.co.uk, @ebay_uk, London, British, car boot, charity shop.
- UK search works much better than Germany's (English captions). An Oct 2 test returned real UK coin and watch content.
- "patches uk" returned pimple patches. Use "patch collector uk", "battle jacket uk", "military patches uk".
- Found in earlier tests (`exports/tiktok_europe_test.csv`):
  - Coins: thecoincollectoruk, coinhunteruk_usa, dansdollarss, ellielouiseleach, hannahgtown, prelovedprophets (check each is UK). Terms that worked: "50p coins", "rare 50p coins".
  - Watches: dkwatchesltd, watchseasonuk, watchseekeruk, surrey.timepieces, watchcartel.uk, maxs_watches, triple5jewellers, barakahbezels, thewatchmuseco. Drop the.clone.watch.company (sells clones).
  - Patches: runway25uk, joecox66, pvcpatchess (small).
- UK eBay accounts seen in the German eBay searches (`exports/germany_ebay_search.csv`): ebayforsellersuk, ebay_uk (eBay's own, keep separate like @ebay.de), charrwilliams (car boot hauls), reseller.dan, resellerluke, kirsty_reseller, 2ndhandandbranded (eBay Live), eliteluxurylondon (eBay luxury auctions), the_brotherhood_games (Pokémon, eBay Live), automotivesurplusuk, partslocaluk, bmw_spares_scotland, carbootkicks, aminotnata, moniquei8 (eBay UK ad), mrgreedy.village (eBay Live UK ad, 2.2M views).

## 5. Steps
1. **eBay searches.** Project "UK eBay searches". Terms: the 13 US terms (ebay, ebay vintage, ebay haul, ebay camera, ebay sneakers, ebay motors, how to buy on ebay, ebay gem, found on ebay, bought on ebay, ebay authentic, ebay pokemon, ebay finds) plus: ebay uk, ebay live uk, ebay uk haul, car boot ebay, charity shop ebay. 365 days. Expect about 1,800 credits charged, most refunded. Keep only rows with a UK flag.
2. **UK eBay sellers.** Pull the UK eBay accounts in section 4 (60 days). Keep posts that mention eBay.
3. **Community accounts.** For each category, find 3+ UK creators (from section 4, or a few UK searches like "pokemon cards uk", "car boot finds", "royal mint", "vintage camera uk", "sneakers uk"). Show Andy the shortlist, then pull 60 days in batches under 500 credits.
4. **CSVs.** Columns: category or search_term, country flag, post_date, pulled_date, handle, account_name, views, likes, comments, shares, caption, ai_summary, on_topic flag, url.
5. **Totals table.** Same layout as Germany (section 1).

## 6. Reference
- Repo `andrewlaker22-oss/videotagger`, branch `claude/determined-curie-f3xkwb`.
- `HANDOFF_GERMANY.md`: the full Germany method and results.
- `scripts/germany/*.py`: build scripts to copy for the UK (search CSV, seller CSV, eBay half, totals).
- Germany for scale: about 1,233 videos and about 2,900 credits net. US: about 3,750 videos.
