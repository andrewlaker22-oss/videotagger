"""US TikTok totals for the boss table: videos, total views and median views per bucket,
plus the eBay-search vs community-search split, from the master research file.
Read-only. Runs once and exits.
"""
import re
import sys

import pandas as pd

PATH = r"C:\Users\andre\Documents\ebay_research\FINAL_eBay_Research_All_9_Datasets.xlsx"


def find_col(cols, patterns):
    for p in patterns:
        for c in cols:
            if re.search(p, str(c), re.I):
                return c
    return None


try:
    sheets = pd.read_excel(PATH, sheet_name=None)
except FileNotFoundError:
    sys.exit(f"File not found: {PATH}  (change PATH at the top of this script)")

tab = next((n for n in sheets if re.search(r"tiktok", n, re.I) and re.search(r"video", n, re.I)), None)
if tab is None:
    sys.exit(f"No TikTok videos tab found. Tabs are: {list(sheets)}")
df = sheets[tab]
print(f"Tab: {tab} ({len(df)} rows)")

bucket = find_col(df.columns, [r"bucket", r"communit", r"categor"])
views = find_col(df.columns, [r"^views?$", r"view", r"play"])
search = find_col(df.columns, [r"search", r"query", r"keyword", r"source"])
print(f"bucket column: {bucket} | views column: {views} | search column: {search}")
if bucket is None or views is None:
    sys.exit(f"Could not find the bucket or views column. Columns are: {list(df.columns)}")

df["_views"] = pd.to_numeric(df[views], errors="coerce")
g = df.groupby(df[bucket].astype(str))["_views"]
out = pd.DataFrame({"videos": g.size(), "views": g.sum().astype("int64"), "median_views": g.median().round(0)})
out = out.sort_values("videos", ascending=False)
pd.set_option("display.width", 200)
print("\nBy bucket:")
print(out.to_string())
print(f"\nTOTAL: {len(df)} videos | {int(df['_views'].sum()):,} views | median {df['_views'].median():,.0f}")

if search is not None:
    is_ebay = df[search].astype(str).str.contains(r"ebay", case=False)
    for name, part in (("eBay searches", df[is_ebay]), ("community searches", df[~is_ebay])):
        print(f"{name}: {len(part)} videos | {int(part['_views'].sum()):,} views | median {part['_views'].median():,.0f}")

    # Community-search videos only, by bucket (for breaking the 914 into categories like the Germany table)
    print("\nCommunity searches only, by bucket:")
    print(df[~is_ebay].groupby(df[bucket].astype(str)).size().sort_values(ascending=False).to_string())
