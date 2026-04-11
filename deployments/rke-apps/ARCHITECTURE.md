# Dev-cluster architecture

Two-stage Terraform deployment (infrastructure → applications) with Traefik, automatic TLS, and DNS.

## High-level flow

```mermaid
flowchart LR
  subgraph Internet
    User
  end
  subgraph AWS
    subgraph Route53
      DNS["nginx / traefik / rancher\n.dev.foobar.support"]
    end
    subgraph Public NLB
      NLB[Traefik NLB\n:80, :443]
    end
    subgraph RKE2 cluster
      Traefik[Traefik\nIngressRoute CRD]
      Traefik --> Nginx[nginx-sample]
      Traefik --> Rancher[Rancher]
      Traefik --> Dashboard[api@internal]
    end
  end
  User --> DNS
  DNS --> NLB
  NLB --> Traefik
```

- **DNS:** external-DNS creates Route53 records for hostnames listed on the Traefik (public) service; all point to the same NLB.
- **TLS:** cert-manager issues Let's Encrypt (prod) certificates; secrets live in the `traefik` namespace; Traefik uses them for HTTPS.
- **Routing:** IngressRoutes (`traefik.io/v1alpha1`) in the `traefik` namespace reference backends in other namespaces (Traefik is configured with `allowCrossNamespace = true`).

## Two-stage deploy

| Stage | Purpose | Key resources |
|-------|---------|----------------|
| **1-infrastructure** | Install CRDs and shared infrastructure | Helm: Traefik, cert-manager, external-DNS, AWS LB controller. Traefik values: allowCrossNamespace, public NLB + external-dns hostnames. |
| **2-applications** | App-specific routing and certs | ClusterIssuer (Let's Encrypt), Certificate + IngressRoute per app (nginx, rancher, traefik-dashboard) in `traefik` namespace. |

Stage 2 depends on Stage 1 because Terraform validates CRDs at plan time; the CRDs are created by the Helm charts in Stage 1.

## Pattern for each app

1. **Certificate** (cert-manager) in namespace `traefik`, issuer `letsencrypt-prod`, secret name e.g. `myapp-tls`.
2. **IngressRoute** (Traefik) in namespace `traefik`, API `traefik.io/v1alpha1`, entryPoints `websecure`, TLS secret `myapp-tls`, service in the app’s namespace (e.g. `myapp`).

Do **not** use the applications module’s `ingresses` map for these; use explicit Certificate + IngressRoute so routing and TLS stay consistent. See [ADDING-NEW-APP.md](ADDING-NEW-APP.md).

## Key configuration

- **Traefik:** `providers.kubernetesCRD.allowCrossNamespace = true` (1-infrastructure) so IngressRoutes in `traefik` can reference services in `nginx-sample`, `cattle-system`, etc.
- **Public NLB:** One Traefik LoadBalancer service; `external-dns.alpha.kubernetes.io/hostname` = comma-separated list of hostnames (nginx, traefik, rancher; add new apps here for DNS).
- **Internal NLB:** Optional; no external-dns hostnames to avoid duplicate DNS; use for VPN-only access if needed later.

## See also

- [ADDING-NEW-APP.md](ADDING-NEW-APP.md) – step-by-step for new apps
- [1-infrastructure/README.md](1-infrastructure/README.md) – Stage 1 details
- [2-applications/README.md](2-applications/README.md) – Stage 2 details
- [docs/SHOWCASE-RECOMMENDATIONS.md](../../docs/SHOWCASE-RECOMMENDATIONS.md) – further doc and refactor ideas
