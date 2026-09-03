"""
Video Tagger - hosted web app.

Someone opens the link, enters their access code, pastes a profile, picks up to 50 videos,
and gets a tagged CSV with a running cost meter. Your Apify + Gemini keys live only in env vars.

Run locally:   python app.py      (then http://127.0.0.1:8080)
Deploy:        see DEPLOY.md

ENV VARS (set on the host, never in code):
  APIFY_TOKEN      your Apify API token
  GEMINI_API_KEY   your Gemini API key
  ADMIN_CODE       the code YOU use to open /admin
  SECRET_KEY       any long random string
  GEMINI_MODEL     optional, default gemini-3.7-flash (half the price of 3.5-flash, same video support)
  DAILY_CAP_USD    optional, default 5.00 - total estimated API spend allowed per day, all users
  DATA_DIR         optional, default /data (attach a Railway volume here)
"""

import os, csv, json, time, uuid, shutil, sqlite3, secrets, tempfile, threading, traceback, queue
from datetime import datetime, timedelta, date
from flask import (Flask, request, redirect, url_for, session, jsonify,
                   send_file, render_template_string, abort)

# ---------------- config ----------------
APIFY_TOKEN    = os.environ.get("APIFY_TOKEN", "")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
ADMIN_CODE     = os.environ.get("ADMIN_CODE", "")
SECRET_KEY     = os.environ.get("SECRET_KEY", secrets.token_hex(32))
GEMINI_MODEL   = os.environ.get("GEMINI_MODEL", "gemini-3.7-flash")
DAILY_CAP_USD  = float(os.environ.get("DAILY_CAP_USD", "5.00"))
DATA_DIR       = os.environ.get("DATA_DIR", "/data" if os.path.isdir("/data") else os.path.join(os.getcwd(), "data"))
os.makedirs(DATA_DIR, exist_ok=True)
CSV_DIR = os.path.join(DATA_DIR, "csv"); os.makedirs(CSV_DIR, exist_ok=True)
DB_PATH = os.path.join(DATA_DIR, "app.db")

MAX_PER_RUN      = 50
DEFAULT_BUCKET   = 100
CSV_KEEP_HOURS   = 24
GEMINI_POLL_MAX  = 60
OVERFETCH        = 3        # ask Apify for 3x posts so after dropping photos we still get N videos
OVERFETCH_CAP    = 150

# ---- pricing (USD). Update here if rates change.
# Sources: ai.google.dev/gemini-api/docs/pricing, and each actor's Apify store page.
PRICE = {
    "gemini_in_per_m":  {"gemini-3.7-flash":0.75, "gemini-3.8-flash":0.75, "gemini-3.6-flash":1.50, "gemini-3.5-flash":1.50},
    "gemini_out_per_m": {"gemini-3.7-flash":3.75, "gemini-3.8-flash":3.75, "gemini-3.6-flash":7.50, "gemini-3.5-flash":9.00},
    "video_tokens_per_sec": 300,   # ~258 image + ~32 audio tokens/sec; only used if Gemini doesn't report usage
    "prompt_tokens": 450, "output_tokens": 400,
    "apify_per_result": {"tiktok":0.004, "instagram":0.0015, "youtube":0.005, "facebook":0.004},
}
def g_in():  return PRICE["gemini_in_per_m"].get(GEMINI_MODEL, 1.50)
def g_out(): return PRICE["gemini_out_per_m"].get(GEMINI_MODEL, 9.00)
def gemini_cost_from_tokens(tin, tout): return tin/1e6*g_in() + tout/1e6*g_out()
def gemini_cost_estimate(duration_s=30):
    return gemini_cost_from_tokens(duration_s*PRICE["video_tokens_per_sec"]+PRICE["prompt_tokens"], PRICE["output_tokens"])
def run_estimate(platform, n):
    return n*gemini_cost_estimate(30) + min(n*OVERFETCH, OVERFETCH_CAP)*PRICE["apify_per_result"][platform]

ACTORS = {
    "tiktok":    "clockworks/tiktok-profile-scraper",
    "instagram": "apify/instagram-scraper",
    "youtube":   "streamers/youtube-scraper",
    "facebook":  "apify/facebook-posts-scraper",
}
COLUMNS = ["Asset Link","Views","Post Copy","Super (First 2s)","Super (Full Video)",
           "adDescription","visualDescription","visualObjects","visualTechniques","Est. Cost (USD)"]

app = Flask(__name__)
app.secret_key = SECRET_KEY

# ---------------- db ----------------
def db():
    c = sqlite3.connect(DB_PATH, check_same_thread=False, timeout=30)
    c.row_factory = sqlite3.Row
    return c

def init_db():
    with db() as c:
        c.executescript("""
        CREATE TABLE IF NOT EXISTS codes(code TEXT PRIMARY KEY, name TEXT, bucket INTEGER, used INTEGER DEFAULT 0, created TEXT);
        CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY, code TEXT, platform TEXT, handle TEXT, n INTEGER,
          status TEXT, message TEXT, processed INTEGER DEFAULT 0, total INTEGER DEFAULT 0,
          log TEXT DEFAULT '', csv_path TEXT, created TEXT, finished TEXT,
          cost REAL DEFAULT 0, cost_lines TEXT DEFAULT '', reserved REAL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS spend(day TEXT PRIMARY KEY, amount REAL DEFAULT 0);
        """)
        for col, typ in [("cost","REAL DEFAULT 0"),("cost_lines","TEXT DEFAULT ''"),("reserved","REAL DEFAULT 0")]:
            try: c.execute("ALTER TABLE jobs ADD COLUMN %s %s" % (col, typ))
            except Exception: pass
        c.execute("UPDATE jobs SET status='failed', message='Server restarted mid-run. Run it again.' WHERE status IN ('queued','running')")

def job_update(jid, **kw):
    with db() as c:
        c.execute("UPDATE jobs SET " + ", ".join(k+"=?" for k in kw) + " WHERE id=?", (*kw.values(), jid))

def job_log(jid, line):
    with db() as c:
        row = c.execute("SELECT log FROM jobs WHERE id=?", (jid,)).fetchone()
        cur = (row["log"] if row else "") or ""
        lines = (cur + "\n[" + datetime.now().strftime('%H:%M:%S') + "] " + line).strip().split("\n")[-300:]
        c.execute("UPDATE jobs SET log=? WHERE id=?", ("\n".join(lines), jid))

def today(): return date.today().isoformat()

def spend_today():
    with db() as c:
        r = c.execute("SELECT amount FROM spend WHERE day=?", (today(),)).fetchone()
        return float(r["amount"]) if r else 0.0

def spend_add(amount):
    with db() as c:
        c.execute("INSERT INTO spend(day,amount) VALUES(?,?) ON CONFLICT(day) DO UPDATE SET amount=amount+?",
                  (today(), amount, amount))

# ---------------- scraping / tagging ----------------
def first_of(d, keys, default=None):
    for k in keys:
        v = d.get(k)
        if v not in (None, "", []): return v
    return default

def apify_input(platform, handle, n):
    h = handle.strip(); want = min(n*OVERFETCH, OVERFETCH_CAP)
    if platform == "tiktok":
        p = h.replace("https://www.tiktok.com/@","").replace("@","").strip("/")
        return {"profiles":[p], "resultsPerPage":n, "shouldDownloadVideos":False}
    if platform == "instagram":
        u = h.replace("https://www.instagram.com/","").replace("http://www.instagram.com/","").replace("@","").strip("/")
        return {"directUrls":["https://www.instagram.com/"+u+"/"], "resultsLimit":want, "resultsType":"posts"}
    if platform == "youtube":
        url = h if h.startswith("http") else "https://www.youtube.com/@"+h.lstrip("@")
        return {"startUrls":[{"url":url}], "maxResults":n, "maxResultsShorts":n}
    if platform == "facebook":
        url = h if h.startswith("http") else "https://www.facebook.com/"+h.strip("/")
        return {"startUrls":[{"url":url}], "resultsLimit":want}

def is_video(platform, it):
    """Drop photos/carousels so N means N actual videos."""
    if platform in ("tiktok","youtube"): return True
    if platform == "instagram":
        t = str(it.get("type","")).lower(); pt = str(it.get("productType","")).lower()
        return t == "video" or pt in ("clips","igtv") or bool(it.get("videoUrl")) or bool(it.get("videoPlayCount"))
    if platform == "facebook":
        if any(it.get(k) for k in ("videoUrl","video","isVideo","videoViewCount")): return True
        media = it.get("media") or []
        return any(str(m.get("__typename","") if isinstance(m,dict) else "").lower().startswith("video") for m in media)
    return True

def scrape_profile(jid, platform, handle, n):
    from apify_client import ApifyClient
    client = ApifyClient(APIFY_TOKEN)
    job_log(jid, "Pulling recent posts from " + platform + " - " + handle + " (need " + str(n) + " videos)")
    run = client.actor(ACTORS[platform]).call(run_input=apify_input(platform, handle, n))
    if run is None:
        raise RuntimeError("Apify run failed. Check the handle and that the profile is public.")
    dataset_id = getattr(run, "default_dataset_id", None) or (run.get("defaultDatasetId") if hasattr(run,"get") else None)
    if not dataset_id: raise RuntimeError("Apify run finished but had no dataset.")
    items = list(client.dataset(dataset_id).iterate_items())
    apify_cost = len(items) * PRICE["apify_per_result"][platform]
    out, seen, dropped = [], set(), 0
    for it in items:
        url = first_of(it, ["url","webVideoUrl","videoUrl","postUrl","webpage_url","link","permalink"])
        if not url or url in seen: continue
        if not is_video(platform, it): dropped += 1; continue
        seen.add(url)
        cap = first_of(it, ["text","caption","title","description","desc","message"], "")
        if isinstance(cap, dict): cap = cap.get("text","")
        out.append({"url":url,
                    "views":first_of(it,["playCount","views","viewCount","videoViewCount","videoPlayCount","play_count","view_count"]),
                    "caption":cap or ""})
        if len(out) >= n: break
    job_log(jid, "Apify returned %d posts - kept %d videos, dropped %d photos/carousels - $%.3f"
            % (len(items), len(out), dropped, apify_cost))
    return out, apify_cost

def download_video(url, workdir):
    import yt_dlp
    opts = {"outtmpl": os.path.join(workdir,"vid.%(ext)s"), "format":"mp4/best[ext=mp4]/best",
            "format_sort":["res:720"], "quiet":True, "no_warnings":True, "noprogress":True}
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=True)
        path = ydl.prepare_filename(info)
        if not os.path.exists(path):
            fs = [os.path.join(workdir,f) for f in os.listdir(workdir) if os.path.isfile(os.path.join(workdir,f))]
            path = max(fs, key=os.path.getsize) if fs else None
        return path, info.get("view_count"), (info.get("description") or info.get("title") or ""), (info.get("duration") or 30)

GEMINI_PROMPT = """You are analyzing a single short-form social video. Return ONLY a JSON object, no prose, no markdown fences.

{
  "super_first_2s": "On-screen text appearing ONLY in the first 2 seconds (00:00-00:02). Opening hook text only. Do NOT include text that appears later. Multiple lines in the first 2s: join with ' / '. No text in the first 2 seconds: empty string. Transcribe exactly.",
  "super_full": "ALL on-screen text across the ENTIRE video, in order, joined with ' / '. Exclude spoken audio. None: empty string.",
  "ad_description": "One sentence describing what happens in the video as an ad.",
  "visual_description": "2-3 sentences on the scene, setting, and visual style.",
  "visual_objects": "Comma-separated main objects/characters/products visible.",
  "visual_techniques": "Comma-separated editing/production techniques (jump cuts, kinetic typography, 3D avatar, ASMR audio, POV framing, etc)."
}

Rules: super_first_2s is the FIRST TWO SECONDS ONLY, never merged with later text. Do not invent text; if unreadable, use an empty string. Valid JSON only."""

def gemini_tag(path, duration_s):
    """Returns (tags dict, cost usd). Uses Gemini's actual billed tokens when reported."""
    from google import genai
    client = genai.Client(api_key=GEMINI_API_KEY)
    f = client.files.upload(file=path)
    tries = 0
    while getattr(f.state,"name",str(f.state)) != "ACTIVE":
        if getattr(f.state,"name",str(f.state)) == "FAILED":
            raise RuntimeError("Gemini could not process this video")
        tries += 1
        if tries > GEMINI_POLL_MAX: raise TimeoutError("Gemini processing timed out")
        time.sleep(3); f = client.files.get(name=f.name)
    resp = client.models.generate_content(model=GEMINI_MODEL, contents=[f, GEMINI_PROMPT])
    um = getattr(resp, "usage_metadata", None)
    tin  = getattr(um, "prompt_token_count", None) if um else None
    tout = getattr(um, "candidates_token_count", None) if um else None
    if tin: cost = gemini_cost_from_tokens(tin, tout or PRICE["output_tokens"])
    else:   cost = gemini_cost_estimate(duration_s)
    txt = (resp.text or "").strip().replace("```json","").replace("```","")
    try: data = json.loads(txt[txt.find("{"):txt.rfind("}")+1])
    except Exception: data = {"visual_description": txt[:400]}
    try: client.files.delete(name=f.name)
    except Exception: pass
    return data, cost

# ---------------- worker ----------------
JOBS = queue.Queue()

def run_job(jid):
    with db() as c:
        j = c.execute("SELECT * FROM jobs WHERE id=?", (jid,)).fetchone()
    if not j: return
    platform, handle, n, code = j["platform"], j["handle"], j["n"], j["code"]
    reserved = float(j["reserved"] or 0)
    attempted, total_cost, lines = 0, 0.0, []
    try:
        job_update(jid, status="running", message="Finding videos")
        vids, apify_cost = scrape_profile(jid, platform, handle, n)
        total_cost += apify_cost; lines.append("%.3f" % apify_cost)
        if not vids:
            job_update(jid, status="failed", cost=total_cost, cost_lines=" + ".join(lines),
                       message="No videos found. Check the handle and that the profile is public.",
                       finished=datetime.now().isoformat())
            return
        job_update(jid, total=len(vids), message="Tagging 1 of %d" % len(vids),
                   cost=total_cost, cost_lines=" + ".join(lines))
        rows, stopped_early = [], False
        for i, v in enumerate(vids, 1):
            if spend_today() - reserved + total_cost + gemini_cost_estimate(30) > DAILY_CAP_USD:
                job_log(jid, "Stopping at video %d: today's $%.2f budget is used up. Saving what's done." % (i, DAILY_CAP_USD))
                stopped_early = True; break
            attempted = i
            job_update(jid, processed=i-1, message="Tagging %d of %d" % (i, len(vids)),
                       cost=total_cost, cost_lines=" + ".join(lines))
            row = {col:"" for col in COLUMNS}
            row["Asset Link"], row["Post Copy"] = v["url"], v["caption"]
            row["Views"] = v["views"] if v["views"] not in (None,"") else ""
            wd = tempfile.mkdtemp(prefix="vt_")
            try:
                path, yv, yd, dur = download_video(v["url"], wd)
                if row["Views"] == "" and yv is not None: row["Views"] = yv
                if not row["Post Copy"] and yd: row["Post Copy"] = yd
                if not path: raise RuntimeError("download produced no file")
                t, vcost = gemini_tag(path, dur)
                row["Super (First 2s)"]   = t.get("super_first_2s","")
                row["Super (Full Video)"] = t.get("super_full","")
                row["adDescription"]      = t.get("ad_description","")
                row["visualDescription"]  = t.get("visual_description","")
                row["visualObjects"]      = t.get("visual_objects","")
                row["visualTechniques"]   = t.get("visual_techniques","")
                row["Est. Cost (USD)"]    = "%.4f" % vcost
                total_cost += vcost; lines.append("%.3f" % vcost)
                job_log(jid, "analyzed video %d (%ds) - $%.3f - running total $%.2f" % (i, int(dur), vcost, total_cost))
            except Exception as e:
                row["adDescription"] = "[skipped: %s]" % e
                row["Est. Cost (USD)"] = "0"
                job_log(jid, "skipped video %d: %s" % (i, str(e)[:120]))
            finally:
                shutil.rmtree(wd, ignore_errors=True)
            rows.append(row)
        fpath = os.path.join(CSV_DIR, jid + ".csv")
        with open(fpath, "w", newline="", encoding="utf-8-sig") as fh:
            w = csv.DictWriter(fh, fieldnames=COLUMNS); w.writeheader(); w.writerows(rows)
        tagged = sum(1 for r in rows if not str(r["adDescription"]).startswith("[skipped"))
        job_log(jid, "cost: " + " + ".join(lines) + " = $%.2f" % total_cost)
        if stopped_early:
            msg = "Stopped at %d of %d: daily budget reached." % (len(rows), len(vids))
        else:
            msg = "Done. %d of %d videos tagged." % (tagged, len(rows))
        msg += " Total ~$%.2f" % total_cost
        job_update(jid, status="done", processed=len(rows), csv_path=fpath, cost=total_cost,
                   cost_lines=" + ".join(lines), message=msg, finished=datetime.now().isoformat())
    except Exception as e:
        job_log(jid, "error: " + traceback.format_exc().splitlines()[-1])
        job_update(jid, status="failed", cost=total_cost, cost_lines=" + ".join(lines),
                   message="Something broke: %s" % e, finished=datetime.now().isoformat())
    finally:
        refund = max(0, n - attempted)
        if refund:
            with db() as c: c.execute("UPDATE codes SET used=used-? WHERE code=?", (refund, code))
        spend_add(total_cost - reserved)   # swap the reservation for what it actually cost

def worker():
    while True:
        jid = JOBS.get()
        try: run_job(jid)
        finally: JOBS.task_done()

def cleaner():
    while True:
        cutoff = (datetime.now() - timedelta(hours=CSV_KEEP_HOURS)).isoformat()
        try:
            with db() as c:
                for r in c.execute("SELECT id, csv_path FROM jobs WHERE csv_path IS NOT NULL AND finished < ?", (cutoff,)).fetchall():
                    try: os.remove(r["csv_path"])
                    except Exception: pass
                    c.execute("UPDATE jobs SET csv_path=NULL WHERE id=?", (r["id"],))
        except Exception: pass
        time.sleep(3600)

# ---------------- ui ----------------
BASE = """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{{ title }}</title>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&display=swap" rel="stylesheet">
<style>
:root{--paper:#F7F8F6;--ink:#1C2321;--mid:#6B7370;--line:#D9DDD9;--yellow:#F5C842;--green:#2E7D4F;--red:#B3261E}
*{box-sizing:border-box}
html,body{margin:0;background:var(--paper);color:var(--ink);font-family:"IBM Plex Sans",system-ui,sans-serif;font-size:15px;line-height:1.5}
main{max-width:560px;margin:0 auto;padding:56px 24px 80px}
h1{font-size:26px;font-weight:600;margin:0 0 6px;letter-spacing:-.01em}
.lede{color:var(--mid);margin:0 0 28px}
label{display:block;font-weight:500;font-size:14px;margin:20px 0 6px}
input[type=text],input[type=password],select{width:100%;padding:11px 12px;border:1px solid var(--line);border-radius:8px;background:#fff;font:inherit;color:var(--ink)}
input:focus,select:focus{outline:2px solid var(--yellow);outline-offset:1px;border-color:var(--yellow)}
.range{display:flex;align-items:center;gap:14px;margin-top:8px}
input[type=range]{flex:1;accent-color:var(--ink)}
.n{font-weight:600;min-width:34px;text-align:right}
button,.btn{margin-top:24px;width:100%;padding:13px;border:0;border-radius:8px;background:var(--ink);color:#fff;font:inherit;font-weight:500;font-size:15px;cursor:pointer;text-align:center;text-decoration:none;display:block}
button:disabled{opacity:.45;cursor:not-allowed}
.btn.green{background:var(--green)}
.err{background:#FBE9E7;color:var(--red);padding:12px;border-radius:8px;margin:0 0 20px;font-size:14px}
.note{color:var(--mid);font-size:13px;margin-top:10px}
.budget{display:flex;justify-content:space-between;font-size:13px;color:var(--mid);margin-top:28px;padding-top:14px;border-top:1px solid var(--line)}
.left{display:flex;justify-content:space-between;align-items:baseline;margin-bottom:6px}
.left b{font-size:22px;font-weight:600}.left span{color:var(--mid);font-size:13px}
.track{height:12px;background:#E4E7E3;border-radius:6px;overflow:hidden}
.fill{height:100%;width:0;background:var(--yellow);transition:width .4s}
.status{margin:22px 0 6px;font-size:16px;font-weight:500}
.cost{font-size:14px;color:var(--mid)}.cost b{color:var(--ink);font-weight:600}
.log{margin-top:16px;padding:12px;border:1px solid var(--line);border-radius:8px;background:#fff;font-size:12.5px;color:var(--mid);white-space:pre-wrap;max-height:240px;overflow:auto}
table{width:100%;border-collapse:collapse;margin-top:18px;font-size:14px}
th,td{text-align:left;padding:9px 6px;border-bottom:1px solid var(--line)}
th{font-weight:500;color:var(--mid)}
code{font-weight:600}
.row2{display:flex;gap:10px}.row2>*{flex:1}
a{color:var(--ink)}
@media (prefers-reduced-motion:reduce){.fill{transition:none}}
</style></head><body><main>{{ body|safe }}</main></body></html>"""

def page(title, body, **ctx):
    return render_template_string(BASE, title=title, body=render_template_string(body, **ctx))

HOME = """
<h1>Video tagger</h1>
<p class="lede">Paste a profile, pick how many recent videos, get a CSV with supers and visual tags.</p>
{% if error %}<div class="err">{{ error }}</div>{% endif %}
<form method="post" action="/start">
  <label for="code">Your access code</label>
  <input type="text" id="code" name="code" value="{{ f.code }}" placeholder="Looks like VT-7K2M4Q" required autocomplete="off">
  <label for="platform">Platform</label>
  <select id="platform" name="platform">
    {% for p,l in [('tiktok','TikTok'),('instagram','Instagram'),('youtube','YouTube'),('facebook','Facebook')] %}
    <option value="{{p}}" {% if f.platform==p %}selected{% endif %}>{{l}}</option>{% endfor %}
  </select>
  <label for="handle">Profile handle or URL</label>
  <input type="text" id="handle" name="handle" value="{{ f.handle }}" placeholder="@pinesol or https://www.tiktok.com/@pinesol" required>
  <label>Recent videos to tag: <span class="n" id="nv">{{ f.n }}</span></label>
  <div class="range"><span>10</span><input type="range" id="nr" name="n" min="10" max="50" value="{{ f.n }}" step="5"><span>50</span></div>
  <div class="note">Max 50 per run, about 30 seconds a video. Estimated <b id="est">$0.00</b> for this run.</div>
  <button type="submit">Tag videos</button>
</form>
<div class="budget"><span>Today's budget</span><span><b>${{ '%.2f'|format(spent) }}</b> of ${{ '%.2f'|format(cap) }} used</span></div>
<script>
var per={{ per_video|tojson }}, ap={{ apify|tojson }}, OF={{ of }}, OFC={{ ofc }};
var nr=document.getElementById('nr'), pl=document.getElementById('platform');
function est(){var n=+nr.value; document.getElementById('nv').textContent=n;
  var e=n*per+Math.min(n*OF,OFC)*ap[pl.value]; document.getElementById('est').textContent='$'+e.toFixed(2);}
nr.oninput=est; pl.onchange=est; est();
</script>
"""

JOB = """
<h1 id="h">{{ 'Done' if j.status=='done' else ('Stopped' if j.status=='failed' else 'Tagging') }}</h1>
<p class="lede">{{ j.platform|capitalize }} - {{ j.handle }} - {{ j.n }} videos requested</p>
<div class="left"><b id="count">{{ j.processed }} / {{ j.total or j.n }}</b><span id="pct"></span></div>
<div class="track"><div class="fill" id="fill"></div></div>
<div class="status" id="msg">{{ j.message }}</div>
<div class="cost">Cost so far <b id="cost">${{ '%.2f'|format(j.cost or 0) }}</b> <span id="lines"></span></div>
<div class="note">You can close this tab. This link keeps your progress: <a href="{{ request.url }}">{{ request.url }}</a></div>
<div id="dl">{% if j.status=='done' %}<a class="btn green" href="/download/{{ j.id }}">Download CSV</a>{% endif %}</div>
{% if j.status=='failed' %}<a class="btn" href="/">Start over</a>{% endif %}
<div class="log" id="log">{{ j.log }}</div>
<script>
var polls=0, t=setInterval(function(){
  if(++polls>3000){clearInterval(t);return;}
  fetch('/api/job/{{ j.id }}').then(function(r){if(!r.ok)throw 0;return r.json();}).then(function(s){
    var tot=s.total||s.n; count.textContent=s.processed+' / '+tot;
    var p=tot?Math.round(100*s.processed/tot):0; fill.style.width=p+'%'; pct.textContent=p+'%';
    msg.textContent=s.message; cost.textContent='$'+(s.cost||0).toFixed(2);
    lines.textContent=s.cost_lines?('= '+s.cost_lines):''; log.textContent=s.log; log.scrollTop=1e9;
    if(s.status==='done'){dl.innerHTML='<a class="btn green" href="/download/'+s.id+'">Download CSV</a>';h.textContent='Done';clearInterval(t);}
    if(s.status==='failed'){h.textContent='Stopped';clearInterval(t);}
  }).catch(function(){});
},2500);
</script>
"""

ADMIN_LOGIN = """<h1>Admin</h1><p class="lede">Enter your admin code.</p>{% if error %}<div class="err">{{ error }}</div>{% endif %}
<form method="post"><input type="password" name="admin" placeholder="Admin code" required autofocus><button>Open admin</button></form>"""

ADMIN = """
<h1>Access codes</h1>
<p class="lede">Each code is one person, {{ default_bucket }} videos by default. Top up when they run out.</p>
<div class="budget" style="margin:0 0 18px;padding:0;border:0"><span>Today's spend, everyone</span><span><b>${{ '%.2f'|format(spent) }}</b> of ${{ '%.2f'|format(cap) }}</span></div>
<form method="post" action="/admin/mint" class="row2">
  <input type="text" name="name" placeholder="Person's name" required>
  <input type="text" name="bucket" value="{{ default_bucket }}">
  <button style="margin-top:0;width:auto;padding:11px 18px">Create code</button>
</form>
<table><tr><th>Code</th><th>Name</th><th>Used</th><th>Left</th><th></th></tr>
{% for c in codes %}<tr><td><code>{{ c.code }}</code></td><td>{{ c.name }}</td><td>{{ c.used }}</td><td>{{ c.bucket - c.used }}</td>
<td><form method="post" action="/admin/topup" style="display:flex;gap:6px"><input type="hidden" name="code" value="{{ c.code }}">
<input type="text" name="add" value="50" style="width:64px;padding:6px"><button style="margin:0;width:auto;padding:6px 10px;font-size:13px">Add</button></form></td></tr>{% endfor %}
{% if not codes %}<tr><td colspan="5" style="color:var(--mid)">No codes yet.</td></tr>{% endif %}
</table>
<h1 style="margin-top:40px;font-size:20px">Recent runs</h1>
<table><tr><th>When</th><th>Who</th><th>Platform</th><th>Handle</th><th>N</th><th>Cost</th><th>Status</th></tr>
{% for j in jobs %}<tr><td>{{ j.created[:16].replace('T',' ') }}</td><td>{{ j.name or j.code }}</td><td>{{ j.platform }}</td><td>{{ j.handle }}</td><td>{{ j.n }}</td><td>${{ '%.2f'|format(j.cost or 0) }}</td><td>{{ j.status }}</td></tr>{% endfor %}
</table>
<div class="note" style="margin-top:20px">All-time videos tagged: {{ total_used }}. All-time estimated spend: ${{ '%.2f'|format(total_cost) }}. Model: {{ model }}</div>
"""

# ---------------- routes ----------------
def form_defaults():
    return {"code": request.args.get("code",""), "platform": request.args.get("platform","tiktok"),
            "handle": request.args.get("handle",""), "n": request.args.get("n","10")}

@app.route("/")
def home():
    return page("Video tagger", HOME, error=request.args.get("e"), f=form_defaults(),
                spent=spend_today(), cap=DAILY_CAP_USD, per_video=round(gemini_cost_estimate(30),4),
                apify=PRICE["apify_per_result"], of=OVERFETCH, ofc=OVERFETCH_CAP)

def back(msg, code, platform, handle, n):
    return redirect(url_for("home", e=msg, code=code, platform=platform, handle=handle, n=n))

@app.route("/start", methods=["POST"])
def start():
    code = (request.form.get("code") or "").strip().upper()
    platform = request.form.get("platform"); handle = (request.form.get("handle") or "").strip()
    try: n = int(request.form.get("n", 10))
    except ValueError: n = 10
    n = max(1, min(n, MAX_PER_RUN))
    if platform not in ACTORS or not handle:
        return back("Pick a platform and paste a handle.", code, platform, handle, n)
    if not (APIFY_TOKEN and GEMINI_API_KEY):
        return back("Server is missing API keys. Tell Andy.", code, platform, handle, n)
    est = run_estimate(platform, n)
    if spend_today() + est > DAILY_CAP_USD:
        left = max(0.0, DAILY_CAP_USD - spend_today())
        return back("Today's $%.2f budget is nearly used up ($%.2f left, this run needs about $%.2f). Try fewer videos or come back tomorrow."
                    % (DAILY_CAP_USD, left, est), code, platform, handle, n)
    with db() as c:
        row = c.execute("SELECT * FROM codes WHERE code=?", (code,)).fetchone()
        if not row: return back("That code isn't valid. Codes look like VT-7K2M4Q.", code, platform, handle, n)
        left = row["bucket"] - row["used"]
        if left <= 0: return back("This code has 0 videos left. Ask Andy for more.", code, platform, handle, n)
        if n > left: n = left
        jid = uuid.uuid4().hex[:12]
        c.execute("UPDATE codes SET used=used+? WHERE code=?", (n, code))
        c.execute("INSERT INTO jobs(id,code,platform,handle,n,status,message,created,reserved) VALUES(?,?,?,?,?,?,?,?,?)",
                  (jid, code, platform, handle, n, "queued", "Waiting in line", datetime.now().isoformat(), est))
    spend_add(est)
    JOBS.put(jid)
    return redirect(url_for("job", jid=jid))

@app.route("/job/<jid>")
def job(jid):
    with db() as c: j = c.execute("SELECT * FROM jobs WHERE id=?", (jid,)).fetchone()
    if not j: abort(404)
    return page("Tagging", JOB, j=dict(j))

@app.route("/api/job/<jid>")
def api_job(jid):
    with db() as c:
        j = c.execute("SELECT id,status,message,processed,total,n,log,cost,cost_lines FROM jobs WHERE id=?", (jid,)).fetchone()
    if not j: abort(404)
    return jsonify(dict(j))

@app.route("/download/<jid>")
def download(jid):
    with db() as c: j = c.execute("SELECT csv_path,platform,handle FROM jobs WHERE id=?", (jid,)).fetchone()
    if not j or not j["csv_path"] or not os.path.exists(j["csv_path"]):
        return page("Expired", "<h1>That CSV is gone</h1><p class='lede'>Downloads are kept for 24 hours.</p><a class='btn' href='/'>Run it again</a>")
    safe = "".join(ch for ch in j["handle"] if ch.isalnum() or ch in "-_")[:40]
    return send_file(j["csv_path"], as_attachment=True, download_name="video_tags_%s_%s.csv" % (j["platform"], safe))

def is_admin(): return session.get("admin") is True

@app.route("/admin", methods=["GET","POST"])
def admin():
    if request.method == "POST":
        if ADMIN_CODE and request.form.get("admin","") == ADMIN_CODE:
            session["admin"] = True; return redirect(url_for("admin"))
        return page("Admin", ADMIN_LOGIN, error="That's not the admin code.")
    if not is_admin(): return page("Admin", ADMIN_LOGIN, error=None)
    with db() as c:
        codes = [dict(r) for r in c.execute("SELECT * FROM codes ORDER BY created DESC")]
        jobs = [dict(r) for r in c.execute("SELECT j.*, c.name FROM jobs j LEFT JOIN codes c ON c.code=j.code ORDER BY j.created DESC LIMIT 40")]
        total_used = c.execute("SELECT COALESCE(SUM(used),0) t FROM codes").fetchone()["t"]
        total_cost = c.execute("SELECT COALESCE(SUM(cost),0) t FROM jobs").fetchone()["t"]
    return page("Admin", ADMIN, codes=codes, jobs=jobs, total_used=total_used, total_cost=total_cost,
                default_bucket=DEFAULT_BUCKET, spent=spend_today(), cap=DAILY_CAP_USD, model=GEMINI_MODEL)

@app.route("/admin/mint", methods=["POST"])
def mint():
    if not is_admin(): abort(403)
    name = (request.form.get("name") or "").strip()[:60]
    try: bucket = int(request.form.get("bucket") or DEFAULT_BUCKET)
    except ValueError: bucket = DEFAULT_BUCKET
    code = "VT-" + "".join(secrets.choice("ABCDEFGHJKMNPQRSTUVWXYZ23456789") for _ in range(6))
    with db() as c:
        c.execute("INSERT INTO codes(code,name,bucket,used,created) VALUES(?,?,?,0,?)",
                  (code, name, bucket, datetime.now().isoformat()))
    return redirect(url_for("admin"))

@app.route("/admin/topup", methods=["POST"])
def topup():
    if not is_admin(): abort(403)
    try: add = int(request.form.get("add") or 0)
    except ValueError: add = 0
    with db() as c: c.execute("UPDATE codes SET bucket=bucket+? WHERE code=?", (add, request.form.get("code")))
    return redirect(url_for("admin"))

# ---------------- boot ----------------
init_db()
threading.Thread(target=worker, daemon=True).start()
threading.Thread(target=cleaner, daemon=True).start()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
