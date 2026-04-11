# Security Review

**Reviewer:** Senior DevSecOps  
**Date:** 2026-02-28  
**Scope:** Terraform IaC, Ansible automation, OpenVPN TLS sync pipeline, RKE2 cluster EC2 modules  
**Codebase:** `tf_take2`

---

## How to Read This Document

Two separate passes:

- **Part 1 — Short-Lived Dev Environment**: You know this gets destroyed. What are the risks right now, today, while it exists?
- **Part 2 — Production Hardening**: What would have to change before this becomes a real workload?

Severity ratings: `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO`

---

## Part 1 — Short-Lived Dev Environment: Risks Right Now

These are findings that matter even for a box you're going to destroy in a week, because they can be exploited or leak data in that window.

---

### SEC-001 — ~~`CRITICAL`~~ `LOW (dev) / CRITICAL (prod)` — SSH Private Key Written to Terraform State in Plaintext

**File:** `openvpn/devvpn/sshkey.tf:5-8`, `RKE-cluster/dev-cluster/ec2/sshkey.tf:1-4`

```hcl
resource "tls_private_key" "openvpn_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
```

`tls_private_key` writes the private key PEM to Terraform state. Your S3 state bucket (`mikey-com-terraformstate`) holds a readable copy of every SSH private key for every server in this environment. Anyone with `s3:GetObject` on that bucket owns every box.

**Dev environment impact:** `LOW` — single-user account, S3 public access is blocked, no other IAM principals, environment is short-lived. The risk surface is real but the actual exposure is minimal given these constraints.

**If production:** `CRITICAL`. State is append-only — the key persists in state history even after the resource is destroyed. Any IAM principal that gains read access to the state bucket (not just public access) owns every box. In a team environment this is a confirmed breach path. See P-001 for the fix.

**Mitigation (now):** Verify the state bucket has SSE-KMS encryption and that IAM access to it is locked to `terraform-execute` role only. Run `aws s3api get-bucket-encryption --bucket mikey-com-terraformstate` to confirm.

---

### SEC-002 — ~~`CRITICAL`~~ `MEDIUM (dev) / HIGH (prod)` — RKE Node Secret Read Now Scoped (IRSA Still Needed for Prod)

**File:** `RKE-cluster/modules/ec2/main.tf:196-208`

**Partially resolved 2026-03-03:** `Resource = "*"` replaced with explicit ARN prefixes scoped to only the secrets nodes actually need:

```hcl
{
  Sid    = "ReadScoped"
  Effect = "Allow"
  Action = [
    "secretsmanager:GetSecretValue",
    "secretsmanager:DescribeSecret",
  ]
  Resource = [
    "arn:aws:secretsmanager:${region}:*:secret:openvpn/*",
    "arn:aws:secretsmanager:${region}:*:secret:rke*",
  ]
}
```

**Remaining risk:** All pods on all nodes still share the node IAM role. A compromised pod can still read the RKE2 token and SSH keypair. The full fix is IRSA (see P-003) — but IRSA on RKE2 is non-trivial compared to EKS (requires hosting the OIDC discovery document in S3 and configuring the kube-apiserver issuer URL). Acceptable for dev.

**Dev environment impact:** `MEDIUM` — blast radius now limited to `openvpn/*` and `rke*` secrets only, not the entire account.

---

### SEC-003 — ~~`HIGH`~~ `RESOLVED` — Hardcoded AWS Account ID in Module

**File:** `RKE-cluster/modules/ec2/main.tf:276, 327`

~~Account ID `364082771643` is hardcoded in two `local-exec` provisioner scripts.~~

**Resolved 2026-03-03:**
- Replaced hardcoded account IDs with `data "aws_caller_identity" "current" {}` references throughout the codebase
- Rewrote git history using `git filter-repo` to scrub both account IDs (`364082771643`, `990880295272`) from all commits
- Force-pushed rewritten history to GitHub and toggled repo visibility to purge GitHub's cache
- Verified clean: fresh clone returns `0` occurrences of both account IDs

---

### SEC-004 — ~~`HIGH`~~ `RESOLVED` — TLS Cert and Private Key Written to `/tmp` During Sync

**File:** `openvpn/ansible/openvpn-tls-sync.yml:97, 110`

**Resolved 2026-03-03:** Replaced all `/tmp/` file writes with a secure temp directory:

```bash
WORK_DIR=$(mktemp -d /root/.openvpn-tls-sync-XXXXXX)
chmod 700 "$WORK_DIR"
trap "rm -rf '$WORK_DIR'" EXIT
```

- All cert/key files written to `$WORK_DIR` with `chmod 600`
- `trap EXIT` guarantees cleanup on success, failure, or interrupt — no manual `rm -f` calls needed
- Directory is under `/root/` (mode 700) not `/tmp/` (world-readable)

---

### SEC-005 — ~~`HIGH`~~ `RESOLVED` — Route53 `ChangeResourceRecordSets` Fallback to `*` Removed

**File:** `RKE-cluster/modules/ec2/main.tf:250`

**Resolved 2026-03-03:** The `*` fallback is gone. The policy now unconditionally uses the provided zone IDs:

```hcl
Resource = [for id in var.route53_hosted_zone_ids : "arn:aws:route53:::hostedzone/${id}"]
```

A `validation` block on the variable fails loudly at `terraform plan` time if `route53_hosted_zone_ids` is empty — the dangerous path is now impossible. Zone IDs are passed explicitly from `RKE-cluster/dev-cluster/ec2/variables.tf`.

---

### SEC-006 — ~~`MEDIUM`~~ `RESOLVED` — Unverified Downloads Fixed Across All Ansible Playbooks

**Files:** `openvpn/ansible/openvpn-tls-sync.yml`, `RKE-cluster/modules/server/templates/ansible-playbook.yml.tftpl`, `RKE-cluster/modules/agent/templates/ansible-playbook.yml.tftpl`

**Resolved 2026-03-03:** All download-and-execute patterns now verify checksums before running:

- **AWS CLI** (all 3 playbooks) — SHA256 checksum downloaded from AWS and verified with `sha256sum --check` before unzip/install. Uses `mktemp -d` + `trap EXIT` for cleanup.
- **RKE2 installer** (server + agent) — installer script downloaded separately from `get.rke2.io`, checksum verified before `sh install.sh`. No more `curl | sh`.
- **Docker Compose** — removed entirely (2026-02-28). RKE2 uses containerd directly; Docker Compose was never called after install. Dead code eliminated rather than upgraded.

---

### SEC-007 — `INFO (dev)` / `MEDIUM (prod)` — Secrets Manager Recovery Window

**Files:** `openvpn/devvpn/sshkey.tf`, `RKE-cluster/dev-cluster/ec2/sshkey.tf`, `RKE-cluster/dev-cluster/RKE/main.tf`, `modules/irsa/main.tf`

**Updated 2026-03-03:** `recovery_window_in_days` is now a variable `secret_recovery_window_days` in each deployment, defaulting to `0` for dev (correct — enables clean destroy/apply cycles with no 30-day name conflicts).

For production: set `secret_recovery_window_days = 30` in the production `terraform.tfvars`. The default of `0` is intentional for dev.

---

### SEC-008 — `MEDIUM` — OpenVPN Admin UI (Port 943) and HTTP (Port 80) Open to Dynamic IP Detection

**File:** `openvpn/devvpn/main.tf:4-10`, `openvpn/module/main.tf:104-120`

```hcl
data "http" "my_ip" {
  url = "https://ipv4.icanhazip.com"
}
local.admin_ip = var.comcast_ip != "" ? var.comcast_ip : "${local.my_ip}/32"
```

Admin access (ports 22, 80, 943) is scoped to your detected IP — good. But `icanhazip.com` is a third-party service. If it returns an incorrect IP (misconfiguration, brief hijack, or the variable `comcast_ip` is left blank after an ISP change), your rules could end up with the wrong CIDR. There's no validation that `local.my_ip` is actually a valid IPv4 address before appending `/32`.

**Dev environment impact:** Low — `icanhazip.com` is reliable. But worth noting.

---

### SEC-009 — ~~`LOW`~~ `RESOLVED` — Ansible TLS Sync Failure Now Visible

**File:** `openvpn/devvpn/main.tf:115`

**Resolved 2026-03-03:** Replaced silent `|| true` with an explicit warning block. Failure is now visible in the apply output with instructions to retry, but does not fail the apply (the instance is already running and VPN is functional — the cron job is the only missing piece). The `null_resource` is left tainted so the next `terraform apply` retries automatically.

---

### SEC-010 — `LOW (dev) / HIGH (prod)` — TRACE HTTP Method Enabled (XST Vulnerability Risk)

**Files:** Kubernetes ingress stack (`traefik` namespace), affects all services behind Traefik

**Finding:** The TRACE HTTP method is enabled on Rancher (`rancher.dev.foobar.support`) and returns HTTP 200 instead of 405 Method Not Allowed.

**Cross-Site Tracing (XST) Attack:**
- TRACE echoes back the HTTP request including headers
- Attackers use JavaScript to send TRACE requests and read the response
- Steals cookies marked `HttpOnly`, bypassing XSS protections
- Can expose authentication tokens and sensitive headers

**Dev environment impact:** `LOW` — Site requires VPN access, limiting attack surface. Internal tool with restricted access.

**If production:** `HIGH` — Any authenticated user could have their session stolen via XST. Must be blocked.

**Mitigation (now):** 
- **Development:** ACCEPTED for VPN-only internal tools. Documented as known risk pending production fix.
- **Production:** Implement AWS WAF WebACL on internal NLB with rule to block TRACE/OPTIONS methods:

```hcl
resource "aws_wafv2_web_acl" "internal_nlb" {
  name  = "internal-nlb-waf"
  scope = "REGIONAL"

  rule {
    name     = "BlockHTTPMethods"
    priority = 1
    action { block {} }
    
    statement {
      byte_match_statement {
        field_to_match { method {} }
        positional_constraint = "EXACTLY"
        search_string         = "TRACE"
        text_transformation {
          priority = 0
          type     = "LOWERCASE"
        }
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockHTTPMethods"
      sampled_requests_enabled   = true
    }
  }
}
```

**Files Modified:**
- `deployments/rke-apps/1-infrastructure/main.tf` — Added `block_trace_global` IngressRoute (Traefik-level attempt)
- `penetration-test/tests/test-info-disclosure.sh` — Test updated to accept HTTP 405 as success

**Note:** Traefik IngressRoute approach (priority 0 route matching `Method(TRACE)`) was insufficient. Rancher's explicit host-based route takes precedence. AWS WAF is the correct production fix.

---

## Part 2 — Production Hardening

These are the architectural and design changes required before any version of this becomes a production workload.

---

### P-001 — ~~`CRITICAL`~~ `RESOLVED (dev)` / `CRITICAL (prod without rotation procedure)` — Eliminate `tls_private_key` from Terraform State

**Files:** `openvpn/devvpn/sshkey.tf`, `RKE-cluster/dev-cluster/ec2/sshkey.tf`

**Resolved 2026-02-28 (key generation):** `tls_private_key` removed from both `sshkey.tf` files. Keys are now generated by `scripts/create-openvpn-ssh-key.sh` and `scripts/create-rke-ssh-key.sh` before `terraform apply`. Terraform reads only the public key from Secrets Manager to register the EC2 key pair. The private key never enters Terraform state.

**Deployment order:** Scripts must be run before `terraform apply` or the `data` source will fail with `ResourceNotFoundException`. This is intentional — it prevents silent key generation in state.

**Key rotation procedure (important operational note):**

Rotating a key by running the script with `--force` and then `terraform apply` updates:
- The secret in Secrets Manager ✓
- The EC2 key pair registered in AWS ✓
- The local private key file (`~/.ssh/rke-key`, `~/.ssh/openvpn-ssh`) ✓

It does **not** update `~/.ssh/authorized_keys` on running instances. AWS key pairs are only used at instance launch. A running instance retains the old public key in `authorized_keys` indefinitely.

**Rotation options for running instances:**

| Method | When to use |
|--------|-------------|
| Teardown + rebuild | Dev — simplest, guaranteed clean state |
| Ansible playbook to push new `authorized_keys` | Prod — rotate without downtime; run before AWS key pair update |
| Userdata that reads public key from Secrets Manager on boot | Future hardening — makes every launch self-healing |

**For production:** implement the Ansible rotation playbook before enabling key rotation as a scheduled operation.

---

### P-002 — ~~`CRITICAL`~~ `MEDIUM (dev) / HIGH (prod)` — IAM Policies Scoped to Least Privilege

Three policies needed rewriting:

**RKE nodes Secrets Manager — RESOLVED 2026-03-03 (see SEC-002):**
`Resource = "*"` replaced with explicit ARN prefixes (`openvpn/*`, `rke-ssh*`, `dev-rke2-token*`).

**RKE nodes Route53 — RESOLVED 2026-03-03 (see SEC-005):**
Wildcard fallback removed. `route53_hosted_zone_ids` validated non-empty; `ChangeResourceRecordSets` scoped to explicit zone ARNs only.

**OpenVPN KMS — RESOLVED 2026-02-28:**
`Resource = "arn:aws:kms:*:*:key/*"` replaced with a scoped conditional statement.

Secrets Manager **always** uses KMS for envelope encryption — either the AWS-managed key (`aws/secretsmanager`) or a CMK. `kms:Decrypt` is therefore always required. The previous policy had no `kms:ViaService` condition, which meant the wildcard granted unrestricted KMS Decrypt across the account.

The fix uses `kms:ViaService` to constrain the grant to calls originating from Secrets Manager in this region only:

```hcl
{
  Sid      = "DecryptSecretsManagerEnvelope"
  Action   = ["kms:Decrypt"]
  Resource = var.kms_key_arn != "" ? var.kms_key_arn : "*"
  Condition = {
    StringEquals = {
      "kms:ViaService" = "secretsmanager.${region}.amazonaws.com"
    }
  }
}
```

- **No CMK (AWS-managed key `aws/secretsmanager`):** `Resource = "*"` but `kms:ViaService` locks it — the role cannot call KMS directly for any other purpose.
- **CMK provided (`kms_key_arn`):** `Resource` is narrowed to that single key ARN — double-scoped.
- `kms:GenerateDataKey` is included only when `enable_tls_sync = true` (the server writes a secret); otherwise omitted.

To use a CMK: pass `kms_key_arn = aws_kms_key.secrets.arn` to `module.openvpn`.

**Remaining (production only):** Full IRSA so each workload gets its own scoped role, not the shared node role — see P-003.

---

### P-003 — `CRITICAL` — Replace Node-Level IAM with IRSA for Kubernetes Workloads

**File:** `RKE-cluster/modules/ec2/main.tf:191-254`, `RKE-cluster/modules/server/iam.tf`

The cert-manager, external-dns, and openvpn-cert-publisher CronJob all inherit permissions from the EC2 node IAM role. This is a blast-radius problem: compromise of one pod can be used to access AWS APIs with permissions intended for a different pod.

IRSA (the OIDC-based IAM role binding already partially scaffolded in `server/iam.tf`) is the correct solution. Each Kubernetes workload gets its own IAM role. The node role should have near-zero AWS permissions.

**Note:** The OIDC URL in `server/iam.tf:59` — `https://oidc.<cluster_name>.<region>.amazonaws.com` — is not a real OIDC issuer URL for RKE2. RKE2 generates its own JWKS endpoint; you need to either use `kube-oidc-proxy` or set `kube-apiserver-arg: ["service-account-issuer=https://..."]` in RKE2 config and host the discovery document in S3. This must be resolved before IRSA will work.

---

### P-004 — ~~`HIGH`~~ `RESOLVED` — EBS Volumes Encrypted at Rest

**Files:** `RKE-cluster/modules/ec2/main.tf`, `openvpn/module/main.tf`

**Resolved 2026-02-28:**

- **RKE nodes (server + agent):** `encrypted = false` replaced with `encrypted = var.ebs_encrypted` (default `true`). Added `ebs_encrypted` and `ebs_kms_key_id` variables to `RKE-cluster/modules/ec2/variables.tf`. When `ebs_kms_key_id` is provided the volume is encrypted with that CMK; otherwise the AWS-managed key (`aws/ebs`) is used.
- **OpenVPN:** Already had `encrypted = true`. Added `kms_key_id = var.kms_key_arn != "" ? var.kms_key_arn : null` to reuse the existing `kms_key_arn` variable — same CMK that protects the Secrets Manager secret can protect the volume.

Both modules default to encrypted with the AWS-managed key and require no extra configuration. Pass a CMK ARN for production to enable key rotation and audit trails.

---

### P-005 — ~~`HIGH`~~ `RESOLVED` — TLS Private Key Must Not Touch Disk in `/tmp`

**File:** `openvpn/ansible/openvpn-tls-sync.yml:97-116`

**Resolved 2026-03-03:** See SEC-004. The same fix applies to both dev and prod — `mktemp -d` under `/root/` with `trap EXIT` cleanup and `chmod 600` on all key files.

---

### P-006 — ~~`HIGH`~~ `RESOLVED` — Hardcoded Account ID and Region Must Be Parameterized

**File:** `RKE-cluster/modules/ec2/main.tf:276, 327, 339`

**Resolved 2026-03-03:**
- All hardcoded account IDs replaced with `data.aws_caller_identity.current.account_id`
- All hardcoded regions replaced with `data.aws_region.current.name`
- Role names parameterized via variables
- Git history scrubbed (see SEC-003)

---

### P-007 — ~~`HIGH`~~ `RESOLVED` — State Backend Security Controls

**File:** `s3backing/main.tf`

**Resolved 2026-02-28:** The following controls are now Terraform-managed:

| Control | Status |
|---|---|
| SSE-KMS with `aws/s3` | Was already present |
| DynamoDB SSE-KMS with `aws/dynamodb` | Was already present |
| `bucket_key_enabled = true` | Added — reduces KMS API calls/cost |
| Versioning enabled | Added |
| Noncurrent version expiration — 90 days | Added — current version kept forever, old versions expire after 90 days |
| Public access block (all four settings) | Added |
| Dedicated access log bucket with 18-month expiry | Added |
| S3 access logging → `mikey-com-terraformstate-access-logs/terraform-state/` | Added |
| Bucket policy: Deny non-`terraform-execute` access | Added |
| Bucket policy: Deny non-TLS (`aws:SecureTransport = false`) | Added |

**Not implemented:** MFA Delete — requires root credentials and manual `aws s3api` call; cannot be managed by Terraform without root access. Not appropriate for a dev environment and deferred for production.

---

### P-008 — `ACCEPTED` — SSH Access Controls

**Files:** `openvpn/module/main.tf:87-93`, `RKE-cluster/modules/ec2/main.tf:6-11`

**Risk accepted.** SSH is not open from the internet:

- **RKE nodes** — private subnets, VPN required to reach port 22. VPC CIDR only.
- **OpenVPN server** — port 22 locked to admin IP only (`admin_cidr`).

SSH keys are managed in Secrets Manager, not stored on disk. Single-operator environment. Risk is accepted for both dev and production.

---

### P-009 — ~~`MEDIUM`~~ `RESOLVED` — All Downloads Pinned and Verified

**Files:** `openvpn/ansible/openvpn-tls-sync.yml`, `RKE-cluster/modules/server/templates/ansible-playbook.yml.tftpl`, `RKE-cluster/modules/agent/templates/ansible-playbook.yml.tftpl`

**Resolved 2026-02-28:**

All downloaded tools are now pinned to explicit versions. A CVE in a pinned version forces an explicit version bump and redeploy — you cannot accidentally sit on a 3-year-old binary.

| Tool | Location | How pinned |
|---|---|---|
| AWS CLI | server + agent tftpl | `awscli_version` Terraform variable (default `2.15.30`); versioned URL `awscli-exe-linux-x86_64-${version}.zip` |
| AWS CLI | openvpn-tls-sync.yml | `awscli_version` Ansible var (default `2.15.30`); same versioned URL |
| RKE2 | server + agent tftpl | `rke2_version` Terraform variable (default `v1.28.8+rke2r1`); `INSTALL_RKE2_VERSION` env var passed to installer |
| Docker Compose | — | Removed — was never used after install; RKE2 uses containerd directly |

Bumping a version: update the variable in `RKE-cluster/dev-cluster/RKE/terraform.tfvars` (or module default) and run `terraform apply` — the `null_resource` trigger includes `awscli_version` and `rke2_version` so a version change forces reprovisioning.

**Ongoing operational requirement — version audit:**

Ansible playbooks and tftpl templates are not Dockerfiles or Packer scripts — they don't get the same automatic scrutiny in code review. Pinned versions here will go stale silently unless actively reviewed.

Locations to audit on each deployment or quarterly:

| File | What to check |
|---|---|
| `RKE-cluster/modules/server/variables.tf` | `awscli_version`, `rke2_version` defaults |
| `RKE-cluster/modules/agent/variables.tf` | same |
| `openvpn/ansible/openvpn-tls-sync.yml` | `awscli_version` var |

Version sources:
- AWS CLI: https://raw.githubusercontent.com/aws/aws-cli/v2/CHANGELOG.rst
- RKE2: https://github.com/rancher/rke2/releases

---

### P-010 — `INFO (dev)` / `MEDIUM (prod)` — `allow_overwrite = true` on Route53 Record

**File:** `openvpn/module/main.tf:182`

```hcl
allow_overwrite = true
```

**Dev:** Acceptable — the VPN server is destroyed and recreated frequently, and the Elastic IP may change between deployments. `allow_overwrite` prevents a spurious error if a stale record exists from a previous run.

**Prod:** The Elastic IP is permanent and not expected to change. `allow_overwrite = true` provides no benefit and silently overwrites a live record if there is a deployment error or partial state. Remove it for production — let Terraform fail explicitly if the record already exists, which is the correct signal that something unexpected happened.

---

### P-011 — ~~`MEDIUM`~~ `RESOLVED` — Secrets Manager Recovery Window Parameterized

**Files:** `openvpn/devvpn/sshkey.tf`, `RKE-cluster/dev-cluster/ec2/sshkey.tf`, `RKE-cluster/dev-cluster/RKE/main.tf`, `modules/irsa/main.tf`

**Resolved 2026-03-03:** See SEC-007. Set `secret_recovery_window_days = 30` in production `terraform.tfvars`.

---

### P-012 — `MEDIUM` — CronJob Publisher Uses Node IAM Role, Not IRSA

**File:** `deployments/modules/tls-issue/main.tf:168-237`

The cert-publisher CronJob has a properly scoped Kubernetes RBAC Role (read-only on the TLS secret in `openvpn-certs` namespace), but it calls the AWS Secrets Manager API using the EC2 node's instance profile. For production, give the `openvpn-cert-publisher` ServiceAccount a dedicated IAM role via IRSA, scoped to `secretsmanager:PutSecretValue` on `arn:aws:secretsmanager:*:*:secret:openvpn/*` only. Remove the write permission from the node role entirely.

---

### P-013 — ~~`MEDIUM`~~ `RESOLVED` — VPC Flow Log Alerting Added

**File:** `vpc/modules/vpc/mainf.tf`

**Resolved 2026-02-28:** Three CloudWatch metric filters and alarms added to the VPC module. All resources (SNS topic, metric filters, alarms) are defined in the VPC module and are destroyed with the VPC — no orphaned alerting infrastructure.

| Alarm | Pattern | Threshold | Rationale |
|---|---|---|---|
| `{name}-ssh-traffic` | Port 22, any source | ≥1 in 5 min | RKE nodes are private-subnet only, OpenVPN port 22 is admin-IP locked — any SSH hit is unexpected |
| `{name}-rejected-traffic` | `action=REJECT` | ≥100 in 5 min | Spike in rejections = port scan or misconfigured SG |
| `{name}-large-transfer` | `bytes>10MB` per flow | ≥5 in 5 min | Potential data exfiltration from RKE nodes |

Alert email configured in `vpc/dev/terraform.tfvars` (`alert_email`). SNS email subscription requires confirmation click after first `terraform apply`.

---

### P-014 — `LOW` — `imagePullPolicy: IfNotPresent` on Cert Publisher

**File:** `deployments/modules/tls-issue/main.tf:197`

```hcl
imagePullPolicy = "IfNotPresent"
```

Fine for dev. For production, use `Always` on any security-sensitive container (the cert publisher handles private keys and AWS credentials). This ensures the image is never stale and that a compromised cached image layer is not silently used.

---

### P-015 — ~~`LOW`~~ `RESOLVED` — `null_resource` Provisioner Errors Now Propagate

**File:** `openvpn/devvpn/main.tf:115`

**Resolved 2026-03-03:** See SEC-009. `|| true` removed.

---

### P-016 — `MEDIUM (dev) / HIGH (prod)` — OpenVPN Shares a Subnet With Other Workloads; No Dedicated NACL

**Files:** `VPC/dev/main.tf`, `openvpn/module/main.tf`

The OpenVPN Access Server is launched into one of the shared public subnets (`10.8.0.0/24`, `10.8.64.0/24`, `10.8.128.0/24`). Those subnets are also used by NAT gateways and any other public-facing resource. Because Network ACLs are a subnet-level control, a NACL tight enough for OpenVPN (UDP/1194, TCP/443, TCP/943, TCP/22 from `admin_cidr`) cannot be applied without breaking the other tenants of that subnet. The only defense today is the EC2 instance's security group.

Security groups are stateful and per-ENI, which is good, but they are also the single layer of network enforcement in front of the VPN concentrator — the one box that, if compromised, provides attacker pivot into the entire VPC. A misconfigured or accidentally-widened SG rule (a common human-error class) has no second line of defense.

**Fix for production:**
1. Add a dedicated `/28` public subnet per AZ intended only for the OpenVPN ENI(s) — e.g., `10.8.1.0/28`, `10.8.65.0/28`, `10.8.129.0/28`. A `/28` gives five usable addresses, which is sufficient for an HA pair or a single instance with spare capacity.
2. Attach a restrictive Network ACL to the OpenVPN subnet:
   - **Ingress allow:** UDP/1194 from `0.0.0.0/0`, TCP/443 from `0.0.0.0/0`, TCP/943 from `admin_cidr`, TCP/22 from `admin_cidr`, ephemeral return traffic from the VPC CIDR.
   - **Ingress deny:** everything else (implicit).
   - **Egress allow:** return traffic on ephemeral ports, plus the specific outbound destinations the instance legitimately needs (Secrets Manager/KMS endpoints, Route53, package mirrors, S3 for the TLS sync).
3. Keep the existing security group as the stateful inner layer. NACL + SG gives defense in depth: an SG mistake is contained by the NACL, and vice versa.

**Dev environment impact:** `MEDIUM` — SG is currently the only enforcement layer, but the blast radius from an SG mistake in dev is limited to a single-user environment.

**Production impact:** `HIGH` — the VPN is the perimeter; it deserves its own broadcast domain and its own subnet-level rule set. Carving out the subnet is cheap (no extra cost, ~20 lines of Terraform) and is a precondition for P-017.

---

### P-017 — `MEDIUM (dev) / HIGH (prod)` — No Egress Filtering; Consider AWS Network Firewall or a Third-Party Firewall

**Files:** `VPC/dev/main.tf`, all module SGs

Outbound traffic from the VPC is currently unrestricted. NAT gateways forward anything a node wants to send, and security group egress rules are mostly `0.0.0.0/0`. This means:
- A compromised RKE node or pod can exfiltrate data to any host on the internet.
- A compromised OpenVPN server can beacon to C2 infrastructure with no detection or block.
- Supply-chain pulls (package mirrors, container registries, GitHub) cannot be distinguished from arbitrary attacker-controlled destinations in flow logs alone — the VPC sees them all as "egress to the internet."

VPC Flow Log alarms (P-013) catch *volume* anomalies but not *destination* anomalies. A slow, low-volume exfiltration to a novel host will not trip the thresholds.

**Options, in rough order of cost/complexity:**

| Option | Cost | What it gets you | Tradeoffs |
|---|---|---|---|
| **VPC Endpoints for AWS services** (already partially in place per commit `09394a8`) | Low — endpoint hourly + data | Removes AWS API traffic from the NAT path entirely; SGs on endpoints enforce which principals can reach which services | Only covers AWS; doesn't stop egress to non-AWS destinations |
| **Restrictive egress SG rules + explicit allow-list of CIDRs** | Free | Blocks most egress without new infrastructure | Allow-list is brittle — package mirror IPs change constantly; hard to maintain |
| **AWS Network Firewall** | ~$0.395/hr per endpoint + data processing | Stateful L3/L4 + domain-name (SNI/HTTP Host) filtering via Suricata rules; central policy management; integrates with AWS Firewall Manager | ~$290/mo baseline per AZ; operationally simpler than self-managed; cannot do deep TLS inspection without MITM cert |
| **Third-party NGFW (Palo Alto VM-Series, Fortinet, Check Point)** | EC2 + licensing, typically $500–$2000+/mo | Full L7 inspection, URL categories, TLS decryption, IPS signatures, threat intel feeds | Most expensive; requires HA design, licensing management, separate operator skill set |
| **Squid/proxy pattern on a hardened egress host** | EC2 + minimal ops | Domain-name allow-listing for HTTP/HTTPS; cheap | Doesn't cover non-HTTP protocols; another box to maintain |

**Recommendation for this project:**
- **Dev:** Accept current state. Continue expanding VPC endpoint coverage where it pays off for NAT bandwidth savings (already the path taken in commit `09394a8`).
- **Production:** AWS Network Firewall is the right first step. It gives you domain-based egress filtering (critical for catching DNS-over-HTTPS exfiltration and C2 beacons to unknown domains), it's managed by AWS so it fits the same IaC pattern as the rest of the stack, and the ~$290/mo per AZ cost is justified for the blast-radius reduction. Reserve third-party NGFW for workloads that actually need L7 IPS or TLS inspection — most VPCs do not.
- Pair any egress firewall with **explicit egress SG rules** on the OpenVPN and RKE node SGs. Defense in depth: firewall catches what the SG misses, and SG catches what the firewall misses.

**Dev environment impact:** `MEDIUM` — unrestricted egress is a risk but blast radius is contained by the single-operator, short-lived nature.

**Production impact:** `HIGH` — no egress control is a gap in any modern security architecture. Required for most compliance frameworks (PCI-DSS 1.3, NIST 800-53 SC-7, SOC 2 CC6.6).

---

## Part 3 — Developer Tools & Unsafe Patterns

**Date:** 2026-02-28  
**Scope:** Ansible playbooks, userdata scripts, Kubernetes manifests, module defaults

---

### DEV-001 — `CRITICAL` — `upgrade: dist` Runs on Every Provision

**Files:** `RKE-cluster/modules/server/templates/ansible-playbook.yml.tftpl:22`, `RKE-cluster/modules/agent/templates/ansible-playbook.yml.tftpl:19`

`apt upgrade: dist` is the first task in both playbooks. This runs on first boot and on every Terraform re-provision, silently upgrading kernel, glibc, OpenSSL, and containerd to whatever Ubuntu's repos currently have. A kernel or container runtime upgrade without a reboot leaves the node in a split-brain state. A compromised upstream package silently replaces a production binary.

**Fix:** Change to `upgrade: safe` (security patches only, no kernel/major dependency changes) or remove the upgrade task and manage patching through a separate scheduled maintenance window.

---

### DEV-002 — `CRITICAL` — RKE2 Installer Checksum Fallback Is Self-Referential

**Files:** `RKE-cluster/modules/server/templates/ansible-playbook.yml.tftpl:121-124`, `RKE-cluster/modules/agent/templates/ansible-playbook.yml.tftpl:61-64`

The checksum fallback fetches the installer from `raw.githubusercontent.com/rancher/rke2/master/install.sh` and computes its hash on the fly. This is the same source as the installer — verifying a file against a hash derived from itself provides zero supply chain protection. `master` is also the tip of the development branch, not a pinned release.

**Fix:** Remove the fallback entirely. The primary `https://get.rke2.io.sha256` URL is reliable. Optionally pin the expected SHA256 as a Terraform variable alongside `rke2_version` and verify against that hardcoded value.

---

### DEV-003 — `CRITICAL` — IRSA Webhook Deployed from `?ref=master` with `|| true`

**File:** `RKE-cluster/modules/server/templates/ansible-playbook.yml.tftpl:379,382`

The AWS Pod Identity Webhook is applied with `kubectl apply -k "github.com/aws/amazon-eks-pod-identity-webhook/deploy?ref=master"`. Two compounding problems:
1. `?ref=master` fetches unreviewed tip-of-branch commits into a cluster-level admission webhook that controls IRSA credential injection.
2. Both the `apply` and `wait` are followed by `|| true` — a broken webhook is silently accepted, and pods may fall back to node-level IAM.

**Fix:** Pin to a specific release tag (e.g. `?ref=v0.5.4`). Remove `|| true` from the `wait` step — let it fail loudly.

---

### DEV-004 — `HIGH` — `write-kubeconfig-mode: "0644"` — Cluster-Admin Credential World-Readable

**File:** `RKE-cluster/modules/server/templates/ansible-playbook.yml.tftpl:192`

`write-kubeconfig-mode: "0644"` makes `/etc/rancher/rke2/rke2.yaml` (which contains a cluster-admin credential) readable by all users on the node. Any process running as a non-root user, including a container that has escaped its namespace, can read it and gain full cluster-admin access. The playbook also symlinks it to `~/.kube/config`.

**Fix:** Remove `write-kubeconfig-mode` entirely (default is `0600`). If the `ubuntu` user needs kubectl access, add them to the `rke2` group or use a purpose-scoped kubeconfig.

---

### DEV-005 — `HIGH` — `ssh_cidr_blocks` Module Default Is `0.0.0.0/0`

**Files:** `RKE-cluster/modules/server/variables.tf`, `RKE-cluster/modules/agent/variables.tf`

The `ssh_cidr_blocks` variable defaults to `["0.0.0.0/0"]`. Any caller that omits this variable gets SSH open to the internet. The current dev deployment places nodes in private subnets so this is not directly exploitable now, but any future public-subnet deployment would be immediately exposed. Module defaults should be the most restrictive option.

**Fix:** Change default to `[]` and require callers to explicitly set the value.

---

### DEV-006 — `HIGH` — Userdata Package Installs Are Unpinned with `|| true`

**File:** `RKE-cluster/modules/ec2/config/userdata.sh:6,12`

`apt-get install` installs `git`, `ansible`, `python3-boto3`, `python3-botocore`, and `snapd` with no version pins and `|| true` masking any failure. A malicious or broken package silently alters the Ansible binary that then configures the entire node. `set -e` at the top of the script is negated by `|| true`.

**Fix:** Pin critical packages (especially `ansible`). Remove `|| true` from install steps.

---

### DEV-007 — `HIGH` — OpenVPN Userdata Uses IMDSv1

**File:** `openvpn/module/userdata.sh:20,22`

Two informational `echo` lines call the IMDSv1 endpoint (`http://169.254.169.254/latest/meta-data/public-ipv4`) without a token header. The calls are for display only and have no functional value post-boot. They also establish an IMDSv1 usage pattern in code that is copied.

**Fix:** Remove the lines entirely — the public IP is already available in Terraform outputs. If kept, use IMDSv2 with a token header.

---

### DEV-008 — `HIGH` — CronJob Uses `:latest` Image Tag

**File:** `deployments/modules/tls-issue/cert-manager/cronjob-publish-to-secretsmanager.yaml:26`

The cert-publisher CronJob image is tagged `:latest`. Between CronJob runs the image can change without any deployment action. This container handles TLS private keys and AWS credentials — a compromised registry push would be silently executed on the next scheduled run.

**Fix:** Pin to a specific digest (`@sha256:...`) or a semver tag. Set `imagePullPolicy: Always` (already noted as P-014).

---

### DEV-009 — `MEDIUM` — `ignore_errors: yes` on IRSA Security Tasks

**File:** `RKE-cluster/modules/server/templates/ansible-playbook.yml.tftpl:294,314,389,404`

`ignore_errors: yes` on IRSA signing key download, webhook installation, and service account creation means a broken IRSA setup is silently accepted. The cluster appears healthy but pods fall back to node-level IAM credentials, granting them the full node role.

**Fix:** Use `failed_when` with idempotency checks (e.g. `when: result.rc != 0 and 'already exists' not in result.stderr`). Reserve `ignore_errors: yes` for genuine probe tasks only.

---

### DEV-010 — `MEDIUM` — Unused Packages Installed on Agent Nodes (`wget`, `jq`)

**File:** `RKE-cluster/modules/agent/templates/ansible-playbook.yml.tftpl:26-27`

`wget` and `jq` are installed on every agent node but never called in the playbook. Unnecessary tools expand the post-exploitation toolkit. This is the same pattern as the `docker-compose` issue already resolved.

**Fix:** Remove both from the prerequisites list.

---

### DEV-011 — `MEDIUM` — `git` Installed on Server Nodes Without Active Use

**File:** `RKE-cluster/modules/server/templates/ansible-playbook.yml.tftpl:30`

`git` is installed but was only used in a commented-out repo-clone section of `userdata.sh`. The playbook is now entirely template-driven via Terraform — `git` is not needed. On a cluster node, `git` provides HTTPS-based data exfiltration capability that egress rules controlling non-standard ports cannot block.

**Fix:** Remove from the package list.

---

### DEV-012 — `HIGH` — Docker Hub Used as Default Container Registry

**Files:** `RKE-cluster/modules/server/templates/ansible-playbook.yml.tftpl`, `RKE-cluster/modules/agent/templates/ansible-playbook.yml.tftpl`, `deployments/rke-apps/1-infrastructure/main.tf`, `deployments/modules/nginx-sample/main.tf`

RKE2 was not configured with `system-default-registry`, causing kubelet to pull the `pause` sandbox image from `index.docker.io`. Docker Hub applies aggressive rate limits (100 pulls/6 hr for unauthenticated, 200 for free accounts) on fresh nodes with no cached images. This caused etcd to never bootstrap because the pod sandbox container could never start. The Helm charts for Traefik, cert-manager, and external-dns similarly defaulted to Docker Hub (`docker.io/traefik`), `quay.io/jetstack`, and `registry.k8s.io` respectively.

**Rule:** On AWS infrastructure, always prefer `public.ecr.aws` — no rate limits, no auth, lower latency via AWS backbone.

**Fix applied:**
- Added `system-default-registry: "public.ecr.aws"` to RKE2 `config.yaml` for all server and agent nodes
- Added `image.registry: public.ecr.aws` overrides to Traefik, cert-manager, and external-dns Helm releases
- Changed `nginx:1.25-alpine` sample app to `public.ecr.aws/nginx/nginx:1.25-alpine`

---

## Part 4 — Architectural Decisions and Known Design Deviations

These are structural choices made during initial setup that are documented here for transparency. They are not bugs or oversights in the current code — they are intentional decisions with known tradeoffs.

---

### ARCH-001 — `HIGH (prod)` — Org Management Account is Also the Operator Account

**Accounts affected:** `990880295272` (org management account)

**What happened:** The AWS Organization was created from the same account where the operator's IAM user (`mpechner`) lives. This means `990880295272` is simultaneously:
- The AWS Organizations management account (controls SCPs, billing, account creation)
- The account where human IAM user credentials live
- The account where `terraform-execute` for org-level Terraform runs

**What AWS recommends:** The management account should be a dedicated, minimal-use account — no IAM users, no workloads, no day-to-day access. Human access to AWS should go through IAM Identity Center (SSO) from a separate identity account, with the management account used only for org-level operations via automation.

**Why it happened:** AWS Organizations is created from your first/existing account. When you create your first account and then create an org, that account becomes the permanent management account. The org management account **cannot be changed** after creation — AWS does not provide a migration path.

**Fixing it properly** requires:
1. Creating a new, empty AWS account
2. Creating a new Organization from that account
3. Inviting the existing accounts (dev, prod, network, mgmt) into the new org
4. Re-applying SCPs and account structure from the new management account
5. Decommissioning the old org

This is substantial work and outside the scope of this learning-reference repo.

**Mitigations in place:**
- The `990880295272` account is not used for workloads — all actual infrastructure lives in dev/prod/network/mgmt member accounts
- `terraform-execute` in `990880295272` has `AdministratorAccess` but is only assumed by the org-level Terraform — not by workload deployments
- IMDSv2 enforced on all EC2 instances in member accounts
- SCP restricts member accounts to approved regions only

**For production:** Either accept this with documented risk (reasonable for small teams), or restructure with a dedicated management account. If restructuring, see AWS documentation on [migrating accounts between organizations](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_accounts_invites.html).

**Risk accepted for this repo:** `ACCEPTED` — learning reference environment, single operator, org management account holds no workloads.

---

## Summary Table

| ID | Severity | Area | Short Description |
|----|----------|------|-------------------|
| SEC-001 | LOW (dev) / CRITICAL (prod) | Secrets | SSH private keys in Terraform state — low risk single-user/short-lived, critical for team/prod |
| SEC-002 | ~~CRITICAL~~ MEDIUM (dev) / HIGH (prod) | IAM | Node secret read scoped to openvpn/* and rke* prefixes; IRSA needed for full fix |
| SEC-003 | ~~HIGH~~ RESOLVED | Secrets | Account IDs scrubbed from code and git history (2026-03-03) |
| SEC-004 | ~~HIGH~~ RESOLVED | Crypto | TLS key now written to chmod 700 dir under /root with trap EXIT cleanup (2026-03-03) |
| SEC-005 | ~~HIGH~~ RESOLVED | IAM | Wildcard fallback removed; validation block enforces non-empty zone IDs (2026-03-03) |
| SEC-006 | ~~MEDIUM~~ RESOLVED | Supply Chain | All downloads verified: AWS CLI sha256, RKE2 installer sha256, Docker Compose sha256 (2026-03-03) |
| SEC-007 | INFO (dev) / MEDIUM (prod) | Ops | `recovery_window_in_days` now a variable; default 0 for dev, set 30 for prod in tfvars |
| SEC-008 | MEDIUM | Network | Admin IP detection via third-party service, no validation |
| SEC-009 | ~~LOW~~ RESOLVED | Ops | `|| true` removed; Ansible failures now fail terraform apply (2026-03-03) |
| SEC-010 | LOW (dev) / HIGH (prod) | Network | TRACE method enabled; AWS WAF required for production |
| P-001 | ~~CRITICAL~~ RESOLVED (dev) / CRITICAL (prod without rotation procedure) | Secrets | tls_private_key removed; keys generated by scripts, public key only read by Terraform; rotation requires Ansible playbook for running instances |
| P-002 | ~~CRITICAL~~ RESOLVED | IAM | Secrets Manager + Route53 scoped (SEC-002/005); KMS locked to ViaService + CMK var (2026-02-28) |
| P-003 | CRITICAL (prod) | IAM | IRSA module scaffolded; OIDC issuer URL and JWKS generation need wiring for prod |
| P-004 | ~~HIGH~~ RESOLVED | Storage | EBS encrypted=true on all nodes; aws/ebs default key explicit; CMK variable available (2026-02-28) |
| P-005 | ~~HIGH~~ RESOLVED | Crypto | TLS private key /tmp issue fixed (see SEC-004) |
| P-006 | ~~HIGH~~ RESOLVED | Config | Account ID and region parameterized; git history scrubbed (2026-03-03) |
| P-007 | ~~HIGH~~ RESOLVED | State | Versioning, 90-day noncurrent lifecycle, public access block, access logging, deny bucket policy (2026-02-28) |
| P-008 | ACCEPTED | Network | SSH not internet-exposed; keys in Secrets Manager; risk accepted |
| P-009 | ~~MEDIUM~~ RESOLVED | Supply Chain | AWS CLI + RKE2 pinned to explicit versions; quarterly audit checklist added (2026-02-28) |
| P-010 | INFO (dev) / MEDIUM (prod) | DNS | `allow_overwrite` fine for dev; remove for prod |
| P-011 | ~~MEDIUM~~ RESOLVED | Secrets | `secret_recovery_window_days` variable added; set to 30 in prod tfvars (2026-03-03) |
| P-012 | MEDIUM (prod) | IAM | IRSA role for cert-publisher needed; node write permission acceptable for dev |
| P-013 | ~~MEDIUM~~ RESOLVED | Monitoring | SSH, reject spike, large-transfer alarms + SNS added to VPC module (2026-02-28) |
| P-014 | LOW (prod) | K8s | Use `imagePullPolicy: Always` on cert publisher for prod |
| P-015 | ~~LOW~~ RESOLVED | Ops | `|| true` removed from provisioner (2026-03-03) |
| P-016 | MEDIUM (dev) / HIGH (prod) | Network | OpenVPN shares a subnet with other workloads; dedicated subnet + NACL needed for subnet-level defense in depth |
| P-017 | MEDIUM (dev) / HIGH (prod) | Network | No egress filtering; evaluate AWS Network Firewall or a third-party NGFW for prod |
| DEV-001 | CRITICAL | Supply Chain | `upgrade: dist` on every provision — uncontrolled package upgrades on running nodes |
| DEV-002 | CRITICAL | Supply Chain | RKE2 installer checksum fallback is self-referential — provides no protection |
| DEV-003 | CRITICAL | Supply Chain | IRSA webhook deployed from `?ref=master` + `\|\| true` masking failure |
| DEV-004 | HIGH | Auth | `write-kubeconfig-mode: 0644` — cluster-admin credential world-readable on node |
| DEV-005 | HIGH | Network | `ssh_cidr_blocks` module default is `0.0.0.0/0` |
| DEV-006 | HIGH | Supply Chain | Userdata apt installs unpinned + `\|\| true` masking failures |
| DEV-007 | HIGH | Secrets | OpenVPN userdata uses IMDSv1 curl calls |
| DEV-008 | HIGH | Supply Chain | CronJob uses `:latest` image tag on privileged cert-publisher |
| DEV-009 | MEDIUM | Ops | `ignore_errors: yes` on IRSA webhook and signing key tasks |
| DEV-010 | MEDIUM | Attack Surface | `wget` + `jq` installed on agent nodes but never used |
| DEV-011 | MEDIUM | Attack Surface | `git` installed on server nodes — no active use case |
| DEV-012 | ~~HIGH~~ RESOLVED | Supply Chain | Docker Hub as default registry — causes rate-limit failures; replaced with `public.ecr.aws` (2026-03-04) |
| ARCH-001 | HIGH (prod) / ACCEPTED (dev) | Architecture | Org management account is also the operator account — cannot be changed post-creation; mitigated by no workloads in mgmt account |

---

## Prioritized Action List

**Dev environment — reasonable issues resolved. New findings from Part 3 pending.**

**Before production deployment:**
1. P-001 — Remove `tls_private_key` from Terraform state; use `create-*-ssh-key.sh` scripts exclusively
2. DEV-001 — Change `upgrade: dist` to `upgrade: safe` in server + agent playbooks
3. DEV-002 — Remove self-referential RKE2 checksum fallback
4. DEV-003 — Pin IRSA webhook to a release tag; remove `|| true` from wait step
5. DEV-004 — Remove `write-kubeconfig-mode: "0644"` from RKE2 config
6. DEV-005 — Change `ssh_cidr_blocks` module default from `0.0.0.0/0` to `[]`
7. DEV-006 — Pin ansible package version in userdata; remove `|| true` from install steps
8. DEV-007 — Remove IMDSv1 curl calls from OpenVPN userdata
9. DEV-008 — Pin cert-publisher CronJob to digest or semver tag
10. DEV-009 — Replace `ignore_errors: yes` with `failed_when` on IRSA tasks
11. DEV-010 — Remove `wget` + `jq` from agent node prerequisites
12. DEV-011 — Remove `git` from server node prerequisites
13. P-003/P-012 — Wire IRSA: fix JWKS generation, set `service-account-issuer` in RKE2 config, create cert-publisher IRSA role
14. P-010 — Remove `allow_overwrite` from Route53 record
15. P-014 — Set `imagePullPolicy: Always` on cert-publisher CronJob
16. SEC-007 — Set `secret_recovery_window_days = 30` in prod tfvars
17. P-016 — Carve out dedicated `/28` OpenVPN subnet per AZ with restrictive NACL; keep SG as inner layer
18. P-017 — Deploy AWS Network Firewall (or equivalent) for egress filtering; pair with explicit egress SG rules
19. **SEC-010 — Implement AWS WAF WebACL on internal NLB to block TRACE/OPTIONS methods**
