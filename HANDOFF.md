# Handoff: eBay x Strategy TikTok research, full context as of 2026-10-06

Paste into a new chat to pick up where this one left off. Germany details: `HANDOFF_GERMANY.md`. UK plan: `HANDOFF_UK.md`.

## 1. What this project is
- Client: eBay. Strategy asked Andy (analytics) to research eBay-related communities on social. Most of the data is TikTok.
- Two halves per market:
  - **Community half:** videos from communities Strategy thinks sell on eBay (Pokémon/TCG, toys, luxury/handbags, coins, watches, sports cards, cameras, patches, etc.).
  - **eBay half:** videos about eBay itself (people searching "ebay vintage", "ebay haul", etc.).
- Data comes from Adology through its MCP server (a plug-in that lets an AI search and pull Adology data). James (Adology founder) gave free credits; Adology is an existing partner.
- Markets: US done, Germany done, UK next (handoff written), then France and Italy.

## 2. Rules (Andy's)
- Adology credits: under 500 per pull, no need to ask. Over 500, quote first and get a yes.
- Never do video analysis yourself. Sort/bucket only from captions and Adology's text fields.
- One CSV per pull, deduped, sent with a short preview. Commit and push.
- Concise replies, no em-dashes, blunt and simple language for anything going to other people.
- Python for Andy's machine: save to `C:\Users\andre\OneDrive\Desktop`, give `cd C:\Users\andre\OneDrive\Desktop` then `python <file>.py`. No infinite loops.
- Never propose browser console/devtools JavaScript on work systems.
- Pronouns: use they/them unless stated.

## 3. Where things live
- Repo `andrewlaker22-oss/videotagger`, branch `claude/determined-curie-f3xkwb`. Exports in `exports/`, scripts in `scripts/`, raw Adology items in `data/germany/`.
- Andy's laptop: `C:\Users\andre\Documents\ebay_research\FINAL_eBay_Research_All_9_Datasets.xlsx` (master file with the US 1,921). Not in the repo.
- Raw Apify exports for the US 1,921 were uploaded to the chat once (full_1000_tiktok.csv = 40 community hashtags x 21 posts; ebay plain + expanded search = the 13 eBay terms). Not in the repo.
- Adology portfolio `cb16ed412aae5177a79f6e35`. Projects:
  - `ee7a3209-e87b-4f26-b590-751f3014d83b` main (US 4 buckets, Pokémon, Germany communities). Its feedNames filter is broken; filter by brand display name.
  - `56c70366-6df9-489b-b905-58eb54e66398` Germany eBay searches round 1.
  - `845bdde5-334c-44d3-ac74-ed3ef24aaf74` Germany eBay searches round 2.
  - `a29a16a6-a7f6-4b99-8591-921e94a13885` Germany eBay.de sellers.
- Adology balance: 49,953 (Oct 5).
- James issues note (Claude artifact, private until shared): https://claude.ai/code/artifact/18b71e1b-d7d0-4b5d-b495-9f55a80d7e40

## 4. US (done)
- **1,921 videos** (from Andy's master file): 1,007 from 13 eBay searches (ebay, ebay vintage, ebay haul, ebay camera, ebay sneakers, ebay motors, how to buy on ebay, ebay gem, found on ebay, bought on ebay, ebay authentic, ebay pokemon, ebay finds) + 914 from 40 community hashtags.
  - Category counts (overlap, cover both pulls): Pokémon/TCG 164, Toys 255, Luxury 205, Sneakers 233, Sports cards 81, Electronics 345, Other/Emerging 683, Coins 1.
- **1,838 more videos** pulled Oct 1-2 to beef up 4 buckets Strategy asked about (`exports/tiktok_all.csv`, plus per-topic files). 365 days, Oct 2025 to Oct 2026.
  - Patches 688 (morale, chenille, police, embroidered, custom, iron-on patches, patch collector/collection), coins 492 (coin roll hunting, rare coins, wheat penny, silver coins, numismatics, coin collecting), watches 486 (watchtok, luxury/vintage watches, watch collection), rubber ducks 172.
  - On topic (caption or Adology text names it): 1,738. Andy's slide uses stricter AI tags: 1,506.
- **US total about 3,759.** Table for the boss: `exports/us_totals_simple.csv` (category rows overlap, so they don't sum to the totals; footnote it).

## 5. Germany (done)
- Community half: 1,111 videos, 974 on topic, from 21 creator/shop accounts (60-day account pulls). Pokémon 309, toys 247, handbags 178, coins 137, watches 143, sports cards 39, cameras 40, patches 18. Austria accounts included and labeled (vintageconnaisseur, cardhome_store).
- eBay half: 30 German eBay searches (1,169 videos, mostly US/English) + 8 German eBay.de seller accounts (299 videos). Result: **64 German eBay videos**, 8 mixed with Kleinanzeigen, 50 eBay.de dropshippers who aren't German.
- Germany total 1,233. Tables: `exports/germany_totals_simple.csv` (by category) and `exports/germany_totals.csv` (per account).
- Key takeaways: Adology has no location filter; German search terms return mostly English content; German "eBay" talk is mostly Kleinanzeigen (separate company now); German eBay Live sellers also sell on Whatnot, TikTok Shop and Instagram.
- About 2,900 Adology credits net. Open decisions: count Austria (DACH) or not; count the dropshipper tier or not.

## 6. Other Europe work
- Oct 2 tests (UK, DE, FR, IT, local-language searches): UK worked, DE/FR/IT returned almost nothing local. `exports/tiktok_europe_test.csv`.
- Pokémon Germany via translated captions and German creators: `exports/pokemon_*` files.
- @ebay.de's own TikTok (17 posts, eBay Live heavy): `exports/ebay_de_tiktok.csv`.
- UK next: `HANDOFF_UK.md` has the plan, terms, starter accounts and UK filter rules.

## 7. Adology lessons
- Flow: pull_data (quoteOnly) -> confirm_pull (maxCredits) -> check_pull. Unused credits refund a few minutes later.
- Don't cap the number of videos small. 365 days for searches, 60 days for accounts.
- 0 videos in ~15 seconds = outage (happened Oct 5, James fixed it). Failed pulls lock for 12 hours.
- Reading is free but capped at ~25KB per page; page with offset and don't skip items.
- AI summaries can lag behind the videos.

## 8. Claude usage and access (the current blocker)
- Andy's personal Claude account ran out of usage. Adology credits are fine; they belong to the Adology account and work from any AI that connects to the MCP with the same Adology login.
- This chat cost about $87+ at API rates (Oct 1-5). Long chats are expensive; a new chat per task with a short brief costs about 60% less.
- Work can't use Claude unless approved. Analytics is moving to Gemini Enterprise; Christian (engineering) says a week or two.
- To connect another AI: add Adology as a custom MCP connector (URL from claude.ai Settings > Connectors > adologyMCP, or ask James), sign in with the Adology account, paste a handoff doc.
- A new teammate already has the MCP; she got short UK pull instructions and `HANDOFF_UK.md`.

## 9. Next steps
1. UK pull per `HANDOFF_UK.md`.
2. Andy's decisions on Germany (Austria, dropshipper tier).
3. France and Italy with the same method (account pulls, not keyword search).
4. Optional: fill US views/median per category with `scripts/us_tiktok_totals.py` on Andy's laptop.
