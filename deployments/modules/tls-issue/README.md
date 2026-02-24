# OpenVPN TLS cert via cert-manager + Secrets Manager

**Prefer Terraform:** This module is called from **2-applications** in `openvpn-cert.tf` (source `../../modules/tls-issue`). Set `openvpn_cert_enabled`, `openvpn_cert_hosted_zone_id`, `openvpn_cert_letsencrypt_email`, and `openvpn_cert_publisher_image` in terraform.tfvars and apply from `deployments/dev-cluster/2-applications`. Terraform creates the IAM user, access key, and Kubernetes credentials Secret automatically.

This directory holds **standalone YAML and scripts** for reference or for use without Terraform (e.g. `kubectl apply -f ...`). The name `tls-issue` reflects its purpose: issuing and publishing TLS certificates for OpenVPN.

## Layout

| Path | Contents |
|------|----------|
| **cert-manager/** | ClusterIssuer (Route53 DNS-01), Certificate, RBAC for publisher, CronJob |
| **publisher/** | Python script, Dockerfile, requirements, README |
| **aws/** | IAM policy snippets (Route53 DNS-01, Secrets Manager + KMS), KMS key policy snippet |

## Apply order

1. Edit `cert-manager/clusterissuer-letsencrypt-route53.yaml`: set `HOSTED_ZONE_ID` and `email`.
2. Edit `cert-manager/certificate-vpn-example-com.yaml`: set `commonName` and `dnsNames` to your VPN FQDN (e.g. `vpn.dev.foobar.support`).
3. Apply cert-manager manifests (see `publisher/README.md` for full steps).
4. Create the AWS credentials Secret and apply the CronJob with your image and env values.

Full instructions, IAM setup, and build/push: **publisher/README.md**.
