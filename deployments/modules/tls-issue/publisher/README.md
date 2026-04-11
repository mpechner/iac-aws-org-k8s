# OpenVPN cert publisher (Kubernetes → Secrets Manager)

Reads the TLS Secret produced by cert-manager and publishes it to AWS Secrets Manager.
Idempotent: only calls `PutSecretValue` (or `CreateSecret` on first run) when the certificate fingerprint changes.

## AWS credentials — EC2 node IAM role (no static keys)

Credentials come from the EC2 node's IAM role (`rke-nodes-role`). No static access keys or
Kubernetes credential Secrets are used.

The role is configured in `RKE-cluster/dev-cluster/ec2` and must include:

| Permission | Scope | Purpose |
|---|---|---|
| `secretsmanager:PutSecretValue`, `CreateSecret` | `openvpn/*` prefix | Publisher writes the cert |
| `secretsmanager:GetSecretValue`, `DescribeSecret` | `*` | Publisher reads current value |
| `route53:ChangeResourceRecordSets`, `ListResourceRecordSets` | VPN hosted zone only | cert-manager DNS-01 |
| `route53:ListHostedZonesByName`, `GetChange` | `*` | cert-manager DNS-01 lookup |

Pass your hosted zone ID in `RKE-cluster/dev-cluster/ec2/terraform.tfvars`:
```hcl
route53_hosted_zone_ids = ["Z06437531SIUA7T3WCKTM"]
```
Then apply `RKE-cluster/dev-cluster/ec2` before applying `2-applications`.

## cert-manager DNS-01 (Route53)

The dedicated ClusterIssuer `letsencrypt-vpn-<env>` uses the **node IAM role** (ambient EC2
instance credentials) — no separate IAM user or Kubernetes Secret for cert-manager.

The ClusterIssuer specifies `hostedZoneID` to target only the VPN zone; the node role must
permit `ChangeResourceRecordSets` on that zone (configured in `RKE-cluster/dev-cluster/ec2`).

To find your hosted zone ID:
```bash
aws route53 list-hosted-zones-by-name \
  --dns-name dev.foobar.support \
  --query 'HostedZones[0].Id' --output text
# Returns e.g. /hostedzone/Z06437531SIUA7T3WCKTM — use the Z... part.
```

Pass this as both `openvpn_cert_hosted_zone_id` (in `2-applications/terraform.tfvars`) and
in `route53_hosted_zone_ids` (in `RKE-cluster/dev-cluster/ec2/terraform.tfvars`).

## Build and push the publisher image

```bash
# From deployments/rke-apps/2-applications
make -C scripts
```

Edit the variables at the top of that script if your account/region differ.  
After pushing, set in `terraform.tfvars`:

```hcl
openvpn_cert_publisher_image = "REDACTED_ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/openvpn-dev:latest"
```

The build script targets `linux/amd64` for ECR compatibility regardless of your local architecture.

## terraform.tfvars example

```hcl
openvpn_cert_enabled           = true
openvpn_cert_hosted_zone_id    = "Z06437531SIUA7T3WCKTM"
openvpn_cert_letsencrypt_email = "you@example.com"
openvpn_cert_publisher_image   = "REDACTED_ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/openvpn-dev:latest"
```

## Secret JSON format

```json
{
  "fqdn": "vpn.dev.foobar.support",
  "fingerprint_sha256": "<hex>",
  "fullchain_pem": "-----BEGIN CERTIFICATE-----...",
  "privkey_pem": "-----BEGIN PRIVATE KEY-----...",
  "chain_pem": "-----BEGIN CERTIFICATE-----..."
}
```

Consumers (e.g. OpenVPN server) use `fullchain_pem` and `privkey_pem`.
