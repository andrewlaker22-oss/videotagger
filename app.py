"""
Video Tagger — hosted web app.

Someone opens the link, enters their access code, pastes a profile, picks up to 50 videos,
and gets a tagged CSV. Your Apify + Gemini keys live only in server env vars.

Run locally:   python app.py      (then http://127.0.0.1:8080)
Deploy:        see DEPLOY.md (Railway, ~10 minutes)

ENV VARS (set these on the host, never in code):
  APIFY_TOKEN      your Apify API token
  GEMINI_API_KEY   your Gemini API key
  ADMIN_CODE       the code YOU use to open /admin and mint access codes
  SECRET_KEY       any long random string (signs the admin session cookie)
  GEMINI_MODEL     optional, default gemini-3.5-flash
  DATA_DIR         optional, default /data (attach a Railway volume here so codes persist)
"""

import os, csv, json, time, uuid, shutil, sqlite3, secrets, tempfile, threading, traceback, queue
from datetime import datetime, timedelta
from flask import (Flask, request, redirect, url_for, session, jsonify,
                   send_file, render_template_string, abort)

# ---------------- config ----------------
APIFY_TOKEN    = os.environ.get("APIFY_TOKEN", "")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
ADMIN_CODE     = os.environ.get("ADMIN_CODE", "")
SECRET_KEY     = os.environ.get("SECRET_KEY", secrets.token_hex(32))
GEMINI_MODEL   = os.environ.get("GEMINI_MODEL", "gemini-3.5-flash")
DATA_DIR       = os.environ.get("DATA_DIR", "/data" if os.path.isdir("/data") else os.path.join(os.getcwd(), "data"))
os.makedirs(DATA_DIR, exist_ok=True)
CSV_DIR = os.path.join(DATA_DIR, "csv"); os.makedirs(CSV_DIR, exist_ok=True)
DB_PATH = os.path.join(DATA_DIR, "app.db")

MAX_PER_RUN          = 50      # hard cap per job
DEFAULT_BUCKET       = 100     # videos per access code, total
CSV_KEEP_HOURS       = 24
GEMINI_POLL_MAX      = 60      # x3s = 3 min max wait for Gemini to process one file
ACTORS = {
    "tiktok":    "clockworks/tiktok-profile-scraper",
    "instagram": "apify/instagram-scraper",
    "youtube":   "streamers/youtube-scraper",
    "facebook":  "apify/facebook-posts-scraper",
}
COLUMNS = ["Asset Link","Views","Post Copy","Super (First 2s)","Super (Full Video)",
           "adDescription","visualDescription","visualObjects","visualTechniques"]

app = Flask(__name__)
app.secret_key = SECRET_KEY

# ---------------- db ----------------
def db():
    c = sqlite3.connect(DB_PATH, check_same_thread=False)
    c.row_factory = sqlite3.Row
    return c

def init_db():
    with db() as c:
        c.executescript("""
        CREATE TABLE IF NOT EXISTS codes(
          code TEXT PRIMARY KEY, name TEXT, bucket INTEGER, used INTEGER DEFAULT 0,
          created TEXT);
        CREATE TABLE IF NOT EXISTS jobs(
          id TEXT PRIMARY KEY, code TEXT, platform TEXT, handle TEXT, n INTEGER,
          status TEXT, message TEXT, processed INTEGER DEFAULT 0, total INTEGER DEFAULT 0,
          log TEXT DEFAULT '', csv_path TEXT, created TEXT, finished TEXT);
        """)
        # any job left "running" from a previous boot didn't finish
        c.execute("UPDATE jobs SET status='failed', message='Server restarted mid-run. Run it again.' WHERE status IN ('queued','running')")

def job_update(jid, **kw):
    sets = ", ".join(f"{k}=?" for k in kw)
    with db() as c:
        c.execute(f"UPDATE jobs SET {sets} WHERE id=?", (*kw.values(), jid))

def job_log(jid, line):
    stamp = datetime.now().strftime("%H:%M:%S")
    with db() as c:
        row = c.execute("SELECT log FROM jobs WHERE id=?", (jid,)).fetchone()
        cur = (row["log"] if row else "") or ""
        lines = (cur + f"\n[{stamp}] {line}").strip().split("\n")[-300:]
        c.execute("UPDATE jobs SET log=? WHERE id=?", ("\n".join(lines), jid))

# ---------------- scraping / tagging ----------------
def first_of(d, keys, default=None):
    for k in keys:
        v = d.get(k)
        if v not in (None, "", []): return v
    return default

def apify_input(platform, handle, n):
    h = handle.strip()
    if platform == "tiktok":
        p = h.replace("https://www.tiktok.com/@","").replace("@","").strip("/")
        return {"profiles":[p], "resultsPerPage":n, "shouldDownloadVideos":False}
    if platform == "instagram":
        u = h.replace("https://www.instagram.com/","").replace("http://www.instagram.com/","").replace("@","").strip("/")
        return {"directUrls":[f"https://www.instagram.com/{u}/"], "resultsLimit":n, "resultsType":"posts"}
    if platform == "youtube":
        url = h if h.startswith("http") else f"https://www.youtube.com/@{h.lstrip('@')}"
        return {"startUrls":[{"url":url}], "maxResults":n, "maxResultsShorts":n}
    if platform == "facebook":
        url = h if h.startswith("http") else f"https://www.facebook.com/{h.strip('/')}"
        return {"startUrls":[{"url":url}], "resultsLimit":n}

def scrape_profile(jid, platform, handle, n):
    from apify_client import ApifyClient
    client = ApifyClient(APIFY_TOKEN)
    job_log(jid, f"Pulling last {n} videos from {platform} @{handle}")
    run = client.actor(ACTORS[platform]).call(run_input=apify_input(platform, handle, n))
    if run is None:
        raise RuntimeError("Apify run failed or returned nothing. Check the handle and that the profile is public.")
    # apify-client v3 returns a Run object; older versions returned a dict. Handle both.
    dataset_id = getattr(run, "default_dataset_id", None) or (run.get("defaultDatasetId") if hasattr(run, "get") else None)
    if not dataset_id:
        raise RuntimeError("Apify run finished but had no dataset.")
    out, seen = [], set()
    for it in client.dataset(dataset_id).iterate_items():
        url = first_of(it, ["url","webVideoUrl","videoUrl","postUrl","webpage_url","link","permalink"])
        if not url or url in seen: continue
        seen.add(url)
        cap = first_of(it, ["text","caption","title","description","desc","message"], "")
        if isinstance(cap, dict): cap = cap.get("text","")
        out.append({"url":url,
                    "views":first_of(it,["playCount","views","viewCount","videoViewCount","videoPlayCount","play_count","view_count"]),
                    "caption":cap or ""})
        if len(out) >= n: break
    job_log(jid, f"Found {len(out)} videos")
    return out

def download_video(url, workdir):
    import yt_dlp
    opts = {"outtmpl": os.path.join(workdir, "vid.%(ext)s"),
            "format": "mp4/best[ext=mp4]/best", "format_sort":["res:720"],
            "quiet":True, "no_warnings":True, "noprogress":True}
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=True)
        path = ydl.prepare_filename(info)
        if not os.path.exists(path):
            fs = [os.path.join(workdir,f) for f in os.listdir(workdir) if os.path.isfile(os.path.join(workdir,f))]
            path = max(fs, key=os.path.getsize) if fs else None
        return path, info.get("view_count"), (info.get("description") or info.get("title") or "")

GEMINI_PROMPT = """You are analyzing a single short-form social video. Return ONLY a JSON object, no prose, no markdown fences.

{
  "super_first_2s": "On-screen text appearing ONLY in the first 2 seconds (00:00-00:02). Opening hook text only. Do NOT include text that appears later. Multiple lines in the first 2s: join with ' / '. No text in the first 2s: empty string. Transcribe exactly.",
  "super_full": "ALL on-screen text across the ENTIRE video, in order, joined with ' / '. Exclude spoken audio. None: empty string.",
  "ad_description": "One sentence describing what happens in the video as an ad.",
  "visual_description": "2-3 sentences on the scene, setting, and visual style.",
  "visual_objects": "Comma-separated main objects/characters/products visible.",
  "visual_techniques": "Comma-separated editing/production techniques (jump cuts, kinetic typography, 3D avatar, ASMR audio, POV framing, etc)."
}

Rules: super_first_2s is the FIRST TWO SECONDS ONLY, never merged with later text. Do not invent text; if unreadable, use an empty string. Valid JSON only."""

def gemini_tag(path):
    from google import genai
    client = genai.Client(api_key=GEMINI_API_KEY)
    f = client.files.upload(file=path)
    tries = 0
    while getattr(f.state, "name", str(f.state)) != "ACTIVE":
        if getattr(f.state, "name", str(f.state)) == "FAILED": raise RuntimeError("Gemini could not process this video")
        tries += 1
        if tries > GEMINI_POLL_MAX: raise TimeoutError("Gemini processing timed out")
        time.sleep(3); f = client.files.get(name=f.name)
    resp = client.models.generate_content(model=GEMINI_MODEL, contents=[f, GEMINI_PROMPT])
    txt = (resp.text or "").strip().replace("```json","").replace("```","")
    try: data = json.loads(txt[txt.find("{"):txt.rfind("}")+1])
    except Exception: data = {"visual_description": txt[:400]}
    try: client.files.delete(name=f.name)
    except Exception: pass
    return data

# ---------------- worker ----------------
JOBS = queue.Queue()

def run_job(jid):
    with db() as c:
        j = c.execute("SELECT * FROM jobs WHERE id=?", (jid,)).fetchone()
    if not j: return
    platform, handle, n, code = j["platform"], j["handle"], j["n"], j["code"]
    attempted = 0
    try:
        job_update(jid, status="running", message="Finding videos")
        vids = scrape_profile(jid, platform, handle, n)
        if not vids:
            job_update(jid, status="failed", message="No videos found. Check the handle and that the profile is public.",
                       finished=datetime.now().isoformat())
            return
        job_update(jid, total=len(vids), message=f"Tagging 1 of {len(vids)}")
        rows = []
        for i, v in enumerate(vids, 1):
            attempted = i
            job_update(jid, processed=i-1, message=f"Tagging {i} of {len(vids)}")
            row = {col:"" for col in COLUMNS}
            row["Asset Link"], row["Post Copy"] = v["url"], v["caption"]
            row["Views"] = v["views"] if v["views"] not in (None,"") else ""
            wd = tempfile.mkdtemp(prefix="vt_")
            try:
                path, yv, yd = download_video(v["url"], wd)
                if row["Views"] == "" and yv is not None: row["Views"] = yv
                if not row["Post Copy"] and yd: row["Post Copy"] = yd
                if not path: raise RuntimeError("download produced no file")
                t = gemini_tag(path)
                row["Super (First 2s)"]   = t.get("super_first_2s","")
                row["Super (Full Video)"] = t.get("super_full","")
                row["adDescription"]      = t.get("ad_description","")
                row["visualDescription"]  = t.get("visual_description","")
                row["visualObjects"]      = t.get("visual_objects","")
                row["visualTechniques"]   = t.get("visual_techniques","")
                job_log(jid, f"ok  {i}/{len(vids)}")
            except Exception as e:
                row["adDescription"] = f"[skipped: {e}]"
                job_log(jid, f"skipped {i}/{len(vids)}: {e}")
            finally:
                shutil.rmtree(wd, ignore_errors=True)
            rows.append(row)
        fname = f"{jid}.csv"; fpath = os.path.join(CSV_DIR, fname)
        with open(fpath, "w", newline="", encoding="utf-8-sig") as fh:
            w = csv.DictWriter(fh, fieldnames=COLUMNS); w.writeheader(); w.writerows(rows)
        job_update(jid, status="done", processed=len(vids), csv_path=fpath,
                   message=f"Done. {len(rows)} videos tagged.", finished=datetime.now().isoformat())
    except Exception as e:
        job_log(jid, "error: " + traceback.format_exc().splitlines()[-1])
        job_update(jid, status="failed", message=f"Something broke: {e}", finished=datetime.now().isoformat())
    finally:
        # bucket: we reserved n at submit; give back what wasn't attempted
        refund = max(0, n - attempted)
        if refund:
            with db() as c: c.execute("UPDATE codes SET used=used-? WHERE code=?", (refund, code))

def worker():
    # Serves jobs for as long as the server is up. Each job is bounded (fixed list, per-video timeouts).
    while True:
        jid = JOBS.get()
        try: run_job(jid)
        finally: JOBS.task_done()

def cleaner():
    # Deletes CSVs older than CSV_KEEP_HOURS. Runs once an hour while the server is up.
    while True:
        cutoff = datetime.now() - timedelta(hours=CSV_KEEP_HOURS)
        try:
            with db() as c:
                old = c.execute("SELECT id, csv_path FROM jobs WHERE csv_path IS NOT NULL AND finished < ?",
                                (cutoff.isoformat(),)).fetchall()
                for r in old:
                    try: os.remove(r["csv_path"])
                    except Exception: pass
                    c.execute("UPDATE jobs SET csv_path=NULL WHERE id=?", (r["id"],))
        except Exception: pass
        time.sleep(3600)

# ---------------- ui ----------------
BASE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{{ title }}</title>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&display=swap" rel="stylesheet">
<style>
:root{--paper:#F7F8F6;--ink:#1C2321;--mid:#6B7370;--line:#D9DDD9;--yellow:#F5C842;--green:#2E7D4F;--red:#B3261E}
*{box-sizing:border-box}
html,body{margin:0;background:var(--paper);color:var(--ink);font-family:"IBM Plex Sans",system-ui,sans-serif;font-size:15px;line-height:1.5}
main{max-width:560px;margin:0 auto;padding:56px 24px 80px}
h1{font-size:26px;font-weight:600;margin:0 0 6px;letter-spacing:-.01em}
.lede{color:var(--mid);margin:0 0 32px}
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
.left{display:flex;justify-content:space-between;align-items:baseline;margin-bottom:6px}
.left b{font-size:22px;font-weight:600}
.left span{color:var(--mid);font-size:13px}
.track{height:12px;background:#E4E7E3;border-radius:6px;overflow:hidden}
.fill{height:100%;width:0;background:var(--yellow);transition:width .4s}
.status{margin:22px 0 6px;font-size:16px;font-weight:500}
.log{margin-top:16px;padding:12px;border:1px solid var(--line);border-radius:8px;background:#fff;font-size:12.5px;color:var(--mid);white-space:pre-wrap;max-height:220px;overflow:auto}
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
  <input type="text" id="code" name="code" value="{{ code or '' }}" placeholder="e.g. PS-7K2M4Q" required autocomplete="off">
  {% if left is not none %}<div class="note">{{ left }} videos left on this code</div>{% endif %}

  <label for="platform">Platform</label>
  <select id="platform" name="platform">
    <option value="tiktok">TikTok</option><option value="instagram">Instagram</option>
    <option value="youtube">YouTube</option><option value="facebook">Facebook</option>
  </select>

  <label for="handle">Profile handle or URL</label>
  <input type="text" id="handle" name="handle" placeholder="@pinesol or https://www.tiktok.com/@pinesol" required>

  <label>Recent videos to tag: <span class="n" id="nv">25</span></label>
  <div class="range"><span>10</span><input type="range" name="n" min="10" max="50" value="25" step="5" oninput="nv.textContent=this.value"><span>50</span></div>
  <div class="note">Max 50 per run. Takes about 30 seconds per video.</div>

  <button type="submit">Tag videos</button>
</form>
"""

JOB = """
<h1>{{ 'Done' if j.status=='done' else ('Stopped' if j.status=='failed' else 'Tagging') }}</h1>
<p class="lede">{{ j.platform|capitalize }} · {{ j.handle }} · {{ j.n }} videos requested</p>
<div class="left"><b id="count">{{ j.processed }} / {{ j.total or j.n }}</b><span id="pct"></span></div>
<div class="track"><div class="fill" id="fill"></div></div>
<div class="status" id="msg">{{ j.message }}</div>
<div class="note">You can close this tab. This link keeps your progress: <a href="{{ request.url }}">{{ request.url }}</a></div>
<div id="dl">{% if j.status=='done' %}<a class="btn green" href="/download/{{ j.id }}">Download CSV</a>{% endif %}</div>
{% if j.status=='failed' %}<a class="btn" href="/">Start over</a>{% endif %}
<div class="log" id="log">{{ j.log }}</div>
<script>
let polls=0, t=setInterval(async()=>{
  if(++polls>3000){clearInterval(t);return;}
  const r=await fetch('/api/job/{{ j.id }}'); if(!r.ok) return; const s=await r.json();
  const tot=s.total||s.n; count.textContent=s.processed+' / '+tot;
  const p=tot?Math.round(100*s.processed/tot):0; fill.style.width=p+'%'; pct.textContent=p+'%';
  msg.textContent=s.message; log.textContent=s.log; log.scrollTop=1e9;
  if(s.status==='done'){dl.innerHTML='<a class="btn green" href="/download/'+s.id+'">Download CSV</a>';document.querySelector('h1').textContent='Done';clearInterval(t);}
  if(s.status==='failed'){document.querySelector('h1').textContent='Stopped';clearInterval(t);}
},2500);
</script>
"""

ADMIN_LOGIN = """
<h1>Admin</h1><p class="lede">Enter your admin code.</p>
{% if error %}<div class="err">{{ error }}</div>{% endif %}
<form method="post"><input type="password" name="admin" placeholder="Admin code" required autofocus><button>Open admin</button></form>
"""

ADMIN = """
<h1>Access codes</h1>
<p class="lede">Each code is one person. {{ default_bucket }} videos each by default. Top up when they run out.</p>
<form method="post" action="/admin/mint" class="row2">
  <input type="text" name="name" placeholder="Person's name" required>
  <input type="text" name="bucket" value="{{ default_bucket }}" placeholder="videos">
  <button style="margin-top:0;width:auto;padding:11px 18px">Create code</button>
</form>
<table><tr><th>Code</th><th>Name</th><th>Used</th><th>Left</th><th></th></tr>
{% for c in codes %}<tr>
  <td><code>{{ c.code }}</code></td><td>{{ c.name }}</td><td>{{ c.used }}</td><td>{{ c.bucket - c.used }}</td>
  <td><form method="post" action="/admin/topup" style="display:flex;gap:6px">
      <input type="hidden" name="code" value="{{ c.code }}">
      <input type="text" name="add" value="50" style="width:64px;padding:6px">
      <button style="margin:0;width:auto;padding:6px 10px;font-size:13px">Add</button></form></td>
</tr>{% endfor %}
{% if not codes %}<tr><td colspan="5" style="color:var(--mid)">No codes yet. Create one above.</td></tr>{% endif %}
</table>
<h1 style="margin-top:40px;font-size:20px">Recent runs</h1>
<table><tr><th>When</th><th>Who</th><th>Platform</th><th>Handle</th><th>N</th><th>Status</th></tr>
{% for j in jobs %}<tr><td>{{ j.created[:16].replace('T',' ') }}</td><td>{{ j.name or j.code }}</td><td>{{ j.platform }}</td><td>{{ j.handle }}</td><td>{{ j.n }}</td><td>{{ j.status }}</td></tr>{% endfor %}
</table>
<div class="note" style="margin-top:20px">Total videos tagged, all time: {{ total_used }}</div>
"""

# ---------------- routes ----------------
@app.route("/")
def home():
    return page("Video tagger", HOME, error=request.args.get("e"), code=request.args.get("code"), left=None)

@app.route("/start", methods=["POST"])
def start():
    code = (request.form.get("code") or "").strip().upper()
    platform = request.form.get("platform")
    handle = (request.form.get("handle") or "").strip()
    try: n = int(request.form.get("n", 25))
    except ValueError: n = 25
    n = max(1, min(n, MAX_PER_RUN))
    if platform not in ACTORS or not handle:
        return redirect(url_for("home", e="Pick a platform and paste a handle.", code=code))
    if not (APIFY_TOKEN and GEMINI_API_KEY):
        return redirect(url_for("home", e="Server is missing API keys. Tell Andy.", code=code))
    with db() as c:
        row = c.execute("SELECT * FROM codes WHERE code=?", (code,)).fetchone()
        if not row:
            return redirect(url_for("home", e="That code isn't valid.", code=code))
        left = row["bucket"] - row["used"]
        if left <= 0:
            return redirect(url_for("home", e="This code has 0 videos left. Ask Andy for more.", code=code))
        if n > left:
            n = left  # trim the run to what they have left
        jid = uuid.uuid4().hex[:12]
        c.execute("UPDATE codes SET used=used+? WHERE code=?", (n, code))          # reserve
        c.execute("INSERT INTO jobs(id,code,platform,handle,n,status,message,created) VALUES(?,?,?,?,?,?,?,?)",
                  (jid, code, platform, handle, n, "queued", "Waiting in line", datetime.now().isoformat()))
    JOBS.put(jid)
    return redirect(url_for("job", jid=jid))

@app.route("/job/<jid>")
def job(jid):
    with db() as c:
        j = c.execute("SELECT * FROM jobs WHERE id=?", (jid,)).fetchone()
    if not j: abort(404)
    return page("Tagging", JOB, j=dict(j))

@app.route("/api/job/<jid>")
def api_job(jid):
    with db() as c:
        j = c.execute("SELECT id,status,message,processed,total,n,log FROM jobs WHERE id=?", (jid,)).fetchone()
    if not j: abort(404)
    return jsonify(dict(j))

@app.route("/download/<jid>")
def download(jid):
    with db() as c:
        j = c.execute("SELECT csv_path,platform,handle FROM jobs WHERE id=?", (jid,)).fetchone()
    if not j or not j["csv_path"] or not os.path.exists(j["csv_path"]):
        return page("Expired", "<h1>That CSV is gone</h1><p class='lede'>Downloads are kept for 24 hours.</p><a class='btn' href='/'>Run it again</a>")
    safe = "".join(ch for ch in j["handle"] if ch.isalnum() or ch in "-_")[:40]
    return send_file(j["csv_path"], as_attachment=True, download_name=f"video_tags_{j['platform']}_{safe}.csv")

# ---- admin ----
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
        jobs = [dict(r) for r in c.execute(
            "SELECT j.*, c.name FROM jobs j LEFT JOIN codes c ON c.code=j.code ORDER BY j.created DESC LIMIT 40")]
        total_used = c.execute("SELECT COALESCE(SUM(used),0) t FROM codes").fetchone()["t"]
    return page("Admin", ADMIN, codes=codes, jobs=jobs, total_used=total_used, default_bucket=DEFAULT_BUCKET)

@app.route("/admin/mint", methods=["POST"])
def mint():
    if not is_admin(): abort(403)
    name = (request.form.get("name") or "").strip()[:60]
    try: bucket = int(request.form.get("bucket") or DEFAULT_BUCKET)
    except ValueError: bucket = DEFAULT_BUCKET
    alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    code = "VT-" + "".join(secrets.choice(alphabet) for _ in range(6))
    with db() as c:
        c.execute("INSERT INTO codes(code,name,bucket,used,created) VALUES(?,?,?,0,?)",
                  (code, name, bucket, datetime.now().isoformat()))
    return redirect(url_for("admin"))

@app.route("/admin/topup", methods=["POST"])
def topup():
    if not is_admin(): abort(403)
    try: add = int(request.form.get("add") or 0)
    except ValueError: add = 0
    with db() as c:
        c.execute("UPDATE codes SET bucket=bucket+? WHERE code=?", (add, request.form.get("code")))
    return redirect(url_for("admin"))

# ---------------- boot ----------------
init_db()
threading.Thread(target=worker, daemon=True).start()
threading.Thread(target=cleaner, daemon=True).start()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
