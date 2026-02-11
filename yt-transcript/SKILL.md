---
name: youtube-transcript
description: Use when a YouTube video transcript is needed e.g. for summarisation or Q&A on the content.
---

Use this skill when you need the transcript/captions for a YouTube video.

## What this skill does

- Fetches YouTube transcripts with timestamps via a url.

## How to run

This script uses uv inline metadata. If `uv` is available, run:

```bash
uv run scripts/youtube_to_transcript.py https://www.youtube.com/watch?v=VIDEO_ID
```

Provide a YouTube URL or an 11-character video ID.
