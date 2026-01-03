#!/usr/bin/env python3
# /// script
# dependencies = [
#   "crawl4ai",
# ]
# ///

import argparse
import asyncio
import sys
from typing import List

from crawl4ai import AsyncWebCrawler, BrowserConfig, CacheMode, CrawlerRunConfig


def parse_urls(argv: List[str]) -> List[str]:
    if argv:
        return argv

    stdin_data = sys.stdin.read().strip()
    if not stdin_data:
        return []

    return [line.strip() for line in stdin_data.splitlines() if line.strip()]


def render_markdown(result) -> str:
    markdown = result.markdown
    if isinstance(markdown, str):
        return markdown
    if markdown is None:
        return ""
    return markdown.raw_markdown or ""


def build_run_config(selector: str, min_words: int) -> CrawlerRunConfig:
    return CrawlerRunConfig(
        cache_mode=CacheMode.BYPASS,
        css_selector=selector,
        word_count_threshold=min_words,
        remove_overlay_elements=True,
    )


async def crawl_urls(urls: List[str], selector: str, min_words: int) -> List[object]:
    browser_cfg = BrowserConfig(
        browser_type="chromium",
        headless=True,
        verbose=False,
    )
    run_cfg = build_run_config(selector, min_words)
    fallback_cfg = build_run_config("article", min_words)

    async with AsyncWebCrawler(config=browser_cfg) as crawler:
        if len(urls) == 1:
            result = await crawler.arun(urls[0], config=run_cfg)
            if selector == "article, main, [role=main]" and not render_markdown(result):
                result = await crawler.arun(urls[0], config=fallback_cfg)
            return [result]
        results = await crawler.arun_many(urls, config=run_cfg)
        if selector == "article, main, [role=main]":
            for index, result in enumerate(results):
                if render_markdown(result):
                    continue
                results[index] = await crawler.arun(urls[index], config=fallback_cfg)
        return results


def print_result(url: str, result) -> bool:
    if not result.success:
        print(f"URL: {url}")
        print(f"ERROR: {result.error_message or 'Unknown error'}")
        print("---")
        return False

    markdown = render_markdown(result)
    if not markdown:
        print(f"URL: {url}")
        print("ERROR: Crawl succeeded but no markdown was produced.")
        print("---")
        return False

    print(f"URL: {url}")
    print(markdown)
    print("---")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fetch URLs with Crawl4AI and output raw Markdown.",
    )
    parser.add_argument("urls", nargs="*", help="One or more URLs to crawl.")
    parser.add_argument(
        "--selector",
        default="article, main, [role=main]",
        help="CSS selector targeting the main content container.",
    )
    parser.add_argument(
        "--min-words",
        type=int,
        default=15,
        help="Minimum word count threshold for content extraction.",
    )
    args = parser.parse_args()

    urls = parse_urls(args.urls)
    if not urls:
        parser.error("Provide at least one URL argument or pipe URLs via stdin.")

    results = asyncio.run(crawl_urls(urls, args.selector, args.min_words))

    had_error = False
    for url, result in zip(urls, results):
        success = print_result(url, result)
        if not success:
            had_error = True

    return 1 if had_error else 0


if __name__ == "__main__":
    raise SystemExit(main())
