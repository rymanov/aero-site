# Aero IPTV — static site

Marketing and legal website for **Aero IPTV**, hosted at **aeroplay.tv**.

## File layout

```
site/
├── index.html          Landing page
├── privacy.html        Privacy policy  (App Store requirement)
├── support.html        Support page    (App Store requirement)
├── styles.css          Shared stylesheet — all three pages use this
├── assets/
│   ├── favicon.svg             SVG favicon (placeholder — replace with final mark)
│   ├── og-image.svg            Open Graph / Twitter card image (1200×630)
│   └── screenshot-hero.png.svg Placeholder screenshot — replace with a real PNG
└── README.md           This file
```

## Preview locally

```bash
cd site
python3 -m http.server 8080
# then open http://localhost:8080
```

## Deploy to a static host

The folder is self-contained — no build step required. Upload the entire `site/` directory.

### Cloudflare Pages / Netlify / GitHub Pages

- **Root directory**: `site/`
- **Build command**: *(none)*
- **Output directory**: `site/` (or `.` if you set root to `site/`)

For GitHub Pages: push the repo and set *Pages → Source → Deploy from branch*, pointing
at the `site/` subfolder (or `docs/` if you rename it).

### URL requirements for App Store

The App Store listing references these URLs — both **must** resolve at launch:

| URL | File |
|-----|------|
| `https://aeroplay.tv/privacy` | `privacy.html` |
| `https://aeroplay.tv/support` | `support.html` |

On most static hosts you'll need to configure clean URLs (drop the `.html` extension) or
add redirect rules. On Cloudflare Pages and Netlify this is handled automatically if you
name the files `privacy.html` / `support.html` — both `/privacy` and `/privacy.html`
will resolve.

## Before going live

1. Replace `assets/screenshot-hero.png.svg` with a real PNG screenshot of the app.
   Update the `<img src="…">` in `index.html` to point at `assets/screenshot-hero.png`.
2. Replace the `href="#"` on the App Store badge link with the real App Store URL once
   the app is approved.
3. Optionally replace `assets/favicon.svg` and `assets/og-image.svg` with final artwork.

## Design notes

- **No external requests** — no CDN fonts, no analytics, no tracking. The privacy policy
  states Aero collects nothing; the site honours that.
- Light/dark mode via `prefers-color-scheme` in `styles.css`.
- All three pages share one stylesheet; edit `styles.css` to restyle everything at once.
