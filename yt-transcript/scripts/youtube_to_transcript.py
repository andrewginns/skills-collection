#!/usr/bin/env -S uv run --script
#
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "youtube-transcript-api>=1.2.3",
# ]
# ///

from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Any, Dict

from youtube_transcript_api import YouTubeTranscriptApi
from youtube_transcript_api.formatters import (
    JSONFormatter,
    PrettyPrintFormatter,
    SRTFormatter,
    TextFormatter,
    WebVTTFormatter,
)

_VIDEO_ID_RE = re.compile(
    r"(?:youtu\.be/|youtube\.com/(?:watch\?.*v=|embed/|v/|shorts/))([A-Za-z0-9_-]{11})"
)


def extract_video_id(url_or_id: str) -> str:
    m = _VIDEO_ID_RE.search(url_or_id)
    if m:
        return m.group(1)
    if re.fullmatch(r"[A-Za-z0-9_-]{11}", url_or_id):
        return url_or_id
    raise SystemExit(f"Could not extract a YouTube video id from: {url_or_id!r}")


def snippet_to_obj(snippet: Any) -> Dict[str, Any]:
    # FetchedTranscriptSnippet has .text/.start/.duration
    return {"text": snippet.text, "start": float(snippet.start), "duration": float(snippet.duration)}


def main() -> None:
    ap = argparse.ArgumentParser(description="Fetch YouTube transcript (captions) with timestamps")
    ap.add_argument("url_or_id", help="YouTube URL or 11-char video id")
    ap.add_argument(
        "--lang",
        action="append",
        default=["en"],
        help="Preferred language codes (repeatable). Example: --lang en --lang en-US",
    )
    ap.add_argument(
        "--format",
        choices=["json", "ndjson", "srt", "vtt", "webvtt", "text", "pretty"],
        default="vtt",
        help="Output format",
    )
    ap.add_argument(
        "--preserve-formatting",
        action="store_true",
        help="Keep HTML formatting in captions when available",
    )
    args = ap.parse_args()

    video_id = extract_video_id(args.url_or_id)

    api = YouTubeTranscriptApi()
    transcript = api.fetch(video_id, languages=args.lang, preserve_formatting=args.preserve_formatting)

    # Stream-friendly for multi-hour videos
    if args.format == "ndjson":
        for snip in transcript:
            sys.stdout.write(json.dumps(snippet_to_obj(snip), ensure_ascii=False) + "\n")
        return

    if args.format == "json":
        sys.stdout.write(JSONFormatter().format_transcript(transcript, ensure_ascii=False))
        sys.stdout.write("\n")
        return

    if args.format == "text":
        sys.stdout.write(TextFormatter().format_transcript(transcript))
        sys.stdout.write("\n")
        return

    if args.format == "pretty":
        sys.stdout.write(PrettyPrintFormatter().format_transcript(transcript))
        sys.stdout.write("\n")
        return

    if args.format == "srt":
        sys.stdout.write(SRTFormatter().format_transcript(transcript))
        return

    # vtt/webvtt
    sys.stdout.write(WebVTTFormatter().format_transcript(transcript))


if __name__ == "__main__":
    main()

