# Your Kubernetes Cluster Already Has a Certificate Authority — Use It for Everything

**How to use cert-manager to issue and deliver Let's Encrypt TLS certificates to services *outside* your cluster, with AWS Secrets Manager as the bridge**

---

## The Pattern Nobody Talks About

If you're running Kubernetes with cert-manager, you already have a fully automated certificate issuance pipeline. It handles ACME challenges, renews before expiry, and stores certs as Kubernetes Secrets. For services *inside* the cluster — ingress controllers, internal APIs — it's seamless.

But what about the services that live *outside* the cluster?

Your VPN server. Your legacy application on a standalone EC2 instance. A third-party appliance that needs a TLS cert but can't run cert-manager itself. A load balancer frontend that isn't managed by Kubernetes. These services still need TLS certificates, and most teams manage them separately — manual renewal, cron scripts hitting Let's Encrypt directly, or expensive wildcard certs.

The insight: **cert-manager can issue certificates for any domain you control, not just domains that resolve to cluster services.** If you're already using DNS-01 validation (as opposed to HTTP-01), the cert issuance has zero coupling to where the cert will actually be used. All cert-manager needs is the ability to create a DNS TXT record in your hosted zone. The certificate itself can go anywhere.

The missing piece is a **delivery mechanism** — a way to get the certificate from the Kubernetes Secret where cert-manager stores it to the external service that needs it. That's what this article builds: a reusable pipeline using AWS Secrets Manager as the intermediary.

---

## The Architecture: Issue, Publish, Consume

The pipeline has three stages that are cleanly decoupled from each other:

1. **Issue** — cert-manager obtains and renews the certificate via DNS-01 challenge, stores it as a Kubernetes Secret
2. **Publish** — a CronJob reads the Secret and writes it to AWS Secrets Manager (only when the cert changes)
3. **Consume** — a cron job on the external service pulls from Secrets Manager and installs the cert (only when it's new)

Each stage knows nothing about the others. The Kubernetes side doesn't know or care what consumes the secret. The external service doesn't know or care how the cert was issued. Secrets Manager is the contract boundary.

![Architecture diagram: three-stage certificate pipeline — Issue (cert-manager in K8s), Publish (CronJob to Secrets Manager), Consume (external services pull and install)](images/cert-pipeline-architecture.png)

**Why this decoupling matters:**

- **One publisher, many consumers.** You write the publish side once. Each external service only needs a small consumer script tailored to how *it* installs certs.
- **The publisher is reusable.** The same container image, CronJob template, and RBAC pattern work for any certificate. Only the environment variables change.
- **Secrets Manager is the right abstraction.** It handles encryption at rest, access control via IAM, audit logging via CloudTrail, and versioning. You don't have to build any of that.

The rest of this article walks through a complete implementation using **OpenVPN Access Server** as the external service. But the pattern applies to anything — an SMTP gateway, a standalone database proxy, a network appliance, a Jenkins server. Anywhere you'd otherwise manually install a cert.

---

## The Concrete Example: OpenVPN Access Server

My OpenVPN Access Server runs on an EC2 instance in a public subnet. It had a static TLS certificate that I renewed annually. The cluster already ran cert-manager for Traefik ingress, Rancher, and sample apps. The question was simple: why maintain a separate cert lifecycle for the VPN?

Here's the specific setup:

| Component | Details |
|-----------|---------|
| Kubernetes distribution | RKE2 (private subnets) |
| cert-manager version | v1.15+ |
| DNS provider | Route53 |
| Secret store | AWS Secrets Manager |
| External service | OpenVPN Access Server (EC2, public subnet) |
| Certificate lifetime | 90 days (Let's Encrypt) |
| Renewal trigger | Day 60 (`renewBefore: 720h`) |
| Publish frequency | Every 6 hours (K8s CronJob) |
| Consume frequency | Every 30 min, midnight–3am only (system cron, maintenance window) |

---

## Part 1: The Kubernetes Side — Issue and Publish

> **In the repo:** The entire publish side is a single Terraform module at [`deployments/modules/tls-issue/`](https://github.com/mpechner/tf_take2/tree/main/deployments/modules/tls-issue). It's called from [`deployments/dev-cluster/2-applications/openvpn-cert.tf`](https://github.com/mpechner/tf_take2/blob/main/deployments/dev-cluster/2-applications/openvpn-cert.tf). The standalone YAML equivalents (for `kubectl apply` without Terraform) are in the `cert-manager/` subdirectory.

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

**Gotcha #1: IAM credentials for cert-manager.** If your cluster nodes run on EC2, cert-manager can use the **node's IAM instance profile** for Route53 access. No static access keys, no Kubernetes Secrets with AWS credentials to rotate. The node IAM role needs:

```json
{
  "Effect": "Allow",
  "Action": [
    "route53:ChangeResourceRecordSets",
    "route53:ListResourceRecordSets"
  ],
  "Resource": "arn:aws:route53:::hostedzone/YOUR_ZONE_ID"
}
```

Plus `ListHostedZonesByName` and `GetChange` on `*` (AWS requires these to be unscoped).

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

> **In the repo:** [`deployments/modules/tls-issue/publisher/`](https://github.com/mpechner/tf_take2/tree/main/deployments/modules/tls-issue/publisher) — contains the Python script, Dockerfile, requirements.txt, and a [README](https://github.com/mpechner/tf_take2/blob/main/deployments/modules/tls-issue/publisher/README.md) with IAM setup and build instructions.

The publisher is a small Python script (~200 lines) that:

1. Reads `tls.crt` and `tls.key` from a volume mount (the Kubernetes Secret)
2. Computes the SHA256 fingerprint of the leaf certificate
3. Checks the existing fingerprint in Secrets Manager
4. Writes only if the fingerprint has changed

The fingerprint comparison is what makes this safe to run frequently — no unnecessary API calls, no Secrets Manager version churn.

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

The Dockerfile is minimal — Python 3.12 slim with `boto3` and `cryptography`:

```dockerfile
FROM public.ecr.aws/docker/library/python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY publish_cert_to_secretsmanager.py .
ENTRYPOINT ["python3", "-u", "publish_cert_to_secretsmanager.py"]
```

**Gotcha #3: Docker Hub rate limits.** If you pull base images from Docker Hub, you'll hit rate limits in a cluster that restarts pods frequently. `public.ecr.aws/docker/library/python:3.12-slim` is the same image, no authentication required, no rate limits.

**This container image is fully reusable.** It's parameterized entirely through environment variables — there's nothing OpenVPN-specific in it. To publish a cert for a different service, you just change the env vars.

### Step 4: Deploy the CronJob

```hcl
resource "kubernetes_manifest" "cert_publisher_cronjob" {
  manifest = {
    apiVersion = "batch/v1"
    kind       = "CronJob"
    metadata = {
      name      = "publish-cert-to-secretsmanager"
      namespace = "myservice-certs"
    }
    spec = {
      schedule          = "0 */6 * * *"   # Every 6 hours
      concurrencyPolicy = "Forbid"
      jobTemplate = {
        spec = {
          backoffLimit            = 2
          activeDeadlineSeconds   = 300
          ttlSecondsAfterFinished = 86400
          template = {
            spec = {
              serviceAccountName = "cert-publisher"
              restartPolicy      = "OnFailure"
              containers = [
                {
                  name  = "publisher"
                  image = "ACCOUNT.dkr.ecr.REGION.amazonaws.com/cert-publisher:latest"
                  env = [
                    { name = "AWS_REGION",           value = "us-west-2" },
                    { name = "AWS_SECRET_NAME",      value = "myservice/dev" },
                    { name = "VPN_FQDN",             value = "myservice.dev.example.com" },
                    { name = "TLS_SECRET_NAME",      value = "myservice-tls" },
                    { name = "TLS_SECRET_NAMESPACE", value = "myservice-certs" },
                  ]
                  volumeMounts = [
                    {
                      name      = "tls"
                      readOnly  = true
                      mountPath = "/etc/tls"
                    }
                  ]
                }
              ]
              volumes = [
                {
                  name = "tls"
                  secret = {
                    secretName = "myservice-tls"
                    optional   = false
                  }
                }
              ]
            }
          }
        }
      }
    }
  }
}
```

The volume mount is the critical design choice — the Kubernetes Secret is mounted directly at `/etc/tls`. No kubectl in the container, no API server calls, no service account token with broad permissions. The RBAC for the `cert-publisher` ServiceAccount is scoped to `get` on a single named Secret.

### Step 5: IAM Permissions for the Cluster Nodes

> **In the repo:** The node IAM role with Route53 and Secrets Manager permissions is in [`RKE-cluster/modules/ec2/main.tf`](https://github.com/mpechner/tf_take2/blob/main/RKE-cluster/modules/ec2/main.tf). The hosted zone IDs are passed via `route53_hosted_zone_ids` in [`RKE-cluster/dev-cluster/ec2/terraform.tfvars`](https://github.com/mpechner/tf_take2/blob/main/RKE-cluster/dev-cluster/ec2/terraform.tfvars.example).

The CronJob uses the EC2 node's instance profile. The node role needs:

**For cert-manager (DNS-01 validation):**

```json
{
  "Sid": "DNS01Challenge",
  "Effect": "Allow",
  "Action": ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets"],
  "Resource": "arn:aws:route53:::hostedzone/YOUR_ZONE_ID"
}
```

**For the publisher (Secrets Manager write):**

```json
{
  "Sid": "WriteCerts",
  "Effect": "Allow",
  "Action": ["secretsmanager:PutSecretValue", "secretsmanager:CreateSecret"],
  "Resource": "arn:aws:secretsmanager:us-west-2:*:secret:myservice/*"
}
```

No separate IAM users, no static access keys stored anywhere.

**Important caveat:** This node-role approach means *every pod on every node* inherits these permissions — including Secrets Manager write and Route53 modify. For a dev environment, this is acceptable. For production, you must use IRSA to scope these permissions to only the pods that need them. See **"The Elephant in the Room: Who Can Read Your Private Keys?"** below for the full production security model.

---

## Part 2: The Consumer Side — Pull and Install

This is the service-specific half. Each external service needs a small consumer tailored to how *it* installs certificates. The example below is for OpenVPN Access Server, but the pattern — fetch from Secrets Manager, compare fingerprints, install if changed — applies to anything.

### Adapting the Consumer to Other Services

Before diving into the OpenVPN specifics, here's how the consumer pattern maps to different services:

| External Service | Cert Install Method | Restart Method | Consumer Runs As |
|-----------------|---------------------|----------------|-----------------|
| **OpenVPN Access Server** | `sacli ConfigPut` (cs.cert, cs.priv_key) | `sacli start` (web only) | System cron on the instance |
| **Nginx (standalone)** | Write to `/etc/nginx/ssl/` | `nginx -s reload` | System cron on the instance |
| **Apache** | Write to `SSLCertificateFile` path | `systemctl reload httpd` | System cron on the instance |
| **HAProxy** | Concatenate cert+key to single PEM | `systemctl reload haproxy` | System cron on the instance |
| **PostgreSQL** | Write to `ssl_cert_file` path | `pg_ctl reload` | System cron on the instance |
| **SMTP (Postfix)** | Write to `smtpd_tls_cert_file` path | `postfix reload` | System cron on the instance |
| **AWS ALB/NLB** | `aws iam upload-server-certificate` or `aws acm import-certificate`, update listener | No restart — listener picks up new cert | K8s CronJob or Lambda |
| **AWS CloudFront** | `aws cloudfront update-distribution` with new ACM cert ARN | No restart — propagates to edge | K8s CronJob or Lambda |
| **Generic API-managed** | API call to update cert (varies by service) | Usually no restart | K8s CronJob or Lambda |

For services you SSH into (OpenVPN, Nginx, databases), the consumer naturally runs as a cron job on the instance itself. But for **AWS-managed services** like ALBs, NLBs, and CloudFront — where there's no server to SSH into — the consumer is just an API call. That can run as a **Kubernetes CronJob** in the same cluster (using the same publisher image pattern with a different entrypoint), or as an **AWS Lambda** triggered on a schedule or by an SNS notification from the publisher. Either way, the consumer reads the same Secrets Manager secret and calls the AWS API to import the cert. No SSH, no Ansible, no system cron — just an API client with the right IAM permissions.

**Think about your maintenance window.** Every service has a different tolerance for restarts. Nginx and HAProxy can reload without dropping connections (`nginx -s reload`, `systemctl reload haproxy`). OpenVPN's `sacli start` briefly interrupts the web UI but not VPN tunnels. PostgreSQL's `pg_ctl reload` picks up the new cert on the next client connection with no downtime at all. Match your cron schedule to when a restart is safe — for OpenVPN, that meant restricting the sync to a midnight–3am window so the admin console blip goes unnoticed.

The consumer script skeleton is always the same:

```bash
# 1. Fetch secret from Secrets Manager
SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" ...)

# 2. Extract cert and key from JSON
NEW_CERT=$(echo "$SECRET_VALUE" | python3 -c "import sys,json; print(json.load(sys.stdin)['fullchain_pem'])")
NEW_KEY=$(echo "$SECRET_VALUE" | python3 -c "import sys,json; print(json.load(sys.stdin)['privkey_pem'])")

# 3. Compute fingerprint of new cert
NEW_FP=$(openssl x509 -in "$NEW_CERT_FILE" -noout -pubkey | openssl sha256)

# 4. Compare with installed cert — exit early if unchanged
[[ "$NEW_FP" == "$CURRENT_FP" ]] && exit 0

# 5. Backup, install, restart — THIS PART IS SERVICE-SPECIFIC
install_cert "$NEW_CERT_FILE" "$NEW_KEY_FILE"
restart_service
```

### The OpenVPN Consumer: Step by Step

Now for the concrete example. Here's how this plays out for OpenVPN Access Server.

#### Step 6: Networking — The VPC Endpoint Gotcha

> **In the repo:** The VPC endpoints are configured in [`vpc/modules/vpc/mainf.tf`](https://github.com/mpechner/tf_take2/blob/main/vpc/modules/vpc/mainf.tf) (search for `vpc_endpoints`). The SG rule allowing OpenVPN to reach them is in [`openvpn/devvpn/main.tf`](https://github.com/mpechner/tf_take2/blob/main/openvpn/devvpn/main.tf) (`aws_security_group_rule.openvpn_to_vpc_endpoints`).

This was the trickiest part, and it applies to *any* external service in a public subnet that needs to reach Secrets Manager.

My VPC had interface endpoints for Secrets Manager with `private_dns_enabled = true` (the default). This means the hostname `secretsmanager.us-west-2.amazonaws.com` resolves to **private endpoint IPs** for *every* host in the VPC — including hosts in public subnets. The endpoint security group only allowed ingress from private subnet CIDRs.

**Result: AWS CLI calls from the OpenVPN server timed out silently.**

I implemented both a belt and suspenders fix — either one alone would work, but together they cover different failure modes:

**Fix 1: Add an SG rule** letting the OpenVPN security group reach the VPC endpoint on port 443. This is the "do it properly" fix — it lets the server use the VPC endpoint path, which stays inside the AWS network and avoids internet transit:

```hcl
resource "aws_security_group_rule" "service_to_vpc_endpoints" {
  count                    = length(data.aws_security_groups.vpc_endpoints.ids) > 0 ? 1 : 0
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = module.openvpn.openvpn_security_group_id
  security_group_id        = data.aws_security_groups.vpc_endpoints.ids[0]
  description              = "Allow external service to reach VPC endpoints"
}
```

Note the `count` guard — if the VPC endpoint doesn't exist (e.g. `enable_vpc_endpoints = false`), the rule is skipped instead of failing.

**Fix 2: Use the public endpoint URL explicitly** in the sync script, bypassing the VPC endpoint DNS override entirely:

```bash
AWS_CLI="aws --endpoint-url https://secretsmanager.${SECRET_REGION}.amazonaws.com"
```

This is the fallback. If the VPC endpoint SG rule is misconfigured, or if the endpoint is temporarily unavailable, the sync script still works by going through the public internet. Since the request is TLS-encrypted and authenticated with IAM SigV4, there's no security downside — it's the same path you'd use without VPC endpoints at all.

![Network diagram: VPC endpoint DNS gotcha — public subnet services resolve to private endpoint IPs, causing timeouts. Fix 1: SG rule allowing OpenVPN SG to Endpoint SG on 443. Fix 2: explicit --endpoint-url bypassing VPC endpoint DNS.](images/vpc-endpoint-dns-gotcha.png)

**Gotcha #4: VPC endpoints with private DNS.** This will bite *any* service in a public subnet that calls an AWS API for which you have a VPC interface endpoint. It's not specific to Secrets Manager. If you have endpoints for STS, KMS, or SSM, the same DNS override applies. Either open the endpoint SG or use explicit endpoint URLs.

#### Step 7: IAM for the External Service

> **In the repo:** The OpenVPN IAM role and Secrets Manager policy are in [`openvpn/module/main.tf`](https://github.com/mpechner/tf_take2/blob/main/openvpn/module/main.tf) (`aws_iam_role.openvpn` and `aws_iam_role_policy.openvpn_secrets`). The RKE node role's Secrets Manager write permissions are in [`RKE-cluster/modules/ec2/main.tf`](https://github.com/mpechner/tf_take2/blob/main/RKE-cluster/modules/ec2/main.tf). Reference IAM policy snippets are in [`deployments/modules/tls-issue/aws/`](https://github.com/mpechner/tf_take2/tree/main/deployments/modules/tls-issue/aws).

The external service needs an IAM role to read from Secrets Manager. Here's the OpenVPN version — adapt the resource ARN pattern for your service's secret path:

```hcl
resource "aws_iam_role_policy" "service_secrets" {
  name = "dev-service-secrets-policy"
  role = aws_iam_role.service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = ["arn:aws:secretsmanager:*:*:secret:myservice/*"]
      },
      {
        Sid    = "DecryptSecretsManagerEnvelope"
        Effect = "Allow"
        Action = ["kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.us-west-2.amazonaws.com"
          }
        }
      }
    ]
  })
}
```

**Gotcha #5: KMS envelope encryption.** Secrets Manager *always* uses KMS for encryption — even if you're using the default `aws/secretsmanager` key. Without `kms:Decrypt`, the `GetSecretValue` call fails with an access denied error even though the Secrets Manager permission is correct. The `kms:ViaService` condition ensures the KMS permission is only usable through Secrets Manager.

**Gotcha #6: IMDSv2 and hop limit.** Your EC2 instances must enforce IMDSv2 (`http_tokens = "required"`). This is not optional. IMDSv1 allows any process on the instance to retrieve IAM credentials with a single unauthenticated HTTP GET to `169.254.169.254` — no headers, no session token, nothing. An SSRF vulnerability in any application on the instance becomes instant credential theft. IMDSv2 requires a PUT to get a session token first, which SSRF attacks can't easily forge. If you're still running IMDSv1, fix that before worrying about certificate automation.

With IMDSv2 enforced, the default hop limit of 1 works for the host itself. Set `http_put_response_hop_limit = 2` if the service runs in a container or behind a proxy on the same instance — the extra network hop consumes the TTL and the token request never reaches IMDS.

#### Step 8: Deploy the Consumer via Ansible

> **In the repo:** The Ansible playbook is at [`openvpn/ansible/openvpn-tls-sync.yml`](https://github.com/mpechner/tf_take2/blob/main/openvpn/ansible/openvpn-tls-sync.yml), the wrapper script at [`openvpn/ansible/setup-tls-sync.sh`](https://github.com/mpechner/tf_take2/blob/main/openvpn/ansible/setup-tls-sync.sh), and the Terraform `null_resource` that automates it during deployment at [`openvpn/devvpn/main.tf`](https://github.com/mpechner/tf_take2/blob/main/openvpn/devvpn/main.tf).

For OpenVPN, I used Ansible to install the consumer cron. The playbook does three things:

1. **Installs AWS CLI v2** (pinned version, with checksum verification)
2. **Creates `/usr/local/bin/sync-vpn-tls.sh`** — the sync script
3. **Creates a cron job** running every 30 minutes, but only between midnight and 3am — a maintenance window when it's safe to restart the web service. Installing a new cert requires an `sacli start`, which briefly restarts the OpenVPN web UI. VPN tunnels are not affected, but the admin console and client download portal are momentarily unavailable. Constraining the cron to overnight hours ensures this blip happens when nobody is actively using the web interface.

The sync script's logic:

```
Fetch secret from Secrets Manager
  → Extract fullchain_pem and privkey_pem from JSON
  → Compute SHA256 fingerprint of new cert
  → Compare with currently installed cert's fingerprint
  → If unchanged: exit (no-op)
  → If changed:
      → Backup current certs
      → Import via sacli ConfigPut (cs.cert, cs.priv_key, cs.ca_bundle)
      → sacli start (restart web service only, not VPN tunnels)
      → Verify web service is running
```

The OpenVPN-specific parts are only the last three lines. Everything above them is generic.

**Key detail: `sacli` vs file copy.** An earlier version (still in the repo as [`openvpn/ansible/install-cert-via-ssh.sh`](https://github.com/mpechner/tf_take2/blob/main/openvpn/ansible/install-cert-via-ssh.sh)) simply copied PEM files to `/usr/local/openvpn_as/etc/web-ssl/`. It worked, but `sacli ConfigPut` is the proper OpenVPN Access Server method — it updates the internal database and handles the certificate chain correctly. `sacli start` then restarts only the web service component. Connected VPN tunnels are **not disrupted**.

For a different service (say, standalone Nginx), the install step would be:

```bash
cp "$NEW_CERT" /etc/nginx/ssl/server.crt
cp "$NEW_KEY"  /etc/nginx/ssl/server.key
nginx -s reload
```

**Gotcha #7: Ansible temp directory on OpenVPN AS.** The `openvpnas` user has restricted home directory permissions. Ansible's default `~/.ansible/tmp` path fails. Fix: set `ansible_remote_tmp: /tmp/.ansible-${USER}` in the playbook vars. This will affect any appliance or restricted-user environment.

Note: this `/tmp` usage is only for Ansible's own control files (Python modules, task scripts) — **not** for TLS certificate material. The sync script itself never writes private keys to `/tmp`. During a security sweep, we moved cert handling to a root-owned secure temp directory (`mktemp -d /root/.openvpn-tls-sync-XXXXXX`, `chmod 700`) with a `trap "rm -rf" EXIT` that cleans up on any exit path — success, failure, or signal. The private key exists on disk only in that locked-down directory, only while the script is running.

#### Running the Setup

A wrapper script handles prerequisite checks and runs the playbook:

```bash
# Override defaults with environment variables
VPN_FQDN="vpn.dev.example.com"
SSH_KEY="$HOME/.ssh/openvpn-ssh"
TLS_SECRET_NAME="openvpn/dev"

cd openvpn/ansible
./setup-tls-sync.sh
```

The script checks: Ansible installed? SSH key exists? AWS credentials valid? Secret exists? Server reachable? SSH works? Only then does it run the playbook.

For full automation via Terraform:

```hcl
resource "null_resource" "tls_sync" {
  triggers = {
    instance_id = module.openvpn.openvpn_server_id
  }

  provisioner "local-exec" {
    command = "./setup-tls-sync.sh"
    environment = {
      AUTO_APPROVE = "1"
      SSH_ATTEMPTS = "6"
      SSH_WAIT     = "20"
    }
  }
}
```

`AUTO_APPROVE` skips interactive prompts. `SSH_ATTEMPTS` with retries handles fresh instances that are still booting.

---

## Part 3: The Shared Contract — Secret JSON Format

The publisher and consumer agree on a JSON schema in Secrets Manager:

```json
{
  "fqdn": "vpn.dev.example.com",
  "fingerprint_sha256": "a1b2c3d4e5f6...",
  "fullchain_pem": "-----BEGIN CERTIFICATE-----\n...",
  "privkey_pem": "-----BEGIN PRIVATE KEY-----\n...",
  "chain_pem": "-----BEGIN CERTIFICATE-----\n..."
}
```

| Field | Purpose |
|-------|---------|
| `fqdn` | The domain the cert was issued for (informational, for logging) |
| `fingerprint_sha256` | SHA256 of the leaf certificate DER — the idempotency key |
| `fullchain_pem` | Leaf + intermediate chain (what most services want for "certificate") |
| `privkey_pem` | The private key |
| `chain_pem` | Just the intermediate chain (some services need this separately) |

The `fingerprint_sha256` is what makes both sides idempotent:
- The **publisher** skips `PutSecretValue` if the fingerprint hasn't changed
- The **consumer** skips cert installation if the installed fingerprint matches

This means both cron jobs can run frequently without generating API calls, Secrets Manager versions, or service restarts.

---

## The Elephant in the Room: Who Can Read Your Private Keys?

This secret contains a private key. Anyone who can read it can impersonate your service. Getting the permissions right isn't optional — it's the whole point of using Secrets Manager instead of, say, an S3 bucket.

### Principle: Minimum Readers, Scoped Writers

The access model should be:

| Role | Permissions | Scope |
|------|------------|-------|
| **Publisher CronJob** (K8s) | `PutSecretValue`, `CreateSecret`, `GetSecretValue` | Single secret path (e.g. `openvpn/dev`) |
| **Consumer** (external service) | `GetSecretValue`, `DescribeSecret` | Single secret path |
| **Terraform execution role** | `DescribeSecret` (if used for data lookups) | Single secret path |
| **Everyone else** | Nothing | — |

Nobody else — not your CI/CD pipeline, not your developers, not other services — should have access. This is a private key, not a config value.

### Secrets Manager Resource Policy

Beyond IAM policies on the roles, attach a **resource policy** directly to the secret. This acts as a second gate — even if someone's IAM policy grants `GetSecretValue` on `*`, the resource policy can deny them:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPublisher",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT:role/rke-nodes-role"
      },
      "Action": [
        "secretsmanager:PutSecretValue",
        "secretsmanager:CreateSecret",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowConsumer",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT:role/dev-openvpn-role"
      },
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyEverythingElse",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "secretsmanager:*",
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:PrincipalArn": [
            "arn:aws:iam::ACCOUNT:role/rke-nodes-role",
            "arn:aws:iam::ACCOUNT:role/dev-openvpn-role",
            "arn:aws:iam::ACCOUNT:role/terraform-execute"
          ]
        }
      }
    }
  ]
}
```

The explicit `Deny` with `StringNotEquals` ensures that even account admins can't accidentally read the secret without first removing the resource policy. In production, you'd add a `Condition` for the Terraform role limiting it to `DescribeSecret` only.

### Use a CMK, Not the Default KMS Key (Production Recommendation)

My implementation currently uses the default AWS-managed key `aws/secretsmanager`. The publisher supports a CMK via an optional `KMS_KEY_ID` environment variable, but I haven't set it — so the secret is encrypted with the default key. This is a documented, accepted risk for the dev environment — see [P-002 in SECURITY-REVIEW.md](https://github.com/mpechner/tf_take2/blob/main/SECURITY-REVIEW.md) for the full assessment. The KMS `Decrypt` permission is locked down with a `kms:ViaService` condition so the node role can't use it for anything other than Secrets Manager, and the OpenVPN module accepts a `kms_key_arn` variable to upgrade to a CMK when you're ready. For a dev environment behind a VPN with a small team, this is acceptable.

For production, it's not. The default key's policy allows anyone in the account with `kms:Decrypt` permission to decrypt any secret encrypted with it. For a TLS private key, you want a **customer-managed KMS key** with a key policy that explicitly lists the allowed principals:

```hcl
resource "aws_kms_key" "cert_secrets" {
  description         = "Encrypt TLS certificate secrets"
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowKeyAdmin"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::ACCOUNT:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowPublisherEncrypt"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::ACCOUNT:role/rke-nodes-role" }
        Action   = ["kms:Encrypt", "kms:GenerateDataKey", "kms:Decrypt"]
        Resource = "*"
      },
      {
        Sid    = "AllowConsumerDecrypt"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::ACCOUNT:role/dev-openvpn-role" }
        Action   = ["kms:Decrypt"]
        Resource = "*"
      }
    ]
  })
}
```

Now even if someone has `secretsmanager:GetSecretValue` permission, they can't decrypt the payload without also being in the KMS key policy.

### CloudTrail: Know Who Accessed What

Secrets Manager automatically logs every `GetSecretValue` and `PutSecretValue` call to CloudTrail. Set up a CloudWatch alarm for any `GetSecretValue` call from an unexpected principal — it means either your permissions are too broad or someone is poking around:

```
filter: { $.eventName = "GetSecretValue" && $.requestParameters.secretId = "openvpn/*" }
alarm:  when count > 0 from unexpected principal ARNs
```

### The Node Role Problem — Why IRSA Matters for Production

The implementation described so far uses the **EC2 node instance profile** for the publisher CronJob. This is the simplest approach, and it works. But it has a serious implication: **every pod on every node inherits the node's IAM permissions.** That means every pod in your cluster — your sample Nginx app, your monitoring stack, a compromised container — can write to Secrets Manager and modify DNS records in Route53.

For a dev environment behind a VPN, this is an acceptable tradeoff. For production, it's not.

**IRSA (IAM Roles for Service Accounts)** solves this by letting you bind an IAM role to a specific Kubernetes ServiceAccount. Only pods using that ServiceAccount get the role's permissions. Everything else on the node gets nothing.

Here's what the production version looks like:

```hcl
# 1. Create an IAM role that trusts the cluster's OIDC provider
resource "aws_iam_role" "cert_publisher" {
  name = "cert-publisher-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::ACCOUNT:oidc-provider/${OIDC_PROVIDER}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${OIDC_PROVIDER}:sub" = "system:serviceaccount:openvpn-certs:cert-publisher"
        }
      }
    }]
  })
}

# 2. Attach only the permissions the publisher needs
resource "aws_iam_role_policy" "cert_publisher" {
  role = aws_iam_role.cert_publisher.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:PutSecretValue", "secretsmanager:CreateSecret",
                     "secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = "arn:aws:secretsmanager:us-west-2:ACCOUNT:secret:openvpn/*"
      }
    ]
  })
}

# 3. Annotate the Kubernetes ServiceAccount
resource "kubernetes_manifest" "cert_publisher_sa" {
  manifest = {
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = "cert-publisher"
      namespace = "openvpn-certs"
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.cert_publisher.arn
      }
    }
  }
}
```

With IRSA:
- The publisher pod gets `PutSecretValue` on `openvpn/*` — and nothing else
- The node role no longer needs Secrets Manager write permissions
- A compromised pod on the same node can't touch your certificates
- The Route53 permissions for cert-manager can similarly be scoped to cert-manager's own ServiceAccount

**Why I didn't implement IRSA here:** This repo runs on RKE2, not EKS. On EKS, IRSA is turnkey — Amazon manages the OIDC provider and the webhook that injects credentials into pods. On RKE2, you have to stand up your own OIDC issuer, host the JWKS discovery document somewhere publicly reachable (usually S3 + CloudFront), configure the API server's `--service-account-issuer` and `--service-account-jwks-uri` flags, and wire the IAM trust policies to your self-hosted provider. It's doable — there's a scaffolded [IRSA module](https://github.com/mpechner/tf_take2/tree/main/modules/irsa) in the repo — but it's a significant amount of plumbing for a project meant as a learning reference. The node-role approach keeps the cert pipeline understandable without requiring readers to also understand OIDC federation. See [P-003 in SECURITY-REVIEW.md](https://github.com/mpechner/tf_take2/blob/main/SECURITY-REVIEW.md) for the production assessment.

**Bottom line:** the node-role approach in this article is fine for development. For production, IRSA is not a "nice to have" — it's table stakes. The blast radius of a compromised pod goes from "can rewrite TLS certs and DNS records" to "can do nothing beyond its own namespace."

---

## Part 4: Deployment Runbook

> **In the repo:** The paths below are relative to [github.com/mpechner/tf_take2](https://github.com/mpechner/tf_take2). The repo's top-level [README](https://github.com/mpechner/tf_take2#readme) has the full deployment walkthrough (Steps 1–12) covering everything from Organization setup through application deployment. What follows here is the cert-pipeline-specific subset. If you're starting from scratch, follow the README first — it covers VPC, VPN, SSH keys, ECR, RKE2 cluster setup, and kubectl configuration that are prerequisites for the steps below.

Here's the exact sequence for the OpenVPN implementation. Adapt Phase 2 and Phase 4 for your target service.

### Phase 1: VPC and Networking

1. **Deploy VPC** with `enable_vpc_endpoints = true` to create the Secrets Manager interface endpoint:

```bash
cd vpc/dev
terraform apply
```

2. **Note the VPC endpoint security group ID** — you'll need it if your external service is in a public subnet (see Gotcha #4).

### Phase 2: External Service (OpenVPN-specific)

3. **Deploy the external service** (EC2 instance, IAM role, security group):

```bash
cd openvpn/devvpn
terraform apply
```

4. The Terraform config includes the **SG rule** allowing the service to reach VPC endpoints and the **IAM policy** for Secrets Manager read access.

### Phase 3: Kubernetes Cluster + Pipeline

5. **Deploy K8s nodes** (with IAM roles for Route53 + Secrets Manager write):

```bash
cd RKE-cluster/dev-cluster/ec2
terraform apply
```

6. **Deploy the K8s cluster** (requires VPN for private subnet access):

```bash
cd RKE-cluster/dev-cluster/RKE
terraform apply
```

7. **Build and push the publisher image** (see [`scripts/Makefile`](https://github.com/mpechner/tf_take2/blob/main/deployments/dev-cluster/2-applications/scripts/Makefile)):

```bash
cd deployments/dev-cluster/2-applications/scripts
make   # builds, tags, authenticates to ECR, pushes
```

8. **Deploy applications** including the cert pipeline:

```bash
cd deployments/dev-cluster/2-applications
terraform apply
# Requires in terraform.tfvars:
#   openvpn_cert_enabled           = true
#   openvpn_cert_hosted_zone_id    = "YOUR_ZONE_ID"
#   openvpn_cert_letsencrypt_email = "you@example.com"
#   openvpn_cert_publisher_image   = "ACCOUNT.dkr.ecr.REGION.amazonaws.com/openvpn-dev:latest"
```

### Phase 4: Consumer Setup (OpenVPN-specific)

9. **Run the Ansible setup** (installs the consumer cron on the OpenVPN server):

```bash
cd openvpn/ansible
VPN_FQDN=vpn.dev.example.com ./setup-tls-sync.sh
```

Or, with `enable_tls_sync = true` in the OpenVPN Terraform config, this runs automatically via `null_resource` during Phase 2.

### Phase 5: Verify End-to-End

10. **Check cert-manager issued the certificate:**

```bash
kubectl get certificate -n openvpn-certs
# STATUS should be "True"
```

11. **Trigger the publisher manually** (don't wait 6 hours for the first run):

```bash
kubectl create job --from=cronjob/openvpn-publish-cert-to-secretsmanager \
  manual-publish -n openvpn-certs
kubectl logs -n openvpn-certs job/manual-publish -f
```

12. **Verify the secret landed in Secrets Manager:**

```bash
aws secretsmanager get-secret-value \
  --secret-id openvpn/dev \
  --query 'SecretString' --output text | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'FQDN:        {d[\"fqdn\"]}')
print(f'Fingerprint: {d[\"fingerprint_sha256\"][:32]}...')
print(f'Cert size:   {len(d[\"fullchain_pem\"])} bytes')
"
```

13. **Trigger the consumer manually on the external service:**

```bash
ssh -i ~/.ssh/openvpn-ssh openvpnas@vpn.dev.example.com \
  "sudo /usr/local/bin/sync-vpn-tls.sh"
```

14. **Verify in the browser:** Navigate to `https://vpn.dev.example.com:943` and inspect the certificate — it should show a Let's Encrypt issuer with a 90-day validity.

<!-- [SCREENSHOT NEEDED: Browser certificate viewer showing:
     - Subject: vpn.dev.example.com
     - Issuer: Let's Encrypt (R3 or R10)
     - Validity: ~90 days from issuance
     - The green lock icon indicating valid chain] -->

---

## Gotchas Summary

| # | Issue | Symptom | Fix | Applies To |
|---|-------|---------|-----|------------|
| 1 | cert-manager IAM | DNS-01 challenge fails | Use EC2 node instance profile, scope Route53 to your zone | All (publish side) |
| 2 | `renewBefore` too short | Cert expires before retries succeed | `renewBefore: 720h` (30-day buffer) | All (publish side) |
| 3 | Docker Hub rate limits | Publisher pod `ImagePullBackOff` | Use `public.ecr.aws` base images | All (publish side) |
| 4 | VPC endpoint private DNS | AWS CLI calls time out from public subnet | Add SG rule or use `--endpoint-url` | Any consumer in a public subnet |
| 5 | KMS envelope encryption | `GetSecretValue` access denied | Add `kms:Decrypt` with `kms:ViaService` condition | Any consumer reading Secrets Manager |
| 6 | IMDSv2 hop limit | AWS CLI 401 on IMDS | `http_put_response_hop_limit = 2` | Any EC2 with containers/nested networking |
| 7 | Restricted home dirs | Ansible `~/.ansible/tmp` fails | Set `ansible_remote_tmp: /tmp/.ansible-${USER}` | Any appliance with restricted users |
| 8 | Node role is too broad | Every pod can write certs and modify DNS | Use IRSA to scope AWS perms to publisher SA only | Production (see "Who Can Read Your Private Keys?") |
| 9 | Default KMS key too open | Any account principal with `kms:Decrypt` can read secrets | Use a customer-managed KMS key with explicit key policy | Production |

---

## Cost

| Item | Monthly Cost | Unit Price | Notes |
|------|-------------|------------|-------|
| Secrets Manager | ~$0.40 | $0.40/secret/month + $0.05/10K API calls | API cost negligible with fingerprint-based skipping |
| VPC Endpoint | ~$7.20 | $0.01/hour/AZ (~$7.20/AZ/month) | Only if not already deployed; shared across all services |
| ECR storage | ~$0.008 | $0.10/GB/month | Publisher image is ~80MB; first 500MB free for year one |
| CronJob compute | $0 | — | Runs on existing K8s nodes, ~50MB RAM for a few seconds every 6 hours |

Compare to the cost of a human forgetting to renew a cert. Or the cost of a wildcard cert from a commercial CA.

---

## Extending the Pattern

### Multiple Services, One Pipeline

To add a second external service:

1. Create a new Certificate + namespace in the cluster
2. Deploy another CronJob instance (same image, different env vars pointing to a different secret path)
3. Write a consumer script for the new service's cert install method
4. Done

The publisher image, RBAC template, and Secrets Manager JSON schema are all reused.

### What I'd Improve

1. **Event-driven instead of polling.** The 6-hour CronJob + 30-minute cron is simple but has latency. A more sophisticated approach: publisher writes to an SNS topic, which triggers SSM Run Command on the target instance. Immediate propagation, no polling, no cron.

2. **CloudWatch monitoring.** The consumer should report metrics — time since last successful sync, days until cert expiry — and trigger alarms when the pipeline is stuck.

3. **HashiCorp Vault instead of Secrets Manager.** If you're in a multi-cloud or on-prem environment, Vault provides the same intermediary role with broader reach. The publisher would use the Vault KV engine instead of boto3.

---

## Conclusion

cert-manager is usually presented as a Kubernetes-internal tool — it issues certs for Ingress resources and that's it. But the combination of DNS-01 validation (which decouples issuance from where the cert is used) and a CronJob publisher (which bridges the gap to an external secret store) turns it into a general-purpose certificate pipeline for your entire infrastructure.

The real complexity isn't in the code. It's in the networking (VPC endpoint DNS resolution affecting public-subnet hosts), the IAM layering (KMS envelope encryption on top of Secrets Manager permissions), and the service-specific install quirks (OpenVPN's `sacli` vs file copy, Ansible temp directories on restricted users). Those are the gotchas this article is meant to save you from.

If you have cert-manager running in your cluster, you have 90% of this pipeline already. The last 10% is plumbing — and you only write the consumer once per service type.

---

*The complete implementation is open source at [github.com/mpechner/tf_take2](https://github.com/mpechner/tf_take2). The reusable Terraform module is at [`deployments/modules/tls-issue/`](https://github.com/mpechner/tf_take2/tree/main/deployments/modules/tls-issue), the publisher container at [`deployments/modules/tls-issue/publisher/`](https://github.com/mpechner/tf_take2/tree/main/deployments/modules/tls-issue/publisher), and the OpenVPN-specific Ansible consumer at [`openvpn/ansible/`](https://github.com/mpechner/tf_take2/tree/main/openvpn/ansible). The repo includes the full VPC, RKE2 cluster, Traefik ingress stack, and deployment runbook — not just the cert pipeline.*

---

## A Note on How This Was Written

I used AI coding agents (Claude, in Cursor) extensively throughout this project — not just to write this article, but to build the infrastructure itself. The Terraform modules, the Python publisher, the Ansible playbooks, and much of the debugging were done in collaboration with agentic AI. I'm not going to hide that.

But here's what the AI *didn't* do:

**The idea was mine.** I'm the one who looked at cert-manager already running in my cluster and said "why am I manually renewing a VPN cert when the automation is right there?" The AI didn't suggest this pattern. It didn't know my infrastructure or what I was trying to solve.

**The architecture decisions were mine.** Using Secrets Manager as the intermediary, choosing DNS-01 over HTTP-01, putting the cert in a dedicated namespace, restricting the cron to a maintenance window — those came from thinking about my environment, not from a prompt.

**The gotchas were real.** Every gotcha in this article came from hitting a wall during actual deployment. The VPC endpoint DNS issue? I debugged that for hours before understanding why `aws secretsmanager` was timing out from a public subnet. The KMS envelope encryption requirement? That was a mystifying "access denied" that the AI confidently told me shouldn't happen. The `sacli` vs file copy distinction? I learned that the hard way when certs stopped working after a direct file replacement. The AI helped me *fix* these problems once I identified them, but it didn't warn me about them upfront.

**The security section was my insistence.** The AI's first draft had node-level IAM and no discussion of secret access control. I pushed back: "not every pod should have access to my private keys." The IRSA section, the resource policies, the CMK requirement — those came from me saying "this isn't good enough for production" and directing the AI to address it.

What the AI *did* do well: it wrote clean Terraform, structured the Python publisher idiomatically, generated the Ansible playbook from my requirements, and organized this article from my scattered notes into something readable. It's a force multiplier, not a replacement for knowing what you're building and why.

If you're using AI to build infrastructure, my advice: treat it like a fast junior engineer who's read all the docs but has never been paged at 2am. It'll write correct code for the happy path. It won't anticipate the networking edge cases, the permission layering, or the operational gotchas that only surface in a real environment. That's still your job.

The entire project — VPC, RKE2 cluster, OpenVPN, Traefik ingress, cert pipeline, penetration tests, and this article — is public at [github.com/mpechner/tf_take2](https://github.com/mpechner/tf_take2). The repo's own [README](https://github.com/mpechner/tf_take2#readme) carries the same AI transparency warning, and [`SECURITY-REVIEW.md`](https://github.com/mpechner/tf_take2/blob/main/SECURITY-REVIEW.md) documents every security finding from the penetration testing — including the ones the AI missed on first pass. Browse the commit history if you want to see the iteration in real time: the initial AI-generated code, the failures, the fixes, the "why didn't you catch this?" moments. That's the honest record of what building infrastructure with AI actually looks like.
