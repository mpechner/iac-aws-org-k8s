# tf_take2
Another attempt at creating AWS infrastructure

**⚠️ AI-Generated Code Warning:** This project was written entirely using **agenic methods** — a combination of Claude (Haiku, Sonnet, Opus) and other AI assistants (Kimi, etc.).

**Critical Lesson:** Even when explicitly requesting security reviews and penetration testing, **basic security principles were missed** by the various agents. Security vulnerabilities including HTTP method exposure (TRACE), missing security headers, and server version disclosure were not caught during initial code generation or code review requests.

**When writing AI-generated infrastructure code:**
- [ ] **Explicit security passes are required** — AI agents do not inherently apply security best practices
- [ ] **Penetration testing is essential** — Automated testing revealed issues missed by AI "code reviews"
- [ ] **Defense in depth must be designed in** — Not automatically added by AI agents
- [ ] **Additional human/AI review cycles are necessary** — First-pass AI code requires security-focused iteration
- [ ] **Document accepted risks** — Some findings (like TRACE for internal dev tools) may be acceptable with proper documentation

See [SECURITY-REVIEW.md](SECURITY-REVIEW.md) and [penetration-test/](penetration-test/) for detailed findings and remediation.

**Note:** This repo is public.

A few years ago I created a AWS eks env in this repo https://github.com/mpechner/terraform_play

In the last 3 years working at a company that used kubernetes, what makes a reasonable environment
has matured.

[Network Plan](VPC/Network-Plan.md)

## What this demonstrates

End-to-end **Infrastructure as Code** for a production-style AWS + Kubernetes environment: VPC, VPN, RKE2 cluster, and a full ingress stack with automatic TLS and DNS. All of it is Terraform-managed with remote state and a clear deployment order.

**Technologies:** Terraform, AWS (VPC, EC2, Route53, IAM, NLBs), Kubernetes (RKE2, EKS, Helm, CRDs), Traefik, cert-manager, external-DNS, Karpenter, KEDA. Security: private subnets, VPN for cluster access, Let's Encrypt production certificates.

Suitable as a reference for multi-account AWS, Kubernetes operations, and ingress/TLS patterns.

---

## Runbooks

Both clusters run in the dev account and share VPC + OpenVPN. Deploy one or the other — not both simultaneously (vCPU quota).

| Runbook | Covers |
|---------|--------|
| [docs/runbook-common.md](docs/runbook-common.md) | Shared infrastructure: VPC, OpenVPN, ECR, org bootstrap |
| [docs/runbook-rke2.md](docs/runbook-rke2.md) | RKE2 cluster on EC2 (us-west-2) |
| [docs/runbook-eks.md](docs/runbook-eks.md) | EKS cluster with Karpenter (us-west-2) |
| [docs/cost-estimate.md](docs/cost-estimate.md) | Hourly cost estimate for the RKE2 and EKS labs |

Each cluster runbook assumes `runbook-common.md` is complete.

**Rough hourly cost** (us-west-2 on-demand, common layer included):

| Lab  | Idle baseline             | With workload               |
|------|---------------------------|-----------------------------|
| RKE2 | **~$0.76/hr** (~$554/mo)  | same (fixed node count)     |
| EKS  | **~$0.52/hr** (~$380/mo)  | ~$0.55–0.90/hr (Karpenter)  |

See [docs/cost-estimate.md](docs/cost-estimate.md) for the full breakdown and cost-reduction wins.