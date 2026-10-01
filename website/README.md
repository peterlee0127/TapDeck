# TapDeck website

An English product site built with Hugo and plain CSS. No theme, JavaScript,
package manager, external fonts, or runtime services are required. The screenshot
viewer uses native radio controls; FAQs use native disclosure controls.

Run from the repository root with Hugo 0.158.0 or later:

```sh
hugo server --source website --bind 127.0.0.1
```

Open <http://localhost:1313>. To build for a real deployment, supply its full URL,
including any subdirectory:

```sh
hugo --source website --minify --baseURL https://your-domain.example/
```

Upload `website/public/` to a static host. Nothing is published automatically.
The Hugo mounts read the existing app icon and screenshots from `Resources/`
and `Documentation/Screenshots/`; build with the full repository checked out.
Hugo generates resized WebP assets and fingerprints the stylesheet.

Edit `layouts/home.html` for page copy, `assets/style.css` for design, and
`hugo.toml` for repository and release links. The download button opens the
GitHub Releases page so it does not pin an app version or invent a DMG URL.

Run the self-contained build/link check (Python 3.11+ and Hugo):

```sh
python3 website/check.py
```

For browser checks, test the screenshot selector with arrow keys, open the FAQs,
and check narrow screens, dark mode, reduced motion, and increased text size.
