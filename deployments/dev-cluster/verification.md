# Let's Encrypt TLS 1.3 Verification - dev.foobar.support

**Status**: ✅ Ready for Deployment  
**Date**: January 18, 2026  
**Domain**: dev.foobar.support  
**Zone ID**: Z06437531SIUA7T3WCKTM

---

## Configuration Summary

### ✅ Route53 Configuration - VERIFIED

```json
{
    "Id": "/hostedzone/Z06437531SIUA7T3WCKTM",
    "Name": "dev.foobar.support.",
    "Config": {
        "Comment": "Delegated subdomain hosted zone in dev account",
        "PrivateZone": false
    },
    "ResourceRecordSetCount": 2
}
```

- **Zone ID**: Z06437531SIUA7T3WCKTM ✅
- **Domain**: dev.foobar.support ✅
- **Type**: Public Hosted Zone ✅
- **Status**: Active with 2 records (NS, SOA) ✅

### ✅ IAM Permissions - CONFIGURED

Route53 permissions have been added to both RKE server and agent nodes:

**Server Nodes**: `RKE-cluster/modules/server/iam.tf` (Lines 36-41)
```hcl
resource "aws_iam_role_policy" "rke_server_route53" {
  name = "${var.cluster_name}-rke-server-route53-policy"
  role = aws_iam_role.rke_server.id
  
  policy = file("${path.module}/policies/server-route53-policy.json")
}
```

**Agent Nodes**: `RKE-cluster/modules/agent/iam.tf` (Lines 36-41)
```hcl
resource "aws_iam_role_policy" "rke_agent_route53" {
  name = "${var.cluster_name}-rke-agent-route53-policy"
  role = aws_iam_role.rke_agent.id
  
  policy = file("${path.module}/policies/agent-route53-policy.json")
}
```

**Permissions Granted**:
- `route53:ChangeResourceRecordSets` ✅
- `route53:ListHostedZones` ✅
- `route53:ListResourceRecordSets` ✅
- `route53:GetChange` ✅
- `route53:ListHostedZonesByName` ✅

### ✅ Let's Encrypt Configuration - SET

**Email**: mikey@mikey.com  
**Environment**: staging (configured in `terraform.tfvars`)  
**ACME Server**: Let's Encrypt Staging v2  
**Challenge Type**: DNS-01 (via Route53)

### ✅ Terraform Configuration - COMPLETE

**File**: `deployments/dev-cluster/terraform.tfvars`
```hcl
route53_zone_id         = "Z06437531SIUA7T3WCKTM"
route53_domain          = "dev.foobar.support"
letsencrypt_email       = "mikey@mikey.com"
letsencrypt_environment = "staging"
```

---

## Component Status

### 1. Cert-Manager ✅
- **Module**: `modules/ingress/cert-manager/`
- **Function**: Automates TLS certificate lifecycle (issue, renew, revoke)
- **Provider**: Let's Encrypt ACME v2
- **Challenge**: DNS-01 via Route53
- **TLS Support**: TLS 1.3 compatible certificates

### 2. External-DNS ✅
- **Module**: `modules/ingress/external-dns/`
- **Function**: Automatically creates Route53 DNS records from Kubernetes Ingress
- **Provider**: AWS Route53
- **Zone**: Z06437531SIUA7T3WCKTM (dev.foobar.support)
- **Policy**: upsert-only (safe mode)

### 3. Traefik Ingress Controller ✅
- **Module**: `modules/ingress/traefik/`
- **Function**: Routes external traffic to Kubernetes services
- **Ports**: 80 (HTTP), 443 (HTTPS)
- **TLS**: Native TLS 1.3 support
- **Dashboard**: Enabled at traefik.dev.foobar.support

### 4. Backend TLS Infrastructure ✅
- **Function**: End-to-end encryption (Traefik → Pod)
- **CA**: Cert-manager internal CA (per namespace)
- **Certificates**: Automated issuance for service endpoints
- **Transport**: ServersTransport with CA verification

### 5. ClusterIssuers ✅
**Staging**: `letsencrypt-staging`
- Server: https://acme-staging-v02.api.letsencrypt.org/directory
- Rate Limits: Relaxed (for testing)
- Certificates: Self-signed by fake CA (browser warning expected)

**Production**: `letsencrypt-prod` (deploy after staging success)
- Server: https://acme-v02.api.letsencrypt.org/directory
- Rate Limits: 50 certs/week per domain
- Certificates: Trusted by all browsers

---

## Prerequisites Verification

Run these commands before deploying:

### 1. Verify Route53 Hosted Zone

```bash
# Check zone exists and is public
aws route53 list-hosted-zones-by-name --dns-name dev.foobar.support

# Expected output:
# - Id: Z06437531SIUA7T3WCKTM
# - PrivateZone: false
```

### 2. Verify DNS Delegation

```bash
# Check nameservers are properly delegated from parent domain
dig NS dev.foobar.support

# Should return 4 AWS nameservers:
# - ns-xxxx.awsdns-xx.org
# - ns-xxxx.awsdns-xx.co.uk
# - ns-xxxx.awsdns-xx.com
# - ns-xxxx.awsdns-xx.net
```

### 3. Verify RKE Cluster is Running

```bash
# Check cluster nodes are up
kubectl get nodes

# Expected output:
# NAME                         STATUS   ROLE    AGE   VERSION
# ip-xxx-xxx-xxx-xxx.us-west-2 Ready    server  Xd    vX.XX.X
# ip-xxx-xxx-xxx-xxx.us-west-2 Ready    agent   Xd    vX.XX.X
```

### 4. Verify IAM Roles Attached

```bash
# Get instance profile from a running node
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*rke-server*" \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
  --output text

# Verify Route53 policy is attached
aws iam list-role-policies --role-name <ROLE_NAME> | grep route53
```

### 5. Verify Kubeconfig Access

```bash
# Check current context
kubectl config current-context

# Test access
kubectl get namespaces
```

---

## Deployment Instructions

### Step 1: Initialize Terraform

```bash
cd /Users/mpechner/dev/tf_take2/deployments/dev-cluster

terraform init
```

**Expected Output**:
```
Initializing modules...
Initializing provider plugins...
- hashicorp/kubernetes
- hashicorp/helm
- hashicorp/aws

Terraform has been successfully initialized!
```

### Step 2: Review Deployment Plan

```bash
terraform plan
```

**What Will Be Created**:
- Cert-manager Helm release (namespace: cert-manager)
- External-DNS Helm release (namespace: kube-system)
- Traefik Helm release (namespace: kube-system)
- ClusterIssuer: letsencrypt-staging
- Namespace: nginx-sample
- Backend TLS infrastructure (Issuer, CA cert, backend cert)
- ServersTransport: backend-tls
- Nginx Deployment (3 replicas, HTTPS on port 443)
- Nginx Service (ClusterIP, port 443)
- Nginx ConfigMaps (HTML, Nginx config)
- Ingress: nginx-sample (www.dev.foobar.support)

**Resources**: ~25-30 resources will be created

### Step 3: Deploy Infrastructure

```bash
terraform apply
```

**Duration**: 3-5 minutes

**Confirmation**: Type `yes` when prompted

### Step 4: Wait for Pods to Start

```bash
# Monitor cert-manager pods (should be Running within 60 seconds)
kubectl get pods -n cert-manager -w

# Monitor ingress controller pods
kubectl get pods -n kube-system | grep -E 'traefik|external-dns'

# Monitor nginx-sample application
kubectl get pods -n nginx-sample -w
```

**All pods should reach `Running` status with `READY 1/1`**

---

## Certificate Verification

### Step 1: Verify ClusterIssuer Created

```bash
kubectl get clusterissuers

# Expected output:
# NAME                  READY   AGE
# letsencrypt-staging   True    Xs
```

```bash
# Check ClusterIssuer details
kubectl describe clusterissuer letsencrypt-staging

# Should show:
# - ACME Server: staging-v02.api.letsencrypt.org
# - Email: mikey@mikey.com
# - DNS01 Solver: route53
# - Status: Ready
```

### Step 2: Monitor Certificate Issuance

```bash
# Watch certificate creation (takes 2-5 minutes)
kubectl get certificate -n nginx-sample -w

# Expected progression:
# nginx-sample-tls   False   Issuing...    0s
# nginx-sample-tls   False   Issuing...    30s
# nginx-sample-tls   True    Ready         120s
```

```bash
# Check certificate details
kubectl describe certificate nginx-sample-tls -n nginx-sample

# Look for:
# - Status: Ready
# - Message: Certificate is up to date and has not expired
# - Not After: <expiration date>
```

### Step 3: Verify Certificate Secret Created

```bash
# Check TLS secret exists
kubectl get secret -n nginx-sample | grep tls

# Expected output:
# nginx-sample-tls           kubernetes.io/tls    2      Xm
# nginx-sample-backend-tls   kubernetes.io/tls    2      Xm
```

```bash
# Inspect certificate in secret
kubectl get secret nginx-sample-tls -n nginx-sample -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text

# Verify:
# - Issuer: (STAGING) Fake LE Intermediate X1
# - Subject: CN=www.dev.foobar.support
# - Validity: 90 days
# - DNS Names: www.dev.foobar.support
```

### Step 4: Verify DNS Record Created

```bash
# External-DNS should auto-create A/CNAME record
aws route53 list-resource-record-sets \
  --hosted-zone-id Z06437531SIUA7T3WCKTM \
  --query "ResourceRecordSets[?Name=='www.dev.foobar.support.']"

# Should show A record pointing to Traefik LoadBalancer IP
```

```bash
# Test DNS resolution
nslookup www.dev.foobar.support

# Should return an IP address (Traefik LoadBalancer)
```

```bash
# Alternative DNS test
dig www.dev.foobar.support +short

# Should return an IP address
```

### Step 5: Verify Ingress Status

```bash
kubectl get ingress -n nginx-sample

# Expected output:
# NAME           CLASS     HOSTS                      ADDRESS         PORTS     AGE
# nginx-sample   traefik   www.dev.foobar.support     XX.XX.XX.XX     80, 443   Xm
```

```bash
# Check ingress annotations
kubectl get ingress nginx-sample -n nginx-sample -o yaml | grep annotations -A 5

# Should show:
# - cert-manager.io/cluster-issuer: letsencrypt-staging
# - traefik.ingress.kubernetes.io/router.entrypoints: websecure
# - traefik.ingress.kubernetes.io/service.serversscheme: https
```

---

## TLS 1.3 Verification

### Test 1: OpenSSL TLS 1.3 Connection

```bash
# Test TLS 1.3 connection explicitly
openssl s_client -connect www.dev.foobar.support:443 -tls1_3 -servername www.dev.foobar.support

# Look for:
# - Protocol: TLSv1.3
# - Cipher: TLS_AES_256_GCM_SHA384 or similar
# - Verify return code: 0 (ok) or 21 (self-signed - expected for staging)
```

**Expected Output (key lines)**:
```
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
Protocol  : TLSv1.3
Cipher    : TLS_AES_256_GCM_SHA384
```

### Test 2: Curl with Protocol Verification

```bash
# Test HTTPS with verbose output
curl -vI https://www.dev.foobar.support 2>&1 | grep -E 'SSL|TLS'

# Expected output:
# * TLSv1.3 (OUT), TLS handshake...
# * SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
```

```bash
# Test with curl (ignore cert error for staging)
curl -k -I https://www.dev.foobar.support

# Should return HTTP 200 OK
```

### Test 3: Certificate Details Inspection

```bash
# Get full certificate chain
echo | openssl s_client -connect www.dev.foobar.support:443 -servername www.dev.foobar.support 2>/dev/null | openssl x509 -noout -text

# Verify:
# - Subject: CN=www.dev.foobar.support
# - Issuer: CN=(STAGING) Fake LE Intermediate X1
# - Signature Algorithm: sha256WithRSAEncryption
# - Public Key: RSA 2048 bit
# - Validity: 90 days
```

### Test 4: Browser Testing

1. Open browser: https://www.dev.foobar.support
2. **Expected**: Certificate warning (staging cert is self-signed)
3. Click "Advanced" → "Proceed anyway"
4. **Expected**: Nginx sample page loads
5. Check certificate in browser:
   - Issuer: (STAGING) Fake LE Intermediate X1
   - Subject: www.dev.foobar.support
   - Valid for 90 days

### Test 5: End-to-End TLS Verification

```bash
# Check backend TLS certificate
kubectl get certificate -n nginx-sample

# Should show both frontend and backend certs:
# nginx-sample-tls           True    <age>
# nginx-sample-backend-tls   True    <age>
```

```bash
# Verify ServersTransport exists
kubectl get servertransport -n nginx-sample

# Expected output:
# NAME          AGE
# backend-tls   Xm
```

---

## Troubleshooting

### Issue: Certificate Stuck in "Issuing" State

**Symptoms**:
```bash
kubectl get certificate -n nginx-sample
# nginx-sample-tls   False   Issuing...   5m
```

**Diagnosis**:
```bash
# Check certificate request
kubectl get certificaterequest -n nginx-sample
kubectl describe certificaterequest <name> -n nginx-sample

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# Check for DNS validation challenges
kubectl get challenges -n nginx-sample
kubectl describe challenge <name> -n nginx-sample
```

**Common Causes**:
1. **DNS not propagating**: Wait 5-10 minutes
2. **Route53 permissions missing**: Verify IAM policy attached
3. **Incorrect hosted zone ID**: Check `terraform.tfvars`
4. **Rate limit hit**: Switch to staging or wait

**Solution**:
```bash
# Delete certificate to retry
kubectl delete certificate nginx-sample-tls -n nginx-sample

# Terraform will recreate it
terraform apply
```

### Issue: DNS Record Not Created

**Symptoms**:
```bash
nslookup www.dev.foobar.support
# Server can't find www.dev.foobar.support: NXDOMAIN
```

**Diagnosis**:
```bash
# Check External-DNS logs
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns --tail=50

# Check for errors like:
# - "AccessDenied" → IAM permissions missing
# - "InvalidHostedZoneId" → Wrong zone ID
```

**Solution**:
```bash
# Verify ingress has hostname
kubectl get ingress nginx-sample -n nginx-sample -o yaml | grep host

# Restart External-DNS
kubectl rollout restart deployment external-dns -n kube-system

# Wait 2-3 minutes and check Route53
aws route53 list-resource-record-sets --hosted-zone-id Z06437531SIUA7T3WCKTM
```

### Issue: IAM Permission Errors

**Symptoms**:
```
Error: AccessDenied when calling Route53 API
```

**Diagnosis**:
```bash
# Check node IAM role
aws ec2 describe-instances --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn'

# List attached policies
aws iam list-role-policies --role-name <role-name>

# Verify route53 policy exists
aws iam get-role-policy --role-name <role-name> --policy-name <policy-name>
```

**Solution**:
If route53 policy is missing, the RKE cluster nodes need to be redeployed with the updated IAM roles:
```bash
cd /Users/mpechner/dev/tf_take2/RKE-cluster/dev-cluster/ec2
terraform apply
```

### Issue: Let's Encrypt Rate Limited

**Symptoms**:
```
Error: urn:ietf:params:acme:error:rateLimited
```

**Solution**:
1. **Using production**: Switch to staging
   ```hcl
   # terraform.tfvars
   letsencrypt_environment = "staging"
   ```

2. **Using staging**: Already rate-limited (rare)
   - Wait 1 hour
   - Use different subdomain (e.g., test.dev.foobar.support)

3. **Rate Limits**:
   - Production: 50 certs/week per domain
   - Staging: 30,000 certs/week per domain

### Issue: TLS Handshake Errors

**Symptoms**:
```bash
curl https://www.dev.foobar.support
# SSL: certificate verify failed
```

**For Staging** (Expected):
```bash
# Use -k to ignore cert verification
curl -k https://www.dev.foobar.support
```

**For Production** (Not Expected):
```bash
# Check certificate issuer
echo | openssl s_client -connect www.dev.foobar.support:443 2>/dev/null | grep "Issuer:"

# Should show: Let's Encrypt Authority (not staging)
```

### Issue: Backend TLS Certificate Not Created

**Symptoms**:
```bash
kubectl get certificate -n nginx-sample
# Only nginx-sample-tls exists, no backend cert
```

**Diagnosis**:
```bash
# Check backend issuer
kubectl get issuer -n nginx-sample

# Check CA certificate
kubectl get certificate -n nginx-sample
kubectl get secret backend-ca-secret -n nginx-sample
```

**Solution**:
```bash
# Recreate backend TLS infrastructure
terraform taint 'module.ingress.kubernetes_manifest.backend_ca_issuer["nginx-sample"]'
terraform apply
```

---

## Production Migration

Once staging certificates work successfully, migrate to production:

### Step 1: Update Configuration

```bash
cd /Users/mpechner/dev/tf_take2/deployments/dev-cluster

# Edit terraform.tfvars
# Change: letsencrypt_environment = "staging"
# To:     letsencrypt_environment = "prod"
```

```hcl
# terraform.tfvars (updated)
route53_zone_id         = "Z06437531SIUA7T3WCKTM"
route53_domain          = "dev.foobar.support"
letsencrypt_email       = "mikey@mikey.com"
letsencrypt_environment = "prod"  # ← Changed to prod
```

### Step 2: Apply Changes

```bash
terraform apply

# Review changes:
# - ClusterIssuer "letsencrypt-prod" will be created
# - ClusterIssuer "letsencrypt-staging" will remain (for fallback)
```

### Step 3: Update Ingress to Use Production Issuer

The ingress is configured dynamically, so it will automatically reference `letsencrypt-prod`:
```hcl
# In main.tf, this evaluates to "letsencrypt-prod"
cluster_issuer = "letsencrypt-${var.letsencrypt_environment}"
```

### Step 4: Delete Staging Certificate

```bash
# Force certificate recreation with production issuer
kubectl delete certificate nginx-sample-tls -n nginx-sample

# Cert-manager will automatically recreate it with production issuer
# Wait 5-10 minutes
kubectl get certificate -n nginx-sample -w
```

### Step 5: Verify Production Certificate

```bash
# Check certificate is from Let's Encrypt production
echo | openssl s_client -connect www.dev.foobar.support:443 -servername www.dev.foobar.support 2>/dev/null | openssl x509 -noout -issuer

# Expected: Issuer: C=US, O=Let's Encrypt, CN=R3
# NOT: (STAGING) Fake LE Intermediate X1
```

### Step 6: Browser Verification

1. Open: https://www.dev.foobar.support
2. **Expected**: Valid green lock, no warnings
3. Click lock icon → Certificate details
4. **Verify**:
   - Issuer: Let's Encrypt (R3)
   - Subject: www.dev.foobar.support
   - Valid: Yes (green checkmark)
   - TLS Version: TLS 1.3

### Production Rate Limits

**Be Aware**:
- **50 certificates per registered domain per week**
- **5 duplicate certificates per week** (same domains)
- Errors are costly, test in staging first

**Best Practices**:
- Always test in staging first
- Don't create/delete certificates repeatedly
- Monitor certificate expiration (auto-renewal at 30 days)

---

## Success Checklist

- [ ] Route53 hosted zone verified (Z06437531SIUA7T3WCKTM)
- [ ] DNS delegation configured and tested
- [ ] IAM permissions attached to RKE nodes
- [ ] `terraform.tfvars` created with correct values
- [ ] Terraform initialized successfully
- [ ] Terraform plan reviewed (no errors)
- [ ] Terraform apply completed successfully
- [ ] Cert-manager pods running (3/3)
- [ ] External-DNS pod running
- [ ] Traefik pods running
- [ ] ClusterIssuer created (letsencrypt-staging)
- [ ] Certificate issued and ready (nginx-sample-tls)
- [ ] DNS record created (www.dev.foobar.support)
- [ ] Ingress shows ADDRESS (Traefik LoadBalancer IP)
- [ ] HTTPS accessible with curl -k
- [ ] TLS 1.3 confirmed with OpenSSL
- [ ] Backend TLS certificates created
- [ ] Nginx sample site loads in browser
- [ ] (Optional) Migrated to production certificates
- [ ] (Optional) Browser shows valid certificate

---

## Additional Resources

- **Detailed Setup Guide**: `../../modules/ingress/LETS_ENCRYPT_SETUP.md`
- **Ingress Module README**: `../../modules/ingress/README.md`
- **Example Ingress**: `../../modules/ingress/example-ingress.yaml`
- **Terraform Variables**: `./variables.tf`
- **Example Configuration**: `./example.tfvars`

## Quick Reference Commands

```bash
# Check all components
kubectl get pods -n cert-manager
kubectl get pods -n kube-system | grep -E 'traefik|external-dns'
kubectl get pods -n nginx-sample

# Check certificates
kubectl get clusterissuers
kubectl get certificates --all-namespaces
kubectl get ingress --all-namespaces

# Monitor in real-time
watch -n 2 'kubectl get certificates -n nginx-sample && kubectl get pods -n nginx-sample'

# Test HTTPS
curl -k -I https://www.dev.foobar.support
openssl s_client -connect www.dev.foobar.support:443 -tls1_3

# Check DNS
nslookup www.dev.foobar.support
dig www.dev.foobar.support +short

# View logs
kubectl logs -n cert-manager -l app=cert-manager -f
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns -f
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik -f
```

---

**Document Version**: 1.0  
**Last Updated**: January 18, 2026  
**Verified By**: Terraform Configuration Analysis
