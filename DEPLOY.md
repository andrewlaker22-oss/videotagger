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
| `GEMINI_MODEL` | optional, defaults to `gemini-3.7-flash` |
| `DAILY_CAP_USD` | optional, defaults to `10.00` across all users in a rolling 24-hour window |
| `WEEKLY_CAP_USD` | optional, defaults to `70.00` in a rolling 7-day window |
| `MONTHLY_CAP_USD` | optional, defaults to `280.00` in a rolling 30-day window |
| `MAX_VIDEO_SECONDS` | optional, defaults to `60`; longer videos are skipped before Gemini |

Railway redeploys automatically after you save variables.

## 4a. Add the independent provider safety barrier

The limits above are enforced by the app. Also turn on provider-level limits so a bug in the app cannot create an open-ended bill:

- Google Cloud / AI Studio: use a dedicated project for this app and create a Gemini API spend cap budget. Set the provider cap slightly below your true maximum because in-flight requests can finish while a cap is being enforced.
- Apify: Billing -> Limits -> Custom usage limit. Disable overage or set the lowest practical limit for your plan.
- Railway: Workspace Usage -> Set Usage Limits -> Compute hard limit. Railway's documented minimum hard limit is $10.

These provider controls are independent of the app's rolling $10 / $70 / $280 checks.

### How YouTube works

YouTube is handled differently from the other platforms. Apify finds the public video URLs, then Gemini analyzes each YouTube URL directly. Railway does not download the YouTube file, so no YouTube proxy, cookies, browser session, or PO-token service is required.

TikTok, Instagram, and Facebook still use yt-dlp to download a temporary video file before sending it to Gemini. Test one YouTube video after each deployment before starting a larger run. Gemini's direct YouTube URL support is currently a preview feature, so keep an eye on Railway logs after model or SDK upgrades.

## 5. Get the URL
- Service → **Settings → Networking → Generate Domain**. That's your link.

## 6. Make access codes
- Open `https://YOUR-URL/admin`, enter your `ADMIN_CODE`.
- Type a person's name → **Create code**. They get a code like `VT-7K2M4Q` with 100 assets.
- Send them the link + their code. Top up from the same page when they run out.

## Cost, roughly
- Railway: ~$5/mo on the Hobby plan.
- Apify: a few cents per profile pull.
- Gemini: most of the spend. Only videos up to 60 seconds and the first 10 slides of a carousel are analyzed. The 100-per-code bucket, 50-per-run cap, and rolling $10/day, $70/week, and $280/month safety limits are the app-level ceiling.

## Results and analysis fields

The selected count means the most recent posts total, including videos, single images, and carousels. Each carousel is one asset. The standard analysis includes the opening hook, people/count/visible age range, specified-brand logo presence and timing, asset summary, dominant colors, visual details, on-screen text, a clean spoken transcript for videos, and up to 15 normalized object tags.

The finished page displays an AI-written findings summary, counts by asset type, average follower-based engagement rate, top object tags with averages, and clickable high/low outliers. The AI summary is also written in the first row of the raw CSV.

Two files are available after each run:

- Raw CSV: one row per asset with public engagement counts and all analysis fields.
- Excel Analysis Report: `Summary`, `Assets`, `Object Tags`, and `Tag Averages` sheets. The normalized Object Tags sheet has one row per asset/tag combination, so tags such as `burrito bowl` can be filtered and averaged without splitting comma-separated text.

Engagement calculations:

- Known Engagements = reactions + comments + shares + saves, using only publicly available fields.
- Engagement Rate = Known Engagements / Account Followers.
- View Engagement Rate = Known Engagements / Views. When views are unavailable the cell says `No public views available`.
- Shares and saves remain blank when a platform does not expose them; blank does not mean zero.
- With at least 10 comparable follower-based rates, High Outlier is at least two sample standard deviations above the run mean and Low Outlier is at least two below it. All asset types in the current run are compared together.

The home page also has two optional fields:

- Brand or product to look for. If blank, brand/logo fields say `Not specified`.
- Custom analysis focus. This is capped at 1,000 characters and adds a `Custom Focus Findings` CSV column without replacing the standard analysis.

Web, news, Reddit, and X research is not enabled in this build.

## If something breaks
- **"model not found"** → change `GEMINI_MODEL` in Variables to the current flash model (ai.google.dev/gemini-api/docs/models).
- **A public YouTube video is skipped** → confirm the video is public, not private or unlisted. Then check that `GEMINI_MODEL` still supports direct YouTube URL input.
- **Media skipped on Instagram/Facebook** → those platforms sometimes block temporary media downloads or return an expired image URL. Running it again often refreshes the URLs.
- **TikTok says no assets** → use either `@username` or the full profile URL. The app removes browser suffixes such as `?lang=en` automatically and logs Apify's exact error code when a profile is private, missing, empty, or temporarily blocked.
- **Codes disappeared** → you skipped step 3 (volume).
- **Logs** → Railway service → Deployments → View logs. Every skipped video says why.

## Run it on your own machine instead (for testing)
    pip install -r requirements.txt
    set APIFY_TOKEN=...   set GEMINI_API_KEY=...   set ADMIN_CODE=...    (PowerShell: $env:APIFY_TOKEN="...")
    cd C:\Users\andre\OneDrive\Desktop\videotagger
    python app.py
Then open http://127.0.0.1:8080. Needs ffmpeg installed for yt-dlp (winget install ffmpeg).
