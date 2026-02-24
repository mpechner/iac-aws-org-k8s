# Portfolio / Showcase Recommendations

This document suggests refactoring and documentation improvements to make the repo a stronger hiring showcase. Prioritized by impact vs effort.

---

## 1. Documentation (high impact, low effort)

### 1.1 Root README: "What This Demonstrates" section
**Why:** Viewers spend 30 seconds on the main README. A short "Showcase" or "What this demonstrates" section calls out skills and technologies.

**Add near the top (after intro):**
- One paragraph: end-to-end AWS + Kubernetes IaC (VPC, VPN, RKE2, ingress, TLS, DNS automation).
- Bullet list: Terraform, AWS (VPC, EC2, Route53, IAM), Kubernetes (RKE2, Helm, CRDs), Traefik, cert-manager, external-dNS, Rancher; security (private subnets, VPN, Let's Encrypt prod).
- One line: "Suitable as a reference for multi-account AWS, Kubernetes operations, and ingress/TLS patterns."

**Also fix:** Step 9 still says "Traefik dashboard and Rancher require VPN". Update to: all three (nginx, traefik, rancher) are on the public NLB; no VPN needed once DNS is set.

### 1.2 Architecture diagram
**Why:** A single diagram (VPC → VPN → RKE → Traefik → apps, with DNS/certs) makes the system understandable at a glance.

**Options:**
- **Mermaid** in a doc (e.g. `deployments/dev-cluster/ARCHITECTURE.md`): flow or C4-style component diagram; renders on GitHub.
- **Separate image** in `docs/` and link from README and `deployments/dev-cluster/README.md`.

### 1.3 deployments/dev-cluster/ARCHITECTURE.md
**Why:** Explains the dev-cluster in one place: two-stage deploy, public NLB + external-DNS, Traefik CRD (traefik.io, allowCrossNamespace), Certificate + IngressRoute pattern, why not the applications-module Ingress for these apps.

**Contents:** 1–2 pages: diagram reference, Stage 1 vs Stage 2, data flow (DNS → NLB → Traefik → backend), TLS (cert-manager, prod issuer), pointer to ADDING-NEW-APP.md.

### 1.4 Runbook / operations one-pager
**Why:** Shows you think about operations, not just deployment.

**File:** `deployments/dev-cluster/OPERATIONS.md` (or add a section to README).

**Contents:** Common tasks: add new app (→ ADDING-NEW-APP.md), destroy order (2-apps → 1-infra), renew/force re-issue certs (delete secret), "Not secure" (prod issuer + hard refresh), 404 (allowCrossNamespace, traefik.io IngressRoute). Keep to one page.

### 1.5 Prerequisites and (optional) cost
**Why:** Lets someone evaluate "can I run this?" and "what will it cost?".

**Where:** Root README or a `docs/PREREQUISITES.md`.

**Contents:** Prerequisites: AWS account(s), domain in Route53 (or delegated), Terraform ≥ X, kubectl, VPN client. Optional: rough monthly cost (e.g. "~$Y for dev VPC + EC2 + NLB + …") and "destroy when not in use to minimize cost".

---

## 2. Refactoring (medium impact, medium effort)

### 2.1 Reusable "app ingress" module
**Why:** Right now adding an app = copy-paste Certificate + IngressRoute (see ADDING-NEW-APP.md). A small Terraform module would show DRY and module design.

**Idea:** e.g. `deployments/dev-cluster/modules/app-ingress/`: inputs = hostname (or domain + subdomain), namespace, service name, port; outputs = none; module creates Certificate + IngressRoute in `traefik` namespace (traefik.io, websecure, priority 100). Then nginx, rancher, traefik-dashboard (and new apps) call this module. ADDING-NEW-APP.md becomes "add hostname to NLB, add one module block, apply".

### 2.2 Variable validation
**Why:** Demonstrates production-minded Terraform.

**Where:** `2-applications/variables.tf`, optionally `1-infrastructure/variables.tf`.

**Examples:** `route53_domain` with validation (e.g. no leading/trailing dots, format); `letsencrypt_environment` with `validation { condition = contains(["staging", "prod"], var.letsencrypt_environment) }`.

### 2.3 Fix README inaccuracies
**Why:** Consistency and credibility.

**Items:**
- Root README Step 9: all three (nginx, traefik, rancher) public; remove "VPN required" for traefik/rancher.
- `deployments/dev-cluster/README.md`: "Accessing Services" and "What this deploys" (Stage 2) — mention Rancher, and that nginx/traefik/rancher are all public; link ADDING-NEW-APP.md for adding apps.

---

## 3. Nice to have

### 3.1 ADR (Architecture Decision Record)
**Why:** Shows you document *why*, not just *what*.

**File:** e.g. `docs/adr/001-two-stage-deploy.md`, `002-explicit-ingressroute-vs-ingress.md`.

**Contents:** Short: context, decision, consequences (1–2 paragraphs each).

### 3.2 CI snippet or badge
**Why:** Shows you use automation.

**Idea:** `.github/workflows/terraform-validate.yml` (or similar) that runs `terraform init -backend=false` and `terraform validate` on PRs for 1-infrastructure and 2-applications. Optional: `terraform fmt -check`. Document in README: "CI runs Terraform validate on PRs."

### 3.3 terraform-docs
**Why:** Auto-generated module inputs/outputs look professional.

**Idea:** `terraform-docs` for key modules (e.g. `deployments/modules/nginx-sample`, `modules/ingress/traefik`); add to CI or pre-commit; READMEs reference "see generated docs" or embed.

---

## 4. Priority summary

| Priority | Item | Effort |
|----------|------|--------|
| P0 | Root README: "What this demonstrates" + fix Step 9 (VPN note) | Small |
| P0 | deployments/dev-cluster README: align with current setup, link ADDING-NEW-APP | Small |
| P1 | deployments/dev-cluster/ARCHITECTURE.md (with optional Mermaid diagram) | Small–medium |
| P1 | OPERATIONS.md or runbook section | Small |
| P2 | Reusable app-ingress module | Medium |
| P2 | Variable validation (route53_domain, letsencrypt_environment) | Small |
| P3 | ADR, CI validate, terraform-docs | As time allows |

Starting with the P0 doc updates and one short ARCHITECTURE.md gives the biggest impression for the least effort.
