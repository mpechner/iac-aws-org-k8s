# Adding a New App (Manual Guide)

This document explains how to add a new application so it is reachable over HTTPS with a browser-trusted certificate, without repeating the pitfalls we hit with nginx/Rancher/Traefik.

**Assumptions:** Stage 1 (1-infrastructure) and Stage 2 (2-applications) are already deployed. Traefik, cert-manager, and external-dns are running. Your app will be served on the **public** NLB (same as nginx, rancher, traefik) at a hostname like `myapp.dev.foobar.support`.

---

## 1. Critical Details (Why Things Broke Before)

Get these wrong and you get 404 or "Not secure":

| Requirement | Why |
|-------------|-----|
| **IngressRoute API** | Use `traefik.io/v1alpha1`, not `traefik.containo.us`. Traefik 3 only watches `traefik.io`. |
| **Cross-namespace** | IngressRoutes live in the `traefik` namespace but reference services in other namespaces (e.g. `myapp`). 1-infrastructure must set `providers.kubernetesCRD.allowCrossNamespace = true` (already set). |
| **Certificate + IngressRoute in `traefik`** | Create both the Certificate and the IngressRoute in the **traefik** namespace. TLS secret must be in `traefik` so Traefik can use it. |
| **DNS for new hostname** | Add the new hostname to the **public** Traefik service’s `external-dns.alpha.kubernetes.io/hostname` in 1-infrastructure so Route53 gets a record pointing to the NLB. |
| **Let’s Encrypt prod** | Use `letsencrypt-prod` (browser-trusted). Staging certs show "Not secure". |

---

## 2. Deploy Your App

Deploy your application in its own namespace (or an existing one): Deployment, Service, etc. Note:

- **Namespace** (e.g. `myapp`)
- **Service name** and **port** (e.g. `myapp`, port `80`)

Example (kubectl; adjust as needed):

```yaml
# myapp-deployment.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: myapp
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: your-image:tag
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: myapp
spec:
  selector:
    app: myapp
  ports:
    - port: 80
      targetPort: 80
```

```bash
kubectl apply -f myapp-deployment.yaml
```

---

## 3. Add DNS for the New Hostname

The public NLB must advertise your new hostname so external-dns creates a Route53 record.

**File:** `1-infrastructure/main.tf`  
**Resource:** `module "traefik"` → `values` → `service.annotations` → `external-dns.alpha.kubernetes.io/hostname`

Add your hostname to the comma-separated list:

```hcl
"external-dns.alpha.kubernetes.io/hostname" = "nginx.${var.route53_domain},traefik.${var.route53_domain},rancher.${var.route53_domain},myapp.${var.route53_domain}"
```

Then apply Stage 1:

```bash
cd deployments/rke-apps/1-infrastructure
terraform apply -auto-approve
```

Wait for external-dns to update Route53 (or restart the external-dns deployment). Verify:

```bash
dig +short myapp.dev.foobar.support
# Should return the same NLB IPs as nginx/traefik/rancher
```

---

## 4. Add TLS Certificate and IngressRoute (2-applications)

In **2-applications**, add two resources: a **Certificate** (cert-manager) and an **IngressRoute** (Traefik). Both must be in the **traefik** namespace and use **traefik.io/v1alpha1** for the IngressRoute.

Replace placeholders:

- `myapp` → your app’s logical name (used in resource names and TLS secret name).
- `myapp` → namespace where your Service lives.
- `myapp` → Service name.
- `80` → Service port.
- `myapp.${var.route53_domain}` → full hostname (e.g. `myapp.dev.foobar.support`).

**File:** `2-applications/main.tf`

**4a. Certificate (Let’s Encrypt prod)**

```hcl
resource "kubernetes_manifest" "myapp_cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "myapp-tls"
      namespace = "traefik"
    }
    spec = {
      secretName = "myapp-tls"
      dnsNames   = ["myapp.${var.route53_domain}"]
      issuerRef = {
        name  = "letsencrypt-${var.letsencrypt_environment}"
        kind  = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  }

  depends_on = [module.applications]
}
```

**4b. IngressRoute (HTTPS on 443)**

```hcl
resource "kubernetes_manifest" "myapp_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "myapp"
      namespace = "traefik"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match    = "Host(`myapp.${var.route53_domain}`) && PathPrefix(`/`)"
          kind     = "Rule"
          priority = 100
          services = [
            {
              name           = "myapp"
              namespace      = "myapp"
              port           = 80
              passHostHeader = true
            }
          ]
        }
      ]
      tls = {
        secretName = "myapp-tls"
      }
    }
  }

  depends_on = [kubernetes_manifest.myapp_cert]
}
```

Apply Stage 2:

```bash
cd deployments/rke-apps/2-applications
terraform apply -auto-approve
```

---

## 5. Optional: HTTP (80) Redirect to HTTPS

If you want `http://myapp.dev.foobar.support` to redirect to HTTPS, add your host to the existing redirect IngressRoute in `2-applications/main.tf`. Find the resource `kubernetes_manifest.redirect_http_to_https_route` and extend the `match` line:

```hcl
match = "Host(`rancher.${var.route53_domain}`) || Host(`traefik.${var.route53_domain}`) || Host(`myapp.${var.route53_domain}`)"
```

No need to add another service; the existing placeholder service is enough because the redirect middleware responds before forwarding.

---

## 6. Verification Checklist

1. **Certificate**
   ```bash
   kubectl get certificate -n traefik myapp-tls
   # READY should be True; issuer should be letsencrypt-prod
   ```

2. **IngressRoute**
   ```bash
   kubectl get ingressroute.v1alpha1.traefik.io -n traefik myapp
   ```

3. **DNS**
   ```bash
   dig +short myapp.dev.foobar.support
   ```

4. **Browser**
   - Open `https://myapp.dev.foobar.support`
   - Page should load and show secure (padlock). If it still shows "Not secure", hard refresh (Cmd+Shift+R / Ctrl+Shift+R) or try Incognito; ensure `letsencrypt_environment = "prod"` and cert is re-issued from prod.

---

## 7. Troubleshooting

| Symptom | Check |
|--------|--------|
| **404** | IngressRoute uses `traefik.io/v1alpha1` (not containo.us). Certificate and IngressRoute are in `traefik` namespace. 1-infrastructure has `providers.kubernetesCRD.allowCrossNamespace = true`. Service name/namespace/port match your app. |
| **Not secure** | Certificate `issuerRef.name` is `letsencrypt-prod`. Delete the TLS secret in `traefik` and let cert-manager re-issue; hard refresh or Incognito. |
| **DNS not resolving** | New hostname added to public Traefik service’s `external-dns.alpha.kubernetes.io/hostname` in 1-infrastructure and applied. Restart external-dns if needed. |
| **Certificate not Ready** | `kubectl describe certificate -n traefik myapp-tls` and cert-manager logs; fix DNS/Route53 if DNS-01 challenge fails. |

---

## 8. Summary

1. Deploy app (namespace, Deployment, Service).
2. In **1-infrastructure**: add `myapp.${var.route53_domain}` to the public Traefik service’s external-dns hostname; apply.
3. In **2-applications**: add Certificate `myapp-tls` and IngressRoute `myapp` in **traefik** namespace (API `traefik.io/v1alpha1`, entryPoint `websecure`, TLS secret `myapp-tls`, service in your app namespace); apply.
4. Wait for cert Ready and DNS; open `https://myapp.dev.foobar.support` and verify secure.

Using this pattern keeps routing and TLS consistent with nginx, rancher, and the Traefik dashboard and avoids the issues we fixed during initial setup.
