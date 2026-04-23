# Markdown Tables Don't Survive Medium Import. Here's a Chrome-Only Fix.

*I went looking for the canonical answer. Nobody had written it down. So this is it.*

*Last verified: April 2026.*


> **How this article came to be.** I wrote a couple of articles using Markdown. I tried various methods to import the articles and the tables. I gave up, came back, and this happened. The whole prompt I gave Claude (Anthropic's AI coding assistant, running in Claude Code) was one sentence: *"Take the tables in part1 and part2 and make them images. That will work for moving the articles into medium."* The workflow documented below — headless Chrome, the flags that matter, the CSS, the sizing heuristic, the PyCharm preview cache trap — is what we built together in the chat that followed. Claude proposed the approach, I pushed back when it went off track, and we iterated until the tables rendered.
>
> This article is a second, explicit prompt: *"Write an article documenting all the hoop jumping you did. I looked at a bunch of articles and not one let you loose to do what I just had you do."* So what follows isn't a retrospective essay — it's the AI documenting the workflow it just created, with me steering. Read it accordingly.


## The Problem

Medium lets you import an article from a URL — point it at a Markdown file on GitHub, click Import, you get a drafted post. Beautiful workflow. Until you notice that your carefully-laid-out cost table, permissions matrix, and "gotchas" summary have silently disappeared on the way in.

Medium's importer doesn't render pipe tables. No error, no placeholder, no log. They just aren't there.

The fix most people land on is obvious: replace the tables with images. The harder question is *how* — and after an hour of searching, I couldn't find a single article that walks through generating clean, Medium-quality table images from a normal developer's machine without installing half of npm or rigging up a docs pipeline.

This is that article. The recipe below uses Chrome — the one already on your laptop — and nothing else.


## What I Tried Before Landing on Chrome

Quick inventory of what a typical macOS dev box has sitting around, and whether each would work:

- **matplotlib** — not installed. `pip install matplotlib` would work, but it's a heavy dependency for a one-off and its default table styling is rough.
- **Pillow (PIL)** — not installed. Same story, and image manipulation wasn't even the bottleneck.
- **wkhtmltoimage / wkhtmltopdf** — not installed. The upstream project is in maintenance mode and has WebKit compatibility issues you don't want to debug.
- **ImageMagick (`convert`, `magick`)** — not installed.
- **sips** (macOS native) — can crop and resize, but can't render HTML and can't auto-trim whitespace.
- **Puppeteer / Playwright** — means Node.js, a package install, and a managed browser binary. Overkill for five tables.
- **Google Chrome** — already installed at `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`. And Chrome has a `--screenshot` mode that most people have never used.

Chrome won.


## The Recipe

Chrome's headless mode takes a local HTML file and writes a PNG. One line of shell:

```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
    --headless=new \
    --disable-gpu \
    --hide-scrollbars \
    --force-device-scale-factor=2 \
    --default-background-color=FFFFFFFF \
    --window-size=1200,400 \
    --screenshot=/absolute/path/output.png \
    "file:///absolute/path/input.html"
```

A few of those flags matter more than the others:

- `--headless=new` — the modern headless mode. The legacy implementation rendered subtly different fonts and shadows; don't use it.
- `--force-device-scale-factor=2` — outputs at 2× resolution. Crisp on retina displays, fine after Medium downscales. **This is the single most important flag for quality.**
- `--default-background-color=FFFFFFFF` — without this, Chrome produces a transparent PNG. Transparent PNGs look terrible against Medium's off-white background.
- `--window-size=WIDTH,HEIGHT` — the gotcha. Keep reading.


## The Sizing Gotcha

Chrome's `--screenshot` captures the whole window, not the content. There is no "fit to content" flag from the CLI.

If your window is taller than the table → the image has trailing whitespace.

If your window is shorter than the table → **the bottom rows get silently truncated.** Not an error. You just ship a cut-off table and hope somebody notices before your readers do.

Without Pillow or ImageMagick available to auto-trim, the pragmatic fix is to tune the window height per table. For a table with *n* body rows and standard cell padding, the height is roughly:

```
  32px (top padding)
+ 50px (header row)
+ 50px × n (body rows)
+ 32px (bottom padding)
+ slack for any cells that will line-wrap
```

In practice: pick a number, render, look at the PNG, adjust. My first render of a six-row "gotchas" table at 400px cut row 6 off the bottom; 460px gave it room to breathe. This is tedious but it's a one-time tuning per table.

If you're going to render dozens of tables, this is where Playwright or Puppeteer starts paying off — both let you measure `document.body.scrollHeight` after render and resize the viewport to fit. For five tables across two articles, the manual tuning was faster.


## The Styling

Chrome renders whatever CSS you give it. The goal is "looks at home on Medium" — clean, quiet, readable — not a dashboard screenshot. Core ruleset that held up:

```css
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
               "Helvetica Neue", Arial, sans-serif;
  color: #1a1a1a;
  padding: 32px;
}
table {
  border-collapse: collapse;
  width: 100%;
  font-size: 15px;
  line-height: 1.5;
}
thead th {
  background: #f3f4f6;
  border-bottom: 2px solid #d1d5db;
  padding: 14px 16px;
  text-align: left;
  font-weight: 600;
}
tbody td {
  padding: 12px 16px;
  border-bottom: 1px solid #e5e7eb;
  vertical-align: top;
}
tbody tr:nth-child(even) td { background: #fafafa; }
code {
  font-family: "SF Mono", Menlo, Monaco, Consolas, monospace;
  font-size: 13.5px;
  background: #f1f3f5;
  padding: 2px 6px;
  border-radius: 4px;
  color: #0b4f6c;
}
```

Three choices that made a surprising difference:

1. **System font stack, not Google Fonts.** No network fetch, and the table reads as native macOS rendering (whatever device eventually views the PNG — the font is baked into the pixels at render time).
2. **A 2px underline on the header row, not bordered cells.** Enough visual hierarchy to read the structure, quiet enough to fit Medium's typographic vibe.
3. **Inline `code` styling.** Technical tables are dense with inline snippets (`http_tokens = "required"`, `renewBefore: 720h`, etc). They carry information density; preserve them.


## Preserving Inline Markup in Cell Text

Your source Markdown table has backticks and bold. You want them to render, not leak as literal characters. A ten-line converter is enough — you don't need a real Markdown parser:

```python
def render_cell(text):
    out = (text.replace("&", "&amp;")
               .replace("<", "&lt;")
               .replace(">", "&gt;"))
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    return out
```

HTML-escape everything first, then selectively convert the two inline patterns that actually appear in technical tables. Most cells have zero or one; a few have two. That's all you need.


## Hosting for Medium Import

Medium's importer fetches images over HTTPS during import and re-hosts them on its own CDN. The zero-friction source: commit your PNGs to your GitHub repo and reference them by raw URL.

```markdown
![descriptive alt text](https://raw.githubusercontent.com/USER/REPO/main/articles/images/my-table.png)
```

Two things to know about this pattern:

1. **Alt text becomes the figure caption.** Which means the text you write as "accessibility" copy is what ships to your readers. Make it descriptive, not decorative.
2. **Raw-GitHub URLs go through Fastly.** Propagation is usually fast, but not instantaneous. After pushing, there's a short window where the URL exists but hasn't hit the edge cache yet.


## A PyCharm Cache Trap (Because I Hit It)

If you render locally, push, and open your Markdown preview in PyCharm before the CDN has the file, PyCharm caches the 404. Your preview stays broken even after `curl -I` confirms the URL is live and the image loads fine in a browser.

Fix, cheapest first:

1. Reload the preview pane (toolbar refresh, or right-click → Reload).
2. Close and reopen the `.md` file.
3. `File → Invalidate Caches → Invalidate and Restart` (heavy-handed; works).

It's a preview cache bug, arguably. But it's a bug you will hit, and the fix is trivial once you know.


## Putting It Together

Define your tables as Python data, build the HTML, run it through Chrome, commit the PNGs, reference them by raw URL in your Markdown. That's the whole workflow.

Two scripts do the entire job in my setup — one that renders the batch of content tables, and one that renders the preview image at the top of this post. Both are reproduced in full at the bottom of this article (**Appendix A** and **Appendix B**) so they don't interrupt the reading flow here.


## The Replication Prompt

The original prompt was one sentence (quoted at the top of this article), and the workflow above is what Claude figured out in response. If you want to skip the discovery path and land on the working setup directly, this is the prompt I'd give a fresh chat today:

> I have a Markdown article with pipe tables that I want to publish on Medium, but Medium's importer strips pipe tables on import. Render each table as a PNG using headless Chrome, commit the PNGs to `articles/images/` in this repo, and replace each Markdown table in the source with a single image reference using an absolute `https://raw.githubusercontent.com/USER/REPO/main/articles/images/<file>.png` URL so Medium can fetch it at import time. Write descriptive alt text — Medium uses it as the figure caption.
>
> Use the Chrome on this machine at `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome` with these flags: `--headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --default-background-color=FFFFFFFF --screenshot=<out> file://<html>`. Set `--window-size=WIDTH,HEIGHT` per table — Chrome screenshots the full window, not content-sized, so if the bottom rows get cut off, increase the height; if there's trailing whitespace, decrease it. Tune iteratively, show me each rendered PNG.
>
> Style with inline CSS: system font stack (`-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, …`), light gray header background (`#f3f4f6`), 2px header underline, zebra-striped rows (`#fafafa`), and inline `<code>` with a subtle fill and monospace font. Preserve `**bold**` and `` `code` `` inline markup from the cells with a small regex-based converter — don't bring in a Markdown parser.
>
> After pushing, raw GitHub URLs go through Fastly and take a few seconds to propagate. If an IDE's Markdown preview shows broken images even after `curl -I` returns 200, the preview has cached a 404 — reload the preview pane, don't start changing URL schemes.

Fill in `USER/REPO`, adjust the output directory if your repo layout differs, and hand it over. Most of the hoops in this article get skipped.

Two smaller prompts, for after you have the first pass:

> The rendered image for the [name] table has its last row cut off. Increase the window height and re-render.

> Move the article PNGs from `articles/` into `articles/images/`, update all Markdown references (including the ones in [other articles]), and update the generator script's output path accordingly. Then commit and push.

Both of those I had to issue by hand; both should have been predictable from the first prompt. If I were writing the prompt again I'd roll them in up front.


## What I'd Do Differently With More Time

- **Auto-size via Playwright.** A 50-line Playwright script could render the HTML, read `document.body.scrollHeight`, resize the viewport, and screenshot — no per-table height tuning. Worth it past ~10 tables.
- **Dark-mode variant.** Medium renders your image as-is against whatever theme the reader chose. A light-mode PNG looks like a bright rectangle on the dark theme. A CSS media query plus two screenshots per table would solve it.
- **Parse tables from the Markdown source.** I hand-translated each Markdown table into Python data. A tiny parser that walks the `.md` file and yields `(headers, rows)` tuples would close the loop — edit your article, re-run, images regenerate.

None of these were worth it for five tables across two articles. All of them pay off in a workflow you'll run more than a handful of times.


## Links

- The articles this workflow was built for: [Part 1: Building the cert pipeline](https://github.com/mpechner/iac-aws-org-k8s/blob/main/articles/part1-cert-pipeline-process.md), [Part 2: Securing the pipeline](https://github.com/mpechner/iac-aws-org-k8s/blob/main/articles/part2-cert-pipeline-security.md).
- The production generator scripts: [`articles/scripts/render-tables.py`](https://github.com/mpechner/iac-aws-org-k8s/blob/main/articles/scripts/render-tables.py) (the table batch) and [`articles/scripts/render-hero.py`](https://github.com/mpechner/iac-aws-org-k8s/blob/main/articles/scripts/render-hero.py) (the preview image at the top of this post). Both are reproduced in full in **Appendix A** and **Appendix B** below.
- The rendered PNGs: [`articles/images/`](https://github.com/mpechner/iac-aws-org-k8s/tree/main/articles/images).


## A Note on How This Was Written

The whole workflow above — the Chrome flags, the sizing gotcha, the styling, the PyCharm cache trap — was worked out in a single afternoon, pair-programmed with Claude, on a real deadline: two cert-pipeline articles that needed to ship to Medium.

What the AI was good at, immediately: writing the Python, threading the Chrome flags correctly, producing CSS that looked reasonable on the first render. What it wasn't: it proposed matplotlib first (the dependency wasn't there), undersized the first three table heights (rows got cut off; I had to eyeball the PNGs and say "bigger"), and when the rendered tables didn't show up in my PyCharm preview, its first instinct was to change the URL scheme when the real problem was my IDE's cache. I had to push back before it stopped solving the wrong problem.

That's roughly the right division of labor. The AI moves fast on the generation side. The human still does the *this isn't the right problem* work.

This article exists because when we finished, I realized: "I looked at a bunch of articles and not one of them let you loose to do what I just had you do." The whole chain — Medium strips tables → render to PNG → headless Chrome will do it with no extra tools → here are the flags that matter and the gotchas that don't show up until you're debugging — was nowhere. Writing it down publicly is the cheapest way to save the next person the same afternoon.


---


## Appendix A: `render-tables.py` — The Table Batch Generator

The script that rendered the five tables in the two cert-pipeline articles. Define your tables as Python data at the top, run the script, commit the PNGs. No dependencies beyond the standard library and the Chrome already on your laptop.

The full script is in the Gist below (Medium will auto-embed it when you import; on GitHub it shows as a plain link):

https://gist.github.com/mpechner/f4ff18f806554c1529ee8993535f18c9

Source of truth lives in the repo at [`articles/scripts/render-tables.py`](https://github.com/mpechner/iac-aws-org-k8s/blob/main/articles/scripts/render-tables.py) — the Gist is a synchronized snapshot for embedding.


## Appendix B: `render-hero.py` — The Preview Image Generator

Same Chrome-headless pattern, one-off HTML, used to produce the preview image at the top of this Medium post. Worth showing because it demonstrates the technique isn't table-specific — you can render any HTML fragment to a clean PNG this way.

https://gist.github.com/mpechner/422b7fb3fd3ef81c0eecd1d0248d02cd

Source in the repo at [`articles/scripts/render-hero.py`](https://github.com/mpechner/iac-aws-org-k8s/blob/main/articles/scripts/render-hero.py).

Two scripts, a few hundred lines total, and the only non-stdlib dependency is the Chrome you already have installed.
