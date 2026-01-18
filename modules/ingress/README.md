# Ingress Module

This module sets up a complete Kubernetes ingress stack with:
- **Traefik**: Modern reverse proxy and ingress controller
- **External-DNS**: Automatically manages DNS records in Route 53
- **Cert-Manager**: Automatically provisions TLS certificates from Let's Encrypt

## Prerequisites

1. **Kubernetes Cluster**: Must be already deployed and accessible
2. **Helm Provider**: Configured to access your cluster
3. **Kubernetes Provider**: Configured for the cluster
4. **Route 53 Hosted Zone**: The hosted zone should already exist
5. **IAM Permissions**: Nodes must have Route53 permissions for External-DNS and Cert-Manager

## Usage Example

```hcl
module "ingress" {
  source = "./modules/ingress"

  # AWS Configuration
  aws_region       = "us-west-2"
  route53_zone_id  = "Z1234567890ABC"  # Your hosted zone ID
  route53_domain   = "example.com"     # Your domain
  # route53_assume_role_arn = "arn:aws:iam::123456789012:role/route53-access"

  # Let's Encrypt Configuration
  letsencrypt_email       = "admin@example.com"
  letsencrypt_environment = "prod"  # or "staging" for testing

  # All three components enabled by default
  traefik_enabled    = true
  external_dns_enabled = true
  cert_manager_enabled = true

  # Optional: Custom Helm values
  traefik_set = [
    {
      name  = "image.tag"
      value = "v2.11.0"
      type  = "string"
    }
  ]

  # Optional: Managed ingresses
  ingresses = {
    app = {
      namespace      = "default"
      host           = "app.example.com"
      service_name   = "my-service"
      service_port   = 8080
      cluster_issuer = "letsencrypt-prod"
    }
  }
}
```

## Configuration Options

### Enable/Disable Components
- `traefik_enabled` - Deploy Traefik ingress controller (default: true)
- `external_dns_enabled` - Deploy External-DNS for Route53 integration (default: true)
- `cert_manager_enabled` - Deploy Cert-Manager for TLS certificates (default: true)

### Required Variables
- `route53_zone_id` - Your Route 53 hosted zone ID
- `route53_domain` - Your domain name (e.g., "example.com")
- `letsencrypt_email` - Email for Let's Encrypt certificate notifications

### Optional Variables
- `letsencrypt_environment` - Use "staging" for testing, "prod" for production
- `aws_region` - AWS region for Route53 (default: us-west-2)
- `route53_assume_role_arn` - IAM role for cross-account Route53 access

### Managed Ingresses

The module can manage Kubernetes Ingress resources with **end-to-end TLS**:

```hcl
ingresses = {
  myapp = {
    namespace          = "default"
    host               = "myapp.example.com"
    service_name       = "myapp"
    service_port       = 443
    cluster_issuer     = "letsencrypt-prod"
    backend_tls_enabled = true  # Default: always enabled
  }
}
```

**Backend TLS is automatically managed:**
- Per-namespace CA certificate
- Per-service backend certificate (cert-manager managed)
- ServersTransport for Traefik validation
- Auto-renewal 30 days before expiration
- `route53_assume_role_arn` - Optional cross-account role for Route53 access
- `ingresses` - Map of ingress definitions to create in the cluster

## Setting Up the Stack

### Step 1: Prerequisites

Ensure your cluster has the necessary IAM permissions. Nodes need these permissions for:

#### External-DNS (Route 53 access):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": ["arn:aws:route53:::hostedzone/*"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets"
      ],
      "Resource": ["*"]
    }
  ]
}
```

#### Cert-Manager (Let's Encrypt DNS validation):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:GetChange"
      ],
      "Resource": ["arn:aws:route53:::change/*"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ],
      "Resource": ["arn:aws:route53:::hostedzone/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["route53:ListHostedZonesByName"],
      "Resource": ["*"]
    }
  ]
}
```

## Account-Specific Deployment Layout

This repo now mirrors the `RKE-cluster` layout for ingress deployments. Use
`ingress/dev-cluster` as the dev account stack and pass account-specific
settings (Route53 zone, email, and ingresses) there.

### Step 2: Apply Terraform Configuration

```bash
terraform init
terraform plan
terraform apply
```

### Step 3: Verify Installation

Check all components are running:
```bash
kubectl get pods -n kube-system | grep traefik
kubectl get pods -n kube-system | grep external-dns
kubectl get pods -n cert-manager
```

Check the Traefik service LoadBalancer IP:
```bash
kubectl get svc -n kube-system traefik
```

## Creating Ingresses

### Managed Ingresses (Terraform)
Add entries to `ingresses` to have Terraform create multiple ingress resources per account.
Each entry supports `host`, `service_name`, `service_port`, `cluster_issuer`, and optional
`path`, `path_type`, `ingress_class_name`, `tls_secret_name`, and `annotations`.

### Method 1: Using Traefik IngressRoute (Recommended)

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
  namespace: default
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`myapp.example.com`)
      kind: Rule
      services:
        - name: my-service
          port: 8080
  tls:
    certResolver: letsencrypt-prod  # or letsencrypt-staging
```

### Method 2: Using Standard Kubernetes Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    traefik.ingress.kubernetes.io/router.entrypoints: "websecure"
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - myapp.example.com
      secretName: myapp-tls
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-service
                port:
                  number: 8080
```

## What Happens When You Create an Ingress

1. **Traefik** detects the new ingress resource
2. **Cert-Manager** automatically creates a certificate request to Let's Encrypt
3. **Let's Encrypt** validates ownership via DNS challenge
4. **Cert-Manager** stores the certificate in a Kubernetes secret
5. **External-DNS** creates a DNS A record in Route53 pointing to Traefik's LoadBalancer IP
6. Your application is now accessible at `https://myapp.example.com` with a valid certificate

## Accessing the Traefik Dashboard

The dashboard is automatically configured to be accessible at:
```
https://traefik.example.com
```

To view the Traefik dashboard on your local machine, you can port-forward:
```bash
kubectl port-forward -n kube-system svc/traefik 8080:8080
```

Then access it at: `http://localhost:8080/dashboard`

## Troubleshooting

### DNS Records Not Being Created
Check External-DNS logs:
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns -f
```

Common issues:
- IAM permissions not configured correctly
- Hosted zone ID is incorrect
- External-DNS can't access AWS credentials

### Certificates Not Being Created
Check Cert-Manager logs:
```bash
kubectl logs -n cert-manager -l app=cert-manager -f
```

Common issues:
- Let's Encrypt email is required
- Cert-Manager can't access Route53 for DNS challenge
- ClusterIssuer not found (check it exists with `kubectl get clusterissuers`)

### Traefik Service is Pending
```bash
kubectl get svc -n kube-system traefik
```

If the EXTERNAL-IP is pending:
- Check if your cloud provider supports LoadBalancer service type
- Use NodePort instead: `traefik_service_type = "NodePort"`

## Advanced Configuration

### Using NodePort Instead of LoadBalancer
```hcl
module "ingress" {
  # ...
  traefik_service_type = "NodePort"
}
```

### Custom Traefik Configuration
```hcl
module "ingress" {
  # ...
  traefik_values = [
    file("${path.module}/traefik-custom-values.yaml")
  ]
}
```

### Using Let's Encrypt Staging (For Testing)
```hcl
module "ingress" {
  # ...
  letsencrypt_environment = "staging"
  # Use "letsencrypt-staging" in your ingress annotations/specs
}
```

## Cleanup

To remove the ingress stack:
```bash
terraform destroy -target module.ingress
```

This will remove all ingresses, certificates, and DNS records created by this module.

## References

- [Traefik Documentation](https://doc.traefik.io)
- [External-DNS Documentation](https://github.com/kubernetes-sigs/external-dns)
- [Cert-Manager Documentation](https://cert-manager.io/docs)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
