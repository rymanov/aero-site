#!/usr/bin/env python3
"""
check-content-sync.py — guard the website's content against drifting from its
source of truth in the Aero wiki.

The wiki (github.com/rymanov/aero-wiki) owns the canonical text:
  concepts/privacy-policy.md  →  site/privacy.html   (section: Canonical content)
  concepts/support-page.md    →  site/support.html   (section: Canonical content)
  directions/website-v1.md    →  site/index.html     (section: Anchor claims (CI-enforced))

This script verifies that every claim listed in the named wiki section is still
present (word-for-word, ignoring punctuation/case/formatting) in the rendered
<main> of the matching HTML file. It is directional: the wiki is authoritative,
so each wiki claim MUST appear in the HTML. The HTML may carry extra chrome
(page title, "last updated" line, nav) that the wiki page does not.

Two enforcement granularities, by design:
  • Privacy + support are legal/verbatim text → the wiki's full "Canonical
    content" section is enforced (every line).
  • The landing page is marketing copy that changes often → only the curated
    "Anchor claims (CI-enforced)" subset is enforced: the load-bearing strings
    (headlines, feature names, and the neutral-player compliance sentences). Copy
    polish elsewhere on index.html will not trip the check; changing an anchor
    string will, forcing a matching wiki edit.

Scope/limits: this catches the realistic drift — someone edits the HTML copy and
it falls out of sync with the wiki. It does NOT police text the HTML *adds*
beyond the enforced claims, and it compares normalized words, not raw bytes (HTML
markup and markdown formatting differ by design). For a stricter legal diff, read
both side by side. Exits non-zero on any missing claim.

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

# (human label, html file, wiki page, wiki section heading to enforce)
PAIRS = [
    ("Privacy policy", SITE_DIR / "privacy.html", WIKI_DIR / "concepts" / "privacy-policy.md",   "Canonical content"),
    ("Support page",   SITE_DIR / "support.html", WIKI_DIR / "concepts" / "support-page.md",     "Canonical content"),
    ("Landing page",   SITE_DIR / "index.html",   WIKI_DIR / "directions" / "website-v1.md",     "Anchor claims (CI-enforced)"),
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


def wiki_claims(path: Path, section: str) -> list[str]:
    """
    Normalized claim blocks from the named '## <section>' heading, up to the next
    '## ' heading or end of file. One block per non-empty, non-heading line
    (lines starting with '#' — including '###' sub-headings — are skipped).
    """
    text = path.read_text(encoding="utf-8")
    pattern = rf"^##\s+{re.escape(section)}\s*$(.*?)(?=^##\s|\Z)"
    m = re.search(pattern, text, re.M | re.S)
    if not m:
        raise SystemExit(f"ERROR: no '## {section}' section in {path}")
    claims = []
    for line in m.group(1).splitlines():
        line = line.strip()
        if not line or line.startswith("#"):     # skip blanks and sub-headings
            continue
        display = re.sub(r"^[-*]\s+", "", line)  # strip a leading list marker for readable output
        norm = normalize(display)
        if len(norm.split()) >= MIN_WORDS:
            claims.append((display, norm))
    return claims


def check_pair(label: str, html_path: Path, wiki_path: Path, section: str) -> list[str]:
    for p in (html_path, wiki_path):
        if not p.exists():
            raise SystemExit(f"ERROR: missing file {p}")
    haystack = " " + html_main_text(html_path) + " "
    failures = []
    for original, norm in wiki_claims(wiki_path, section):
        if (" " + norm + " ") not in haystack:
            failures.append(original)
    return failures


def main() -> int:
    if not WIKI_DIR.exists():
        print(f"ERROR: wiki dir not found: {WIKI_DIR}")
        print("Clone rymanov/aero-wiki beside this repo, or set AERO_WIKI_DIR.")
        return 2

    total = 0
    for label, html_path, wiki_path, section in PAIRS:
        failures = check_pair(label, html_path, wiki_path, section)
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
