# Deployment modules (shared across environments)

These modules are used by deployment stages (e.g. `dev-cluster/2-applications`) and are shared so that additional environments (e.g. `staging-cluster`, `prod-cluster`) can use the same code without duplication.

| Module | Purpose | Used by |
|--------|---------|---------|
| **ingress-applications** | ClusterIssuer, backend TLS, ingress scaffolding | `dev-cluster/2-applications` |
| **nginx-sample** | Sample app deployment + service | `dev-cluster/2-applications` |
| **tls-issue** | OpenVPN TLS cert (cert-manager + CronJob to Secrets Manager) | `dev-cluster/2-applications` |

From `deployments/<env>/2-applications`, reference with `source = "../../modules/<name>"`.
