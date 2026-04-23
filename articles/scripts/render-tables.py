#!/usr/bin/env python3
"""Render markdown tables as PNG images via headless Chrome.

Produces article-ready table images so Medium can import them as figures
instead of rendering markdown tables (which Medium strips on import).
"""

import os
import re
import subprocess
import tempfile
from pathlib import Path

ARTICLES_DIR = Path(__file__).resolve().parent.parent
IMAGES_DIR = ARTICLES_DIR / "images"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

CSS = """
<style>
  * { box-sizing: border-box; }
  html, body {
    margin: 0;
    padding: 0;
    background: #ffffff;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
                 "Helvetica Neue", Arial, sans-serif;
    color: #1a1a1a;
  }
  body { padding: 32px; }
  table {
    border-collapse: collapse;
    width: 100%;
    font-size: 15px;
    line-height: 1.5;
    background: #ffffff;
  }
  thead th {
    background: #f3f4f6;
    text-align: left;
    font-weight: 600;
    color: #111827;
    padding: 14px 16px;
    border-bottom: 2px solid #d1d5db;
    vertical-align: top;
  }
  tbody td {
    padding: 12px 16px;
    border-bottom: 1px solid #e5e7eb;
    vertical-align: top;
  }
  tbody tr:last-child td { border-bottom: none; }
  tbody tr:nth-child(even) td { background: #fafafa; }
  code {
    font-family: "SF Mono", Menlo, Monaco, Consolas, monospace;
    font-size: 13.5px;
    background: #f1f3f5;
    padding: 2px 6px;
    border-radius: 4px;
    color: #0b4f6c;
  }
  strong { font-weight: 600; }
  td.num { white-space: nowrap; width: 1%; font-variant-numeric: tabular-nums; color: #4b5563; }
  td.money { white-space: nowrap; font-variant-numeric: tabular-nums; }
</style>
"""

# ---- table definitions -----------------------------------------------------
# Each table: (output_filename, window_width, window_height, headers, rows)
# Cell text uses a lightweight inline syntax:
#   `code`      -> <code>code</code>
#   **bold**    -> <strong>bold</strong>
#   An em-dash "—" renders literally.

TABLES = [
    # Part 1 — Setup table
    (
        "part1-table-setup.png",
        900, 240,
        ["Component", "Details"],
        [
            ["Stack", "RKE2 + cert-manager + Route53 + Secrets Manager"],
            ["External service", "OpenVPN Access Server (EC2, public subnet)"],
            ["Cadence", "Publish every 6h; consume every 30 min in midnight–3am window"],
        ],
    ),
    # Part 1 — Gotchas summary
    (
        "part1-table-gotchas.png",
        1200, 460,
        ["#", "Issue", "Symptom", "Fix"],
        [
            ["1", "cert-manager IAM", "DNS-01 challenge fails",
             "Use node instance profile, scope Route53 to your zone"],
            ["2", "`renewBefore` too short", "Cert expires before retries succeed",
             "`renewBefore: 720h` (30-day buffer)"],
            ["3", "Docker Hub rate limits", "Publisher pod `ImagePullBackOff`",
             "Use `public.ecr.aws` base images"],
            ["4", "VPC endpoint private DNS", "AWS CLI calls time out from public subnet",
             "Add SG rule + use `--endpoint-url` fallback"],
            ["5", "`sacli` vs file copy", "Cert not recognized after replacement",
             "Use `sacli ConfigPut` for OpenVPN AS"],
            ["6", "Ansible temp directory", "Playbook permission errors",
             "`ansible_remote_tmp: /tmp/.ansible-${USER}`"],
        ],
    ),
    # Part 1 — Cost table
    (
        "part1-table-cost.png",
        1200, 300,
        ["Item", "Monthly Cost", "Unit Price", "Notes"],
        [
            ["Secrets Manager", "~$0.40",
             "$0.40/secret/month + $0.05/10K API calls",
             "API cost negligible with fingerprint skipping"],
            ["VPC Endpoint", "~$7.20",
             "$0.01/hour/AZ (~$7.20/AZ/month)",
             "Only if not already deployed; shared across services"],
            ["ECR storage", "~$0.008", "$0.10/GB/month",
             "Publisher image is ~80MB; first 500MB free year one"],
            ["CronJob compute", "$0", "—", "Runs on existing K8s nodes"],
        ],
    ),
    # Part 2 — Role / permissions
    (
        "part2-table-permissions.png",
        1200, 290,
        ["Role", "Permissions", "Scope"],
        [
            ["**Publisher CronJob** (K8s)",
             "`PutSecretValue`, `CreateSecret`, `GetSecretValue`",
             "Single secret path (e.g. `openvpn/dev`)"],
            ["**Consumer** (external service)",
             "`GetSecretValue`, `DescribeSecret`",
             "Single secret path"],
            ["**Terraform execution role**",
             "`DescribeSecret` (if used for data lookups)",
             "Single secret path"],
            ["**Everyone else**", "Nothing", "—"],
        ],
    ),
    # Part 2 — Security gotchas
    (
        "part2-table-gotchas.png",
        1200, 460,
        ["#", "Issue", "Risk", "Fix"],
        [
            ["1", "Node role too broad", "Every pod can write certs + modify DNS",
             "IRSA: scope AWS perms to publisher SA (see P-003)"],
            ["2", "Default KMS key", "Any `kms:Decrypt` principal can read secrets",
             "Customer-managed KMS key with explicit policy (see P-002)"],
            ["3", "No resource policy", "IAM-only access control on secrets",
             "Attach Secrets Manager resource policy with explicit Deny"],
            ["4", "IMDSv1 enabled", "SSRF = instant credential theft",
             "`http_tokens = \"required\"` on all instances"],
            ["5", "Certs in `/tmp`", "World-readable private keys",
             "Secure root-owned temp dir with trap cleanup"],
            ["6", "No CloudTrail alarm", "Silent unauthorized access",
             "Monitor `GetSecretValue` for unexpected principals"],
        ],
    ),
]


def render_cell(text: str) -> str:
    """Convert the lightweight inline syntax to HTML (escaping first)."""
    # Escape HTML.
    out = (text.replace("&", "&amp;")
               .replace("<", "&lt;")
               .replace(">", "&gt;"))
    # Bold: **text**
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    # Inline code: `text`
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    return out


def build_html(headers, rows) -> str:
    th_cells = "".join(f"<th>{render_cell(h)}</th>" for h in headers)
    body_rows = []
    # Detect a leading numeric "#" column for tighter styling.
    numeric_first = headers and headers[0].strip() == "#"
    for row in rows:
        tds = []
        for i, cell in enumerate(row):
            cls = ""
            if numeric_first and i == 0:
                cls = ' class="num"'
            tds.append(f"<td{cls}>{render_cell(cell)}</td>")
        body_rows.append("<tr>" + "".join(tds) + "</tr>")
    return f"""<!doctype html>
<html><head><meta charset="utf-8">{CSS}</head>
<body>
<table>
  <thead><tr>{th_cells}</tr></thead>
  <tbody>{''.join(body_rows)}</tbody>
</table>
</body></html>
"""


def render(filename: str, width: int, height: int, html: str) -> Path:
    IMAGES_DIR.mkdir(exist_ok=True)
    out_path = IMAGES_DIR / filename
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as f:
        f.write(html)
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
                f"--window-size={width},{height}",
                f"--screenshot={out_path}",
                f"file://{html_path}",
            ],
            check=True,
            capture_output=True,
        )
    finally:
        os.unlink(html_path)
    return out_path


def main():
    for filename, w, h, headers, rows in TABLES:
        html = build_html(headers, rows)
        out = render(filename, w, h, html)
        size = out.stat().st_size
        print(f"  wrote {out.relative_to(ARTICLES_DIR.parent)} ({size:,} bytes)")





if __name__ == "__main__":
    main()
