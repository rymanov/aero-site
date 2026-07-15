#!/usr/bin/env python3
"""
Generate aero-review-demo.xml - the XMLTV guide for Aero's App Review demo playlist.

Why this exists: Aero's guide is one of its main features, but the demo playlist's
sources publish no schedule, so the guide would render empty for an App Review
reviewer and could not be shown in the App Store screenshots.

This is DEMO DATA, and says so in the file. It describes only openly licensed
content and makes no claim about any third party's real schedule.

Staleness is the real trap: a fixed schedule expires. This generates a long rolling
window from a pinned start date, and prints when it runs out. Re-run before the
window closes (or before any re-review) and re-publish.

    python3 scripts/build-review-epg.py            # writes site/aero-review-demo.xml
    python3 scripts/build-review-epg.py --check    # report coverage of the existing file

Channel ids MUST match tvg-id in aero-review-demo.m3u, or the guide silently
attaches to nothing.
"""
import argparse, datetime as dt, pathlib, re, sys

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent / "aero-review-demo.xml"
PLAYLIST = HERE.parent / "aero-review-demo.m3u"

DAYS = 180          # rolling window length
BLOCK_HOURS = 2     # slot size; keeps the file small and the guide grid readable
START = dt.datetime(2026, 7, 1, 0, 0)   # pinned so regeneration is deterministic

# title/desc per channel. Films carry their real titles and credits; the live and
# reference channels get plainly-worded blocks that assert nothing untrue.
CHANNELS = [
    ("live.testcard", "Live Test Card", "Live Test Card",
     "A continuous live test card: colour bars with an on-screen clock. Generated, not filmed - "
     "there is no underlying work and nothing to license. Exercises live playback and rewind."),
    ("blender.bbb",   "Big Buck Bunny", "Big Buck Bunny",
     "(c) Blender Foundation. Licensed under Creative Commons Attribution 3.0."),
    ("blender.sintel", "Sintel", "Sintel",
     "(c) Blender Foundation. Licensed under Creative Commons Attribution 3.0."),
    ("blender.tos",   "Tears of Steel", "Tears of Steel",
     "(c) Blender Foundation. Licensed under Creative Commons Attribution 3.0."),
    ("blender.ed",    "Elephants Dream", "Elephants Dream",
     "(c) Blender Foundation. Licensed under Creative Commons Attribution 3.0."),
    ("apple.hevc",    "Apple Reference (HEVC)", "HLS Reference Stream (HEVC)",
     "Apple's public HLS reference stream, used to verify playback."),
    ("apple.fmp4",    "Apple Reference (fMP4)", "HLS Reference Stream (fMP4)",
     "Apple's public HLS reference stream, used to verify playback."),
]

def esc(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))

def stamp(d):
    return d.strftime("%Y%m%d%H%M%S") + " +0000"

def playlist_ids():
    if not PLAYLIST.exists():
        return None
    return set(re.findall(r'tvg-id="([^"]+)"', PLAYLIST.read_text(encoding="utf-8")))

def build():
    ids = playlist_ids()
    mine = {c[0] for c in CHANNELS}
    if ids is not None and ids != mine:
        print("*** tvg-id MISMATCH - the guide would attach to nothing ***")
        print("  only in playlist:", sorted(ids - mine) or "-")
        print("  only in this EPG:", sorted(mine - ids) or "-")
        return False

    end = START + dt.timedelta(days=DAYS)
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<!DOCTYPE tv SYSTEM "xmltv.dtd">',
           '<!--',
           '  Aero - demo guide for App Review and App Store screenshots.',
           '  DEMO DATA. Aero ships with no content and no guide; this exists only so the',
           '  guide can be exercised with the demo playlist, whose sources publish no',
           '  schedule. It describes openly licensed or generated content only (live test',
           '  card: synthetic; Blender films: CC-BY; Apple: public reference streams) and',
           '  makes no claim about any third party\'s real schedule.',
           f'  Covers {START:%Y-%m-%d} to {end:%Y-%m-%d}. Regenerate with scripts/build-review-epg.py.',
           '-->',
           '<tv generator-info-name="aero-review-demo">']

    for cid, disp, _, _ in CHANNELS:
        out.append(f'  <channel id="{cid}"><display-name>{esc(disp)}</display-name></channel>')

    n = 0
    for cid, _, title, desc in CHANNELS:
        t = START
        while t < end:
            e = t + dt.timedelta(hours=BLOCK_HOURS)
            out.append(f'  <programme start="{stamp(t)}" stop="{stamp(e)}" channel="{cid}">')
            out.append(f'    <title>{esc(title)}</title>')
            out.append(f'    <desc>{esc(desc)}</desc>')
            out.append('  </programme>')
            t = e
            n += 1
    out.append('</tv>')
    OUT.write_text("\n".join(out) + "\n", encoding="utf-8")
    kb = OUT.stat().st_size / 1024
    print(f"wrote {OUT.name}: {len(CHANNELS)} channels, {n} programmes, {kb:.0f} KB")
    print(f"covers {START:%Y-%m-%d} -> {end:%Y-%m-%d}  ({DAYS} days, {BLOCK_HOURS}h blocks)")
    return True

def check():
    if not OUT.exists():
        print("no EPG file"); return False
    s = OUT.read_text(encoding="utf-8")
    stops = re.findall(r'stop="(\d{14})', s)
    if not stops:
        print("no programmes"); return False
    last = dt.datetime.strptime(max(stops), "%Y%m%d%H%M%S")
    today = dt.datetime.now()
    left = (last - today).days
    print(f"channels={len(re.findall(r'<channel id=', s))} programmes={len(stops)}")
    print(f"guide runs out {last:%Y-%m-%d} ({left} days from now)")
    ids = playlist_ids()
    mine = set(re.findall(r'<channel id="([^"]+)"', s))
    print("tvg-ids match playlist:", "yes" if ids == mine else f"NO - {sorted((ids or set()) ^ mine)}")
    if left < 30:
        print("*** REGENERATE: fewer than 30 days of guide left ***")
    return left >= 30 and ids == mine

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--check", action="store_true")
    a = p.parse_args()
    sys.exit(0 if (check() if a.check else build()) else 1)
