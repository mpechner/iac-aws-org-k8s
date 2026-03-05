# Securing the Pipeline: IAM, KMS, and the Gotchas Nobody Warns You About

**Part 2: Who can read your private keys, and what to do about it**

*This is Part 2 of a two-part series. [Part 1](part1-cert-pipeline-process.md) covers building the pipeline: using cert-manager to issue certs, a CronJob to publish them to Secrets Manager, and a consumer to install them on external services.*

---

## A Quick Recap

In Part 1, we built a certificate pipeline that uses cert-manager to issue Let's Encrypt certs for services *outside* the Kubernetes cluster. A CronJob publisher pushes the cert to AWS Secrets Manager, and a consumer script on the external service (OpenVPN, in our example) pulls and installs it during a maintenance window.

It works. It's automated. But the security story has gaps.

The publisher runs with the EC2 **node's IAM instance profile**, which means every pod on every node can write to Secrets Manager and modify Route53 DNS records. The secret is encrypted with the default AWS-managed KMS key, which any account principal with `kms:Decrypt` can unlock. And if your EC2 instances still run IMDSv1, an SSRF vulnerability in any application on the host becomes instant credential theft.

This article is about closing those gaps.

> **Live example:** The full implementation is at [github.com/mpechner/tf_take2](https://github.com/mpechner/tf_take2). Security findings are documented in [`SECURITY-REVIEW.md`](https://github.com/mpechner/tf_take2/blob/main/SECURITY-REVIEW.md).

---

## The Elephant in the Room: Who Can Read Your Private Keys?

This secret contains a TLS private key. Anyone who can read it can impersonate your service. Getting the permissions right isn't optional — it's the whole point of using Secrets Manager instead of, say, an S3 bucket.

### Principle: Minimum Readers, Scoped Writers

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

---

## KMS Encryption: Default Key vs Customer-Managed Key

### What My Implementation Uses (And Why)

My implementation currently uses the default AWS-managed key `aws/secretsmanager`. The publisher supports a CMK via an optional `KMS_KEY_ID` environment variable, but I haven't set it — so the secret is encrypted with the default key.

This is a documented, accepted risk for the dev environment — see [P-002 in SECURITY-REVIEW.md](https://github.com/mpechner/tf_take2/blob/main/SECURITY-REVIEW.md) for the full assessment.

The mitigation: the consumer's `kms:Decrypt` permission is locked down with a `kms:ViaService` condition, so the role can't use it for anything other than Secrets Manager:

```hcl
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
```

> **In the repo:** This conditional KMS policy is in [`openvpn/module/main.tf`](https://github.com/mpechner/tf_take2/blob/main/openvpn/module/main.tf) (`aws_iam_role_policy.openvpn_secrets`). The OpenVPN module accepts a `kms_key_arn` variable to upgrade to a CMK when you're ready.

For a dev environment behind a VPN with a small team, this is acceptable.

### Why Production Needs a CMK

For production, the default key isn't enough. Its key policy allows anyone in the account with `kms:Decrypt` permission to decrypt any secret encrypted with it. For a TLS private key, you want a **customer-managed KMS key** with a key policy that explicitly lists the allowed principals:

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

Now even if someone has `secretsmanager:GetSecretValue` permission, they can't decrypt the payload without also being in the KMS key policy. Two independent gates for your private key.

**Gotcha: KMS envelope encryption.** Secrets Manager *always* uses KMS — even with the default key. Without `kms:Decrypt`, `GetSecretValue` calls fail with an access denied error even though the Secrets Manager permission is correct. This catches people every time. The `kms:ViaService` condition ensures the permission is only usable through Secrets Manager, not for decrypting arbitrary data.

---

## CloudTrail: Know Who Accessed What

Secrets Manager automatically logs every `GetSecretValue` and `PutSecretValue` call to CloudTrail. Set up a CloudWatch alarm for unexpected access:

```
filter: { $.eventName = "GetSecretValue" && $.requestParameters.secretId = "openvpn/*" }
alarm:  when count > 0 from unexpected principal ARNs
```

If someone outside your publisher and consumer roles is reading the secret, your permissions are too broad — or someone is poking around.

---

## The Node Role Problem — Why IRSA Matters

The pipeline in Part 1 uses the **EC2 node instance profile** for both cert-manager (Route53) and the publisher CronJob (Secrets Manager write). This is the simplest approach, and it works. But it has a serious implication: **every pod on every node inherits the node's IAM permissions.** That means every pod in your cluster — your sample Nginx app, your monitoring stack, a compromised container — can write to Secrets Manager and modify DNS records in Route53.

### What IRSA Gives You

**IRSA (IAM Roles for Service Accounts)** binds an IAM role to a specific Kubernetes ServiceAccount. Only pods using that ServiceAccount get the role's permissions. Everything else on the node gets nothing.

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
- Route53 permissions can similarly be scoped to cert-manager's own ServiceAccount

### Why I Didn't Implement IRSA Here

This repo runs on **RKE2**, not EKS. On EKS, IRSA is turnkey — Amazon manages the OIDC provider and the webhook that injects credentials into pods.

On RKE2, you have to:
1. Stand up your own OIDC issuer
2. Host the JWKS discovery document somewhere publicly reachable (usually S3 + CloudFront)
3. Configure the API server's `--service-account-issuer` and `--service-account-jwks-uri` flags
4. Wire the IAM trust policies to your self-hosted provider

It's doable — there's a scaffolded [IRSA module](https://github.com/mpechner/tf_take2/tree/main/modules/irsa) in the repo — but it's a significant amount of plumbing for a project meant as a learning reference. The node-role approach keeps the cert pipeline understandable without requiring readers to also understand OIDC federation. See [P-003 in SECURITY-REVIEW.md](https://github.com/mpechner/tf_take2/blob/main/SECURITY-REVIEW.md) for the production assessment.

### Bottom Line

The node-role approach in Part 1 is fine for development. For production, IRSA is not a "nice to have" — it's table stakes. The blast radius of a compromised pod goes from "can rewrite TLS certs and DNS records" to "can do nothing beyond its own namespace."

---

## IMDSv2: Not Optional

Your EC2 instances **must** enforce IMDSv2 (`http_tokens = "required"`). This is not a recommendation — it's a requirement.

**Why IMDSv1 is a security anti-pattern:** IMDSv1 allows any process on the instance to retrieve IAM credentials with a single unauthenticated HTTP GET to `169.254.169.254` — no headers, no session token, nothing. An SSRF vulnerability in *any* application on the instance becomes instant credential theft. The attacker doesn't need shell access. A misconfigured proxy, a vulnerable web framework, or a server-side request forgery bug in any service — and they have your IAM role's temporary credentials.

**IMDSv2 mitigates this** by requiring a PUT request to obtain a session token first. SSRF attacks typically can't forge PUT requests with custom headers — they're limited to GET or simple POST. This single change breaks the most common cloud credential theft vector.

> **In the repo:** The OpenVPN instance enforces IMDSv2 in [`openvpn/module/main.tf`](https://github.com/mpechner/tf_take2/blob/main/openvpn/module/main.tf):

```hcl
metadata_options {
  http_tokens                 = "required"    # IMDSv2 only
  http_put_response_hop_limit = 2             # needed if service runs in container
  http_endpoint               = "enabled"
}
```

**The hop limit detail:** The default hop limit of 1 works when the AWS CLI runs directly on the host. If your service runs inside a Docker container or behind a reverse proxy on the same instance, the extra network hop decrements the TTL and the token request never reaches IMDS. Set `http_put_response_hop_limit = 2` for those cases.

**If you're still running IMDSv1, fix that before worrying about certificate automation.** The credential exposure from IMDSv1 is a far bigger risk than anything else in this article.

---

## Private Keys and Temp Files

Certificates contain private keys. How they're handled on disk matters.

### On the Consumer (External Service)

The consumer sync script creates a secure temporary directory for cert material:

```bash
WORK_DIR=$(mktemp -d /root/.openvpn-tls-sync-XXXXXX)
chmod 700 "$WORK_DIR"
trap "rm -rf '$WORK_DIR'" EXIT
```

Key properties:
- **Root-owned, mode 700** — no other user can read
- **Under `/root/`** — not in world-readable `/tmp`
- **`trap` cleanup on every exit path** — success, failure, or signal
- **Private key exists on disk only while the script runs**

This was a deliberate decision during a security sweep. An earlier version used `/tmp`, which is world-readable by default on most Linux systems. For a TLS private key, even brief exposure in `/tmp` is unacceptable.

### Ansible's Separate Temp Issue

Ansible's own temporary files (Python modules, task scripts — not your data) also default to `~/.ansible/tmp`. On appliances like OpenVPN Access Server, the service user has a restricted home directory and this path fails. The fix:

```yaml
vars:
  ansible_remote_tmp: "/tmp/.ansible-${USER}"
```

This is safe because Ansible's temp files don't contain secret material — they're execution scaffolding that's removed after each task. Don't confuse this with the cert handling above.

---

## Security Gotchas Summary

| # | Issue | Risk | Fix | Ref |
|---|-------|------|-----|-----|
| 1 | Node role too broad | Every pod can write certs + modify DNS | IRSA: scope AWS perms to publisher SA | P-003 |
| 2 | Default KMS key | Any `kms:Decrypt` principal can read secrets | Customer-managed KMS key with explicit policy | P-002 |
| 3 | No resource policy | IAM-only access control on secrets | Attach Secrets Manager resource policy with explicit Deny | — |
| 4 | IMDSv1 enabled | SSRF = instant credential theft | `http_tokens = "required"` on all instances | — |
| 5 | Certs in `/tmp` | World-readable private keys | Secure root-owned temp dir with trap cleanup | — |
| 6 | No CloudTrail alarm | Silent unauthorized access | Monitor `GetSecretValue` for unexpected principals | — |

---

## Extending the Security Model

### Multiple Services, Isolated Secrets

When you add a second external service to the pipeline:

1. **Separate secret paths** — `openvpn/dev`, `nginx/prod`, etc. Each consumer's IAM policy scopes to its own path only.
2. **Separate KMS keys** (optional) — if one service's credentials are compromised, they can't decrypt another service's certs.
3. **Separate IRSA roles** — each publisher CronJob gets its own ServiceAccount with its own IAM role.
4. **Resource policies per secret** — each secret's policy lists only its publisher and consumer.

### Event-Driven Instead of Polling

The 6-hour CronJob + 30-minute cron is simple but has latency. A more sophisticated approach: the publisher writes to an SNS topic, which triggers SSM Run Command on the target instance. Immediate propagation, no polling, no cron.

### CloudWatch Monitoring

The consumer should report metrics — time since last successful sync, days until cert expiry — and trigger alarms when the pipeline is stuck.

---

## Conclusion

The pipeline from Part 1 solves the functional problem: automated cert issuance and delivery. This article solves the security problem: making sure only the right principals can read your private keys, and limiting the blast radius when something is compromised.

The layers work together:

1. **Secrets Manager resource policy** — first gate (who can call the API)
2. **Customer-managed KMS key** — second gate (who can decrypt the payload)
3. **IRSA** — limits which pods get AWS permissions at all
4. **IMDSv2** — prevents credential theft via SSRF
5. **CloudTrail** — detects unauthorized access after the fact

No single layer is sufficient. Together, they give you defense in depth for a secret that, if leaked, lets someone impersonate your service.

The real complexity isn't in the code — it's in the permission layering (KMS envelope encryption on top of Secrets Manager permissions), the operational details (secure temp files, IMDSv2 hop limits), and understanding what "good enough for dev" versus "required for production" actually means. Those are the gotchas this article is meant to save you from.

---

*The complete implementation is open source at [github.com/mpechner/tf_take2](https://github.com/mpechner/tf_take2). Security findings are in [`SECURITY-REVIEW.md`](https://github.com/mpechner/tf_take2/blob/main/SECURITY-REVIEW.md). The IRSA module scaffold is at [`modules/irsa/`](https://github.com/mpechner/tf_take2/tree/main/modules/irsa). The IAM policies for the publisher and consumer are in [`RKE-cluster/modules/ec2/main.tf`](https://github.com/mpechner/tf_take2/blob/main/RKE-cluster/modules/ec2/main.tf) and [`openvpn/module/main.tf`](https://github.com/mpechner/tf_take2/blob/main/openvpn/module/main.tf) respectively.*

---

## A Note on How This Was Written

I used AI coding agents (Claude, in Cursor) extensively throughout this project — not just to write this article, but to build the infrastructure itself. I'm not going to hide that.

But here's what the AI *didn't* do:

**The security insistence was mine.** The AI's first draft of the pipeline had node-level IAM and no discussion of secret access control. I pushed back: "not every pod should have access to my private keys." The IRSA section, the resource policies, the CMK recommendation — those came from me saying "this isn't good enough for production" and directing the AI to address it. The AI missed KMS envelope encryption as a failure mode. It didn't flag the IMDSv1 risk until I raised it. It wrote correct-but-permissive IAM policies that I had to tighten.

**The gotchas were real.** Every gotcha came from hitting a wall during actual deployment, not from a prompt. The mystifying "access denied" from missing `kms:Decrypt`? That cost me an afternoon. The private keys in `/tmp`? Found during a manual security sweep. The AI helped me *fix* these once identified, but it didn't catch them proactively.

What the AI did well: once I specified the security requirements, it generated correct resource policies, KMS key policies, and IRSA trust configurations. It's good at translating security requirements into code — as long as a human specifies the requirements.

If you're using AI to build infrastructure: **don't accept the first draft's security model.** Push back. Ask "who else can access this?" and "what happens if this pod is compromised?" The AI will answer correctly — it just won't ask those questions itself.

The entire project is public at [github.com/mpechner/tf_take2](https://github.com/mpechner/tf_take2). The repo's [`SECURITY-REVIEW.md`](https://github.com/mpechner/tf_take2/blob/main/SECURITY-REVIEW.md) documents every security finding — including the ones the AI missed on first pass.
