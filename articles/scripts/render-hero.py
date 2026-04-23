#!/usr/bin/env python3
"""Render the Medium preview hero image for the tables-as-images article.

Uses the same headless-Chrome approach the article documents — because
it would be silly to do otherwise.
"""

import os
import subprocess
import tempfile
from pathlib import Path

ARTICLES_DIR = Path(__file__).resolve().parent.parent
IMAGES_DIR = ARTICLES_DIR / "images"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

WIDTH, HEIGHT = 1600, 800
OUTPUT = IMAGES_DIR / "tables-as-images-for-medium-hero.png"

HTML = """<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body {
    width: 1600px; height: 800px;
    background: linear-gradient(135deg, #ffffff 0%, #f3f4f6 100%);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
                 "Helvetica Neue", Arial, sans-serif;
    color: #111827;
    overflow: hidden;
  }
  body { padding: 64px 80px; display: flex; flex-direction: column; }

  .eyebrow {
    font-size: 16px;
    color: #6b7280;
    letter-spacing: 0.18em;
    text-transform: uppercase;
    font-weight: 600;
    margin-bottom: 18px;
  }
  h1 {
    font-size: 68px;
    font-weight: 700;
    line-height: 1.05;
    color: #0f172a;
    margin-bottom: 20px;
    letter-spacing: -0.02em;
  }
  .arrow { color: #6366f1; font-weight: 700; }
  .subtitle {
    font-size: 24px;
    color: #374151;
    font-weight: 400;
    line-height: 1.4;
    margin-bottom: 40px;
    max-width: 1100px;
  }

  .split {
    display: flex;
    gap: 32px;
    margin-top: auto;
    align-items: stretch;
  }
  .card {
    flex: 1;
    border-radius: 14px;
    padding: 22px 24px;
    box-shadow: 0 12px 32px rgba(15, 23, 42, 0.08);
    display: flex;
    flex-direction: column;
    min-height: 260px;
  }
  .card .label {
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.18em;
    margin-bottom: 14px;
    font-weight: 600;
  }

  .before { background: #0f172a; color: #e2e8f0; }
  .before .label { color: #64748b; }
  .before pre {
    font-family: "SF Mono", Menlo, Monaco, Consolas, monospace;
    font-size: 16px;
    line-height: 1.65;
    white-space: pre;
    color: #cbd5e1;
  }
  .pipe { color: #64748b; }
  .head-cell { color: #a5b4fc; font-weight: 600; }
  .code-val { color: #86efac; }

  .after { background: #ffffff; }
  .after .label { color: #9ca3af; }
  .after table {
    border-collapse: collapse;
    width: 100%;
    font-size: 15px;
    line-height: 1.5;
  }
  .after thead th {
    background: #f3f4f6;
    color: #111827;
    padding: 10px 14px;
    text-align: left;
    font-weight: 600;
    font-size: 14px;
    border-bottom: 2px solid #d1d5db;
  }
  .after tbody td {
    padding: 10px 14px;
    border-bottom: 1px solid #e5e7eb;
    font-size: 14px;
    vertical-align: top;
  }
  .after tbody tr:last-child td { border-bottom: none; }
  .after tbody tr:nth-child(even) td { background: #fafafa; }
  .after code {
    font-family: Menlo, monospace;
    font-size: 12.5px;
    background: #f1f3f5;
    padding: 2px 6px;
    border-radius: 4px;
    color: #0b4f6c;
  }
</style>
</head>
<body>
  <div class="eyebrow">Technical Writing &middot; Medium Import</div>
  <h1>Markdown Tables <span class="arrow">&rarr;</span> PNG</h1>
  <div class="subtitle">I went looking for the canonical answer. Nobody had written it down. So this is it.</div>

  <div class="split">
    <div class="card before">
      <div class="label">Markdown Source</div>
<pre><span class="pipe">|</span> <span class="head-cell">Item</span>            <span class="pipe">|</span> <span class="head-cell">Monthly Cost</span> <span class="pipe">|</span>
<span class="pipe">|</span>-----------------<span class="pipe">|</span>--------------<span class="pipe">|</span>
<span class="pipe">|</span> Secrets Manager <span class="pipe">|</span> <span class="code-val">~$0.40</span>       <span class="pipe">|</span>
<span class="pipe">|</span> VPC Endpoint    <span class="pipe">|</span> <span class="code-val">~$7.20</span>       <span class="pipe">|</span>
<span class="pipe">|</span> ECR storage     <span class="pipe">|</span> <span class="code-val">~$0.008</span>      <span class="pipe">|</span></pre>
    </div>
    <div class="card after">
      <div class="label">Rendered PNG</div>
      <table>
        <thead><tr><th>Item</th><th>Monthly Cost</th><th>Notes</th></tr></thead>
        <tbody>
          <tr><td>Secrets Manager</td><td>~$0.40</td><td>API cost negligible</td></tr>
          <tr><td>VPC Endpoint</td><td>~$7.20</td><td>$0.01/hour/AZ</td></tr>
          <tr><td>ECR storage</td><td>~$0.008</td><td>~80MB image</td></tr>
        </tbody>
      </table>
    </div>
  </div>
</body>
</html>
"""


def main():
    IMAGES_DIR.mkdir(exist_ok=True)
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as f:
        f.write(HTML)
        html_path = f.name
    try:
        subprocess.run(
            [
                CHROME,
                "--headless=new",
                "--disable-gpu",
                "--hide-scrollbars",
                "--force-device-scale-factor=2",
                "--default-background-color=FFFFFFFF",
                f"--window-size={WIDTH},{HEIGHT}",
                f"--screenshot={OUTPUT}",
                f"file://{html_path}",
            ],
            check=True,
            capture_output=True,
        )
    finally:
        os.unlink(html_path)
    print(f"  wrote {OUTPUT.relative_to(ARTICLES_DIR.parent)} ({OUTPUT.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
