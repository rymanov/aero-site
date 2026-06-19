#!/usr/bin/env python3
"""
check-content-sync.py — guard the website's legal/support pages against drifting
from their source of truth in the Aero wiki.

The wiki (github.com/rymanov/aero-wiki) owns the canonical text:
  concepts/privacy-policy.md  →  site/privacy.html
  concepts/support-page.md    →  site/support.html

This script verifies that every canonical claim from each wiki page is still
present (word-for-word, ignoring punctuation/case/formatting) in the rendered
<main> of the matching HTML file. It is directional: the wiki is authoritative,
so each wiki claim MUST appear in the HTML. The HTML may carry extra chrome
(page title, "last updated" line, nav) that the wiki page does not.

Scope/limits: this catches the realistic drift — someone edits the HTML copy and
it falls out of sync with the wiki. It does NOT police text the HTML *adds*
beyond the wiki, and it compares normalized words, not raw bytes (HTML markup and
markdown formatting differ by design). For a stricter legal diff, read both side
by side. Exits non-zero on any missing claim.

Usage:
    python3 site/scripts/check-content-sync.py
    AERO_WIKI_DIR=/path/to/aero-wiki python3 site/scripts/check-content-sync.py
"""

import html as html_mod
import os
import re
import sys
from pathlib import Path

# script is at <repo>/site/scripts/ ; repo root is two levels up
REPO_ROOT = Path(__file__).resolve().parents[2]
SITE_DIR = REPO_ROOT / "site"
WIKI_DIR = Path(os.environ.get("AERO_WIKI_DIR", REPO_ROOT / "aero-wiki"))

# (human label, html file, wiki page)
PAIRS = [
    ("Privacy policy", SITE_DIR / "privacy.html", WIKI_DIR / "concepts" / "privacy-policy.md"),
    ("Support page",   SITE_DIR / "support.html", WIKI_DIR / "concepts" / "support-page.md"),
]

# claims with fewer than this many words are skipped (headings / labels)
MIN_WORDS = 3


def normalize(text: str) -> str:
    """Lowercase, reduce to alphanumeric words separated by single spaces."""
    return " ".join(re.sub(r"[^a-z0-9]+", " ", text.lower()).split())


def html_main_text(path: Path) -> str:
    """Normalized visible text inside the <main> element."""
    raw = path.read_text(encoding="utf-8")
    m = re.search(r"<main\b[^>]*>(.*?)</main>", raw, re.S | re.I)
    if not m:
        raise SystemExit(f"ERROR: no <main> element found in {path}")
    body = re.sub(r"<[^>]+>", " ", m.group(1))   # drop tags
    return normalize(html_mod.unescape(body))


def wiki_claims(path: Path) -> list[str]:
    """
    Normalized claim blocks from the '## Canonical content' section.
    One block per non-empty, non-heading line.
    """
    text = path.read_text(encoding="utf-8")
    m = re.search(r"^##\s+Canonical content\s*$(.*)", text, re.M | re.S)
    if not m:
        raise SystemExit(f"ERROR: no '## Canonical content' section in {path}")
    claims = []
    for line in m.group(1).splitlines():
        line = line.strip()
        if not line or line.startswith("#"):     # skip blanks and sub-headings
            continue
        norm = normalize(line)
        if len(norm.split()) >= MIN_WORDS:
            claims.append((line, norm))
    return claims


def check_pair(label: str, html_path: Path, wiki_path: Path) -> list[str]:
    for p in (html_path, wiki_path):
        if not p.exists():
            raise SystemExit(f"ERROR: missing file {p}")
    haystack = " " + html_main_text(html_path) + " "
    failures = []
    for original, norm in wiki_claims(wiki_path):
        if (" " + norm + " ") not in haystack:
            failures.append(original)
    return failures


def main() -> int:
    if not WIKI_DIR.exists():
        print(f"ERROR: wiki dir not found: {WIKI_DIR}")
        print("Clone rymanov/aero-wiki beside this repo, or set AERO_WIKI_DIR.")
        return 2

    total = 0
    for label, html_path, wiki_path in PAIRS:
        failures = check_pair(label, html_path, wiki_path)
        if failures:
            total += len(failures)
            print(f"✗ {label}: {len(failures)} canonical claim(s) missing from "
                  f"{html_path.relative_to(REPO_ROOT)}:")
            for f in failures:
                print(f"    • {f}")
        else:
            print(f"✓ {label}: in sync with {wiki_path.relative_to(WIKI_DIR.parent)}")

    if total:
        print(f"\nFAIL: {total} claim(s) drifted. The wiki is the source of truth — "
              f"update the HTML to match, or change the wiki first if the copy should change.")
        return 1
    print("\nOK: website legal/support pages match the wiki.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
