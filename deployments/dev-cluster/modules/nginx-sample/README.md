# Nginx Sample Site Module

This module deploys an nginx web server with a sample landing page. **End-to-end TLS is managed by the ingress module**, not this module.

## Features

- Custom HTML landing page (templated)
- HTTPS listener on port 443
- Health check endpoint (`/health`)
- Configurable replica count
- Expects backend TLS certificate from ingress module

## Architecture

```
Ingress Module:
  - Creates backend TLS certificate
  - Creates ServersTransport
  - Creates Ingress with backend HTTPS

Nginx Module:
  - Deployment (listens on 443, mounts certificate)
  - Service (port 443)
  - HTML content (ConfigMap)
```

## Usage

```hcl
# In deployments/dev-cluster/main.tf

# 1. Ingress module creates TLS cert and ingress
module "ingress" {
  source = "../../modules/ingress"
  
  ingresses = {
    nginx-sample = {
      namespace          = "nginx-sample"
      host               = "www.dev.foobar.support"
      service_name       = "nginx-sample"
      service_port       = 443
      cluster_issuer     = "letsencrypt-staging"
      backend_tls_enabled = true  # Default
    }
  }
}

# 2. Nginx module creates deployment/service
module "nginx_sample" {
  source = "./modules/nginx-sample"

  namespace   = "nginx-sample"
  environment = "dev"
  domain      = "dev.foobar.support"
  hostname    = "www.dev.foobar.support"

  depends_on = [module.ingress]
}
```

## Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `namespace` | string | `"nginx-sample"` | Kubernetes namespace |
| `create_namespace` | bool | `true` | Whether to create the namespace |
| `environment` | string | `"dev"` | Environment name (shown on page) |
| `domain` | string | required | Base domain (e.g., "dev.foobar.support") |
| `hostname` | string | required | Full hostname (e.g., "www.dev.foobar.support") |
| `replicas` | number | `2` | Number of nginx replicas |
| `labels` | map(string) | `{}` | Additional labels for all resources |

## Outputs

| Name | Description |
|------|-------------|
| `namespace` | Namespace where nginx is deployed |
| `service_name` | Name of the nginx service |
| `service_port` | Port of the nginx service (443) |
| `hostname` | Hostname of the site |
| `url` | Full URL of the site |

## Files

```
nginx-sample/
├── main.tf              # Kubernetes resources
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── README.md            # This file
└── site/
    └── index.html.tftpl # HTML template
```

## Backend Certificate

The backend TLS certificate is **created by the ingress module** at:
- Secret name: `{service_name}-backend-tls` (e.g., `nginx-sample-backend-tls`)
- Managed by: cert-manager (via ingress module)
- Auto-renewed: 30 days before expiration

The nginx deployment mounts this certificate from the secret.

## Customization

### Custom HTML

Edit `site/index.html.tftpl` to customize the landing page. Available template variables:

- `${domain}` - Base domain
- `${hostname}` - Full hostname
- `${environment}` - Environment name
- `${namespace}` - Kubernetes namespace
- `${tls_enabled}` - Always true

### Labels

```hcl
module "nginx_sample" {
  # ...
  
  labels = {
    "team" = "platform"
    "app.kubernetes.io/component" = "frontend"
  }
}
```

## Requirements

- Kubernetes cluster with Traefik ingress controller
- **Ingress module must be deployed first** (creates backend TLS)
- Cert-manager installed
- Terraform >= 1.3
- Providers:
  - hashicorp/kubernetes >= 2.23
