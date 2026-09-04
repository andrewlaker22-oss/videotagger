FROM python:3.11-slim

# ffmpeg is needed by yt-dlp to merge/convert video streams
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

# one worker only: jobs run in a background thread and share one queue,
# more web workers would each start their own queue and split jobs randomly
CMD gunicorn app:app --bind 0.0.0.0:${PORT:-8080} --workers 1 --threads 8 --timeout 120
