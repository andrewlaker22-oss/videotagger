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
| `YTDLP_PROXY` | optional but recommended for reliable YouTube downloads; a stable HTTP/SOCKS proxy URL |
| `YTDLP_COOKIES_B64` | optional but recommended for YouTube; base64 of a Netscape-format `cookies.txt` file |

Railway redeploys automatically after you save variables.

### Reliable YouTube setup on Railway

YouTube often challenges shared cloud/datacenter addresses even when every video is public. Updating yt-dlp alone does not clear an IP challenge. The patched container includes Deno plus yt-dlp's current JavaScript challenge scripts, which are required baseline support, but the most reliable setup is a stable ISP/residential proxy plus a matching cookie session.

1. Get a stable proxy endpoint you are authorized to use. Put its full URL in `YTDLP_PROXY`, for example `http://user:password@host:port`. Do not commit it to GitHub. Railway's static outbound IP feature makes an IP consistent, but Railway notes those IPs may still be shared, and they remain datacenter addresses, so it is not equivalent to a clean ISP proxy.
2. Configure the same proxy in a private/incognito browser window. Sign in with a dedicated YouTube account, not a personal Google account. In that same tab, open `https://www.youtube.com/robots.txt`, export only the `youtube.com` cookies in Netscape `cookies.txt` format, then close the private window and do not reopen that session. YouTube rotates cookies in open tabs.
3. In PowerShell, copy the cookie file as base64:

       [Convert]::ToBase64String([IO.File]::ReadAllBytes("$PWD\youtube-cookies.txt")) | Set-Clipboard

4. Paste the clipboard value into Railway as `YTDLP_COOKIES_B64`, save, and redeploy.
5. Test one YouTube video first, then ten. The app uses the proxy and cookies only for YouTube. TikTok, Instagram, and Facebook keep their existing download path.

Treat the cookie value like a password. Never put it in the repo, logs, or a support ticket. yt-dlp warns that using an account can lead to temporary or permanent YouTube restrictions. A dedicated account limits the blast radius, but does not remove that risk.

If downloads later fail with PO-token or repeated HTTP 403 errors rather than the sign-in challenge, the next step is a PO Token Provider sidecar using the `mweb` client. Manual PO tokens are not a durable fix because current tokens can be bound to each video. That sidecar is intentionally not bundled into this four-file app because it adds another service and should be deployed and monitored separately.

## 5. Get the URL
- Service → **Settings → Networking → Generate Domain**. That's your link.

## 6. Make access codes
- Open `https://YOUR-URL/admin`, enter your `ADMIN_CODE`.
- Type a person's name → **Create code**. They get a code like `VT-7K2M4Q` with 100 videos.
- Send them the link + their code. Top up from the same page when they run out.

## Cost, roughly
- Railway: ~$5/mo on the Hobby plan.
- YouTube proxy: provider-dependent and not included in the app's cost meter.
- Apify: a few cents per profile pull.
- Gemini: most of the spend. Short social videos run a few cents each; a full 50-video run is usually under a dollar or two. The 100-per-code bucket and 50-per-run cap are your ceiling.

## If something breaks
- **"model not found"** → change `GEMINI_MODEL` in Variables to the current flash model (ai.google.dev/gemini-api/docs/models).
- **YouTube says "Sign in to confirm you're not a bot"** → Railway's egress IP was challenged. Configure both YouTube variables above. If they are already set, refresh the cookies through the exact same proxy and redeploy.
- **Videos all skipped on Instagram/Facebook** → those platforms sometimes block downloads for a bit. Their download settings are unchanged by the YouTube fix.
- **Codes disappeared** → you skipped step 3 (volume).
- **Logs** → Railway service → Deployments → View logs. Every skipped video says why.

## Run it on your own machine instead (for testing)
    pip install -r requirements.txt
    set APIFY_TOKEN=...   set GEMINI_API_KEY=...   set ADMIN_CODE=...    (PowerShell: $env:APIFY_TOKEN="...")
    cd C:\Users\andre\OneDrive\Desktop\videotagger
    python app.py
Then open http://127.0.0.1:8080. Needs ffmpeg installed for yt-dlp (winget install ffmpeg).
