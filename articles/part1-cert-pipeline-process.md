# Your Kubernetes Cluster Already Has a Certificate Authority — Use It for Everything

**Part 1: Building the pipeline — how to use cert-manager to issue and deliver Let's Encrypt TLS certificates to services *outside* your cluster**

*Last verified: April 2026.*


## An Underused Pattern

Your Kubernetes cluster has cert-manager. It quietly renews TLS certs for everything in the cluster. Your OpenVPN server, sitting on an EC2 instance outside the cluster, has a TLS cert that's about to expire — again — and with certificate lifetimes trending shorter every year, nobody on the team remembers whose turn it is to renew it.

Here's the thing: cert-manager can issue that cert too. It can issue certs for *anything* you own a DNS name for, whether it runs in Kubernetes or not. Most teams don't know this.

It's not just VPN servers. Legacy applications on standalone EC2 instances. Third-party appliances that need TLS but can't run cert-manager themselves. Load balancer frontends that aren't managed by Kubernetes. These services all need TLS certificates, and most teams manage them separately — manual renewal, cron scripts hitting Let's Encrypt directly, or expensive wildcard certs.

The mechanism: **cert-manager with DNS-01 validation has zero coupling to where the cert will actually be used.** All it needs is the ability to create a DNS TXT record in your hosted zone. The certificate itself can go anywhere.

The missing piece is a **delivery mechanism** — a way to get the certificate from the Kubernetes Secret where cert-manager stores it to the external service that needs it. That's what this article builds: a reusable pipeline using AWS Secrets Manager as the intermediary.


## The Architecture: Issue, Publish, Consume

The pipeline has three stages that are cleanly decoupled from each other:

1. **Issue** — cert-manager obtains and renews the certificate via DNS-01 challenge, stores it as a Kubernetes Secret
2. **Publish** — a CronJob reads the Secret and writes it to AWS Secrets Manager (only when the cert changes)
3. **Consume** — a cron job on the external service pulls from Secrets Manager and installs the cert (only when it's new)

Each stage knows nothing about the others. The Kubernetes side doesn't know or care what consumes the secret. The external service doesn't know or care how the cert was issued. Secrets Manager is the contract boundary.

![Architecture diagram: three-stage certificate pipeline — Issue (cert-manager in K8s), Publish (CronJob to Secrets Manager), Consume (external services pull and install)](https://raw.githubusercontent.com/mpechner/iac-aws-org-k8s/main/articles/images/cert-pipeline-architecture.png)

**Why this decoupling matters:**

- **One publisher, many consumers.** You write the publish side once. Each external service only needs a small consumer script tailored to how *it* installs certs.
- **The publisher is reusable.** The same container image, CronJob template, and RBAC pattern work for any certificate. Only the environment variables change.
- **Secrets Manager is the right abstraction.** It handles encryption at rest, access control via IAM, audit logging via CloudTrail, and versioning. You don't have to build any of that.

The rest of this article walks through a complete implementation using **OpenVPN Access Server** as the external service. But the pattern applies to anything — an SMTP gateway, a standalone database proxy, a network appliance, a Jenkins server. Anywhere you'd otherwise manually install a cert.

> **Live example:** The complete implementation is at [github.com/mpechner/iac-aws-org-k8s](https://github.com/mpechner/iac-aws-org-k8s) — a production-style AWS + RKE2 Kubernetes environment with full Terraform IaC.


## The Concrete Example: OpenVPN Access Server

My OpenVPN Access Server runs on an EC2 instance in a public subnet. It had a static TLS certificate that I renewed annually. The cluster already ran cert-manager for Traefik ingress, Rancher, and sample apps. The question was simple: why maintain a separate cert lifecycle for the VPN?

Here's the specific setup:

![Setup: RKE2 + cert-manager + Route53 + Secrets Manager; OpenVPN Access Server on EC2; publish every 6h, consume every 30 min in the midnight–3am window.](https://raw.githubusercontent.com/mpechner/iac-aws-org-k8s/main/articles/images/part1-table-setup.png)


## The Kubernetes Side — Issue and Publish

> **In the repo:** The entire publish side is a single Terraform module at [`deployments/modules/tls-issue/`](https://github.com/mpechner/iac-aws-org-k8s/tree/main/deployments/modules/tls-issue). It's called from [`deployments/rke-apps/2-applications/openvpn-cert.tf`](https://github.com/mpechner/iac-aws-org-k8s/blob/main/deployments/rke-apps/2-applications/openvpn-cert.tf). The standalone YAML equivalents (for `kubectl apply` without Terraform) are in the `cert-manager/` subdirectory.

This half is completely reusable across services. Nothing here is OpenVPN-specific.

### Step 1: Create a Dedicated ClusterIssuer

You *could* reuse your existing ClusterIssuer, but I recommend a dedicated one per hosted zone. This follows least-privilege: each issuer can only modify DNS records in its own zone.

```hcl
resource "kubernetes_manifest" "service_clusterissuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-myservice-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = "you@example.com"
        privateKeySecretRef = {
          name = "letsencrypt-myservice-prod"
        }
        solvers = [
          {
            dns01 = {
              route53 = {
                region       = "us-west-2"
                hostedZoneID = "ZXXXXXXXXXXXXX"
              }
            }
          }
        ]
      }
    }
  }
}
```

**Key decision: DNS-01 vs HTTP-01.** DNS-01 is the right choice for external services because:

- The target service doesn't need to serve the ACME challenge — cert-manager handles it entirely via DNS TXT records
- Works for services in private subnets, behind firewalls, or on separate networks
- Works for wildcard certificates
- The only requirement is that cert-manager can modify your DNS zone (Route53 in this case)

**Gotcha #1: IAM credentials for cert-manager.** If your cluster nodes run on EC2, cert-manager can use the **node's IAM instance profile** for Route53 access. No static access keys, no Kubernetes Secrets with AWS credentials to rotate. The node IAM role needs `route53:ChangeResourceRecordSets` scoped to your hosted zone, plus `ListHostedZonesByName` and `GetChange` on `*` (AWS requires these to be unscoped).

### Step 2: Create the Certificate Resource

```hcl
resource "kubernetes_manifest" "service_cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "myservice-tls"
      namespace = "myservice-certs"
    }
    spec = {
      secretName  = "myservice-tls"
      duration    = "2160h"   # 90 days
      renewBefore = "720h"    # renew at day 60 — 30 days of retry buffer
      commonName  = "myservice.dev.example.com"
      dnsNames    = ["myservice.dev.example.com"]
      issuerRef = {
        name  = "letsencrypt-myservice-prod"
        kind  = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  }
}
```

I use a dedicated namespace per service to keep RBAC boundaries clean — the publisher CronJob for this service can only read *this* secret.

**Gotcha #2: `renewBefore` math.** Let's Encrypt certs are 90 days. Setting `renewBefore: 720h` (30 days) means cert-manager starts trying to renew at day 60. If the DNS-01 challenge fails, cert-manager retries with exponential backoff. A 30-day window means even a week-long Route53 outage won't result in an expired certificate.

### Step 3: Build the Publisher Container

> **In the repo:** [`deployments/modules/tls-issue/publisher/`](https://github.com/mpechner/iac-aws-org-k8s/tree/main/deployments/modules/tls-issue/publisher) — contains the Python script, Dockerfile, requirements.txt, and a [README](https://github.com/mpechner/iac-aws-org-k8s/blob/main/deployments/modules/tls-issue/publisher/README.md) with IAM setup and build instructions.

The publisher is a small Python script (~200 lines) that reads `tls.crt` and `tls.key` from a volume mount, computes the SHA256 fingerprint of the leaf certificate, checks the existing fingerprint in Secrets Manager, and writes only if the fingerprint has changed.

```python
def main() -> int:
    fullchain_pem = load_pem(Path("/etc/tls/tls.crt"))
    privkey_pem   = load_pem(Path("/etc/tls/tls.key"))

    leaf_der    = get_leaf_der(fullchain_pem)
    fingerprint = fingerprint_sha256(leaf_der)

    _, chain_pem = split_fullchain(fullchain_pem)
    payload = {
        "fqdn":              fqdn,
        "fingerprint_sha256": fingerprint,
        "fullchain_pem":     fullchain_pem.decode("utf-8"),
        "privkey_pem":       privkey_pem.decode("utf-8"),
        "chain_pem":         chain_pem.decode("utf-8") if chain_pem else "",
    }

    client = boto3.client("secretsmanager", region_name=region)
    try:
        current = client.get_secret_value(SecretId=secret_name)
        existing_fp = json.loads(current["SecretString"]).get("fingerprint_sha256")
        if existing_fp == fingerprint:
            logger.info("Fingerprint unchanged — skipping update.")
            return 0
    except ClientError as e:
        if e.response["Error"]["Code"] == "ResourceNotFoundException":
            pass  # First run — will create

    client.put_secret_value(SecretId=secret_name, SecretString=json.dumps(payload))
    return 0
```

**Gotcha #3: Docker Hub rate limits.** Use `public.ecr.aws/docker/library/python:3.12-slim` instead of Docker Hub. Same image, no rate limits.

**This container image is fully reusable.** It's parameterized entirely through environment variables — nothing OpenVPN-specific. To publish a cert for a different service, just change the env vars.

### Step 4: Deploy the CronJob

The CronJob mounts the Kubernetes Secret directly at `/etc/tls` as a volume — no kubectl, no API server calls, no broad service account permissions. The RBAC for the `cert-publisher` ServiceAccount is scoped to `get` on a single named Secret. See the [full CronJob manifest in the repo](https://github.com/mpechner/iac-aws-org-k8s/blob/main/deployments/modules/tls-issue/main.tf).

### Step 5: IAM Permissions

> **In the repo:** The node IAM role is in [`RKE-cluster/modules/ec2/main.tf`](https://github.com/mpechner/iac-aws-org-k8s/blob/main/RKE-cluster/modules/ec2/main.tf).

The CronJob uses the EC2 node's instance profile. The node role needs Route53 permissions (for cert-manager DNS-01) and Secrets Manager write (for the publisher). No separate IAM users, no static access keys.

**Important caveat:** This node-role approach means *every pod on every node* inherits these permissions. For a dev environment, this is acceptable. For production, you must use IRSA to scope permissions to only the pods that need them. **Part 2 of this series covers this in depth.**


## The Consumer Side — Pull and Install

This is the service-specific half. The example below is for OpenVPN Access Server, but the pattern applies to anything.

### Consumer Patterns for Different Services

**Services you SSH into — consumer runs as system cron on the instance:**

- **OpenVPN Access Server** — install via `sacli ConfigPut`, restart with `sacli start` (web UI only, tunnels unaffected)
- **Nginx (standalone)** — write to `/etc/nginx/ssl/`, reload with `nginx -s reload`
- **HAProxy** — concatenate cert+key to a single PEM, reload with `systemctl reload haproxy`
- **PostgreSQL** — write to `ssl_cert_file` path, reload with `pg_ctl reload`

**AWS-managed services — consumer runs as a K8s CronJob or Lambda (just an API call, no server to SSH into):**

- **ALB/NLB** — `aws acm import-certificate`, update the listener; no restart, the listener picks up the new cert

**Think about your maintenance window.** Nginx and HAProxy can reload without dropping connections. OpenVPN's `sacli start` briefly interrupts the web UI but not VPN tunnels. Match your cron schedule to when a restart is safe — for OpenVPN, that meant restricting the sync to a midnight–3am window so the admin console blip goes unnoticed.

### The VPC Endpoint Gotcha

> **In the repo:** VPC endpoints in [`VPC/modules/vpc/mainf.tf`](https://github.com/mpechner/iac-aws-org-k8s/blob/main/VPC/modules/vpc/mainf.tf), SG rule in [`openvpn/devvpn/main.tf`](https://github.com/mpechner/iac-aws-org-k8s/blob/main/openvpn/devvpn/main.tf).

This applies to *any* external service in a public subnet that needs to reach Secrets Manager.

When `private_dns_enabled = true` on a VPC interface endpoint (the default), the hostname `secretsmanager.us-west-2.amazonaws.com` resolves to **private endpoint IPs** for every host in the VPC — including public subnets. If your endpoint SG only allows private subnet CIDRs, public-subnet hosts time out silently.

I implemented both fixes:

1. **SG rule** letting the OpenVPN SG reach the endpoint SG on 443 (keeps traffic on the AWS network).
2. **Explicit `--endpoint-url`** in the sync script as a fallback (bypasses VPC endpoint DNS entirely, goes over public internet with TLS + SigV4).

![Network diagram: VPC endpoint DNS gotcha — public subnet services resolve to private endpoint IPs, causing timeouts.](https://raw.githubusercontent.com/mpechner/iac-aws-org-k8s/main/articles/images/vpc-endpoint-dns-gotcha.png)

**Gotcha #4: VPC endpoints with private DNS.** This bites any service in a public subnet calling any AWS API for which you have an interface endpoint — not just Secrets Manager.

### Deploying the OpenVPN Consumer via Ansible

> **In the repo:** Playbook at [`openvpn/ansible/openvpn-tls-sync.yml`](https://github.com/mpechner/iac-aws-org-k8s/blob/main/openvpn/ansible/openvpn-tls-sync.yml), wrapper at [`openvpn/ansible/setup-tls-sync.sh`](https://github.com/mpechner/iac-aws-org-k8s/blob/main/openvpn/ansible/setup-tls-sync.sh).

The playbook installs AWS CLI v2 (pinned, checksum-verified), creates the sync script, and sets up a cron job (every 30 min, midnight–3am only). The sync script fetches from Secrets Manager, compares fingerprints, and installs via `sacli ConfigPut` only if the cert changed. Connected VPN tunnels are **not disrupted**.

**Gotcha #5: `sacli` vs file copy.** An earlier version (still in the repo as [`install-cert-via-ssh.sh`](https://github.com/mpechner/iac-aws-org-k8s/blob/main/openvpn/ansible/install-cert-via-ssh.sh)) copied PEM files directly. `sacli ConfigPut` is the proper method — it updates the internal database and handles the chain correctly.

**Gotcha #6: Ansible temp directory.** The `openvpnas` user has restricted home directory permissions. Fix: `ansible_remote_tmp: /tmp/.ansible-${USER}`. Note: this `/tmp` usage is only for Ansible's control files — the sync script never writes private keys to `/tmp`. Cert material goes to a root-owned secure temp directory (`mktemp -d /root/.openvpn-tls-sync-XXXXXX`, `chmod 700`) with `trap "rm -rf" EXIT` cleanup.


## The Shared Contract — Secret JSON Format

The publisher and consumer agree on a JSON schema:

```json
{
  "fqdn": "vpn.dev.example.com",
  "fingerprint_sha256": "a1b2c3d4e5f6...",
  "fullchain_pem": "-----BEGIN CERTIFICATE-----\n...",
  "privkey_pem": "-----BEGIN PRIVATE KEY-----\n...",
  "chain_pem": "-----BEGIN CERTIFICATE-----\n..."
}
```

The `fingerprint_sha256` is the idempotency key — the publisher skips writes and the consumer skips installs when it hasn't changed. Both cron jobs can run frequently without unnecessary API calls or service restarts.


## Deployment Runbook

> **In the repo:** Paths are relative to [github.com/mpechner/iac-aws-org-k8s](https://github.com/mpechner/iac-aws-org-k8s). The [README](https://github.com/mpechner/iac-aws-org-k8s#readme) has the full 12-step deployment covering VPC through applications. This is the cert-pipeline subset.

1. **Deploy VPC** with `enable_vpc_endpoints = true` (`VPC/dev`)
2. **Deploy OpenVPN** (`openvpn/devvpn`) — includes SG rule and IAM for Secrets Manager
3. **Deploy K8s nodes** (`RKE-cluster/dev-cluster/ec2`) — includes Route53 + Secrets Manager IAM
4. **Deploy RKE2** (`RKE-cluster/dev-cluster/RKE`) — requires VPN connection
5. **Build publisher image** (`deployments/rke-apps/2-applications/scripts` — `make`)
6. **Deploy cert pipeline** (`deployments/rke-apps/2-applications` — `terraform apply`)
7. **Run Ansible** (`openvpn/ansible` — `./setup-tls-sync.sh`) or let `null_resource` handle it
8. **Verify:** `kubectl get certificate`, trigger publisher manually, check Secrets Manager, trigger sync on OpenVPN, verify cert in browser


## Gotchas Summary

![Gotchas summary: cert-manager IAM, renewBefore window, Docker Hub rate limits, VPC endpoint private DNS, sacli vs file copy, Ansible temp directory — each with symptom and fix.](https://raw.githubusercontent.com/mpechner/iac-aws-org-k8s/main/articles/images/part1-table-gotchas.png)


## Cost

![Cost table: Secrets Manager ~$0.40/mo, VPC Endpoint ~$7.20/mo/AZ, ECR storage ~$0.008/mo, CronJob compute $0 — with unit prices and notes.](https://raw.githubusercontent.com/mpechner/iac-aws-org-k8s/main/articles/images/part1-table-cost.png)


## What's Next

cert-manager is usually presented as a Kubernetes-internal tool — it issues certs for Ingress resources and that's it. But DNS-01 validation decouples issuance from where the cert is used, and a CronJob publisher bridges the gap to an external secret store. The result is a general-purpose certificate pipeline for your entire infrastructure.

If you have cert-manager running in your cluster, you have 90% of this pipeline already. The last 10% is plumbing — and you only write the consumer once per service type.

**But we haven't talked about security yet.** This pipeline stores private keys in Secrets Manager and uses node-level IAM that gives every pod on every node write access to your certs. For dev, that's fine. For production, it's not.

**Part 2: Securing the Pipeline** — coming shortly — covers who should have access to your secrets (and who shouldn't), resource policies, customer-managed KMS keys, IRSA for pod-level IAM scoping, and why IMDSv1 is a dealbreaker.


*The complete implementation is open source at [github.com/mpechner/iac-aws-org-k8s](https://github.com/mpechner/iac-aws-org-k8s). The reusable Terraform module is at [`deployments/modules/tls-issue/`](https://github.com/mpechner/iac-aws-org-k8s/tree/main/deployments/modules/tls-issue), the publisher container at [`deployments/modules/tls-issue/publisher/`](https://github.com/mpechner/iac-aws-org-k8s/tree/main/deployments/modules/tls-issue/publisher), and the OpenVPN-specific Ansible consumer at [`openvpn/ansible/`](https://github.com/mpechner/iac-aws-org-k8s/tree/main/openvpn/ansible). The repo includes the full VPC, RKE2 cluster, Traefik ingress stack, and deployment runbook — not just the cert pipeline.*


## A Note on How This Was Written

AI coding agents (Claude, in Cursor) were used heavily throughout this project — not just for writing this article, but for building the infrastructure itself. Terraform modules, the Python publisher, the Ansible playbooks, and much of the debugging were developed in collaboration with agentic AI.

The architecture and design decisions came from understanding the environment — looking at cert-manager already running in the cluster and asking "why am I manually renewing a VPN cert when the automation is right there?" The issues documented here surfaced during actual deployment: the VPC endpoint DNS behavior cost hours of investigation before the fix was clear, and the `sacli` vs file copy distinction was learned the hard way when certs stopped working after a direct file replacement.

Where the AI helped was in execution: generating clean Terraform, structuring the Python publisher idiomatically, translating requirements into working Ansible, and organizing scattered notes into a readable article. In practice it worked as a force multiplier — the system still needed someone who understood the architecture, could recognize when something was wrong, and could iterate until it worked.

The full project is public at [github.com/mpechner/iac-aws-org-k8s](https://github.com/mpechner/iac-aws-org-k8s). The commit history shows the evolution — initial implementations, failures, and the fixes that made it work.
