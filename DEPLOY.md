# Deploy the video tagger (Railway, ~10 minutes)

You end up with a URL like `videotagger.up.railway.app` that anyone with an access code can use.
Your keys never leave Railway's settings panel.

## 1. Put the code on GitHub
- Make a new repo (private is fine). Upload these 4 files: `app.py`, `requirements.txt`, `Dockerfile`, `DEPLOY.md`.

## 2. Create the Railway project
- Go to railway.app, sign in, **New Project → Deploy from GitHub repo**, pick the repo.
- It detects the Dockerfile and builds. First build takes 2-3 min (installs ffmpeg).

## 3. Add a volume (so your access codes don't vanish on redeploy)
- In the service, **Settings → Volumes → Add Volume**.
- Mount path: `/data`
- Without this, every redeploy wipes the codes and job history.

## 4. Set the environment variables
Service → **Variables** → add these:

| Variable | Value |
|---|---|
| `APIFY_TOKEN` | your Apify token (apify.com → Settings → Integrations) |
| `GEMINI_API_KEY` | your Gemini key (aistudio.google.com → Get API key) |
| `ADMIN_CODE` | make one up, this opens `/admin` (e.g. a long random phrase) |
| `SECRET_KEY` | any long random string (signs the admin login cookie) |
| `GEMINI_MODEL` | optional, defaults to `gemini-3.5-flash` |

Railway redeploys automatically after you save variables.

## 5. Get the URL
- Service → **Settings → Networking → Generate Domain**. That's your link.

## 6. Make access codes
- Open `https://YOUR-URL/admin`, enter your `ADMIN_CODE`.
- Type a person's name → **Create code**. They get a code like `VT-7K2M4Q` with 100 videos.
- Send them the link + their code. Top up from the same page when they run out.

## Cost, roughly
- Railway: ~$5/mo on the Hobby plan.
- Apify: a few cents per profile pull.
- Gemini: most of the spend. Short social videos run a few cents each; a full 50-video run is usually under a dollar or two. The 100-per-code bucket and 50-per-run cap are your ceiling.

## If something breaks
- **"model not found"** → change `GEMINI_MODEL` in Variables to the current flash model (ai.google.dev/gemini-api/docs/models).
- **Videos all skipped on Instagram/Facebook** → those platforms sometimes block downloads for a bit. TikTok and YouTube are the most reliable.
- **Codes disappeared** → you skipped step 3 (volume).
- **Logs** → Railway service → Deployments → View logs. Every skipped video says why.

## Run it on your own machine instead (for testing)
    pip install -r requirements.txt
    set APIFY_TOKEN=...   set GEMINI_API_KEY=...   set ADMIN_CODE=...    (PowerShell: $env:APIFY_TOKEN="...")
    cd C:\Users\andre\OneDrive\Desktop\videotagger
    python app.py
Then open http://127.0.0.1:8080. Needs ffmpeg installed for yt-dlp (winget install ffmpeg).
