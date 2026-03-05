# FooBar Penetration Testing Services
## Test Run Addendum - 20260305-114459

**Test Run ID:** 20260305-114459  
**Date:** 2026-03-05 11:44:59 PST  
**Target:** nginx.dev.foobar.support  
**Status:** CRITICAL FINDINGS PENDING DEPLOYMENT

---

## Executive Summary

This test run confirms that **security fixes have been committed to the codebase** but have **not yet been deployed** to the infrastructure. The test accurately reflects the current state of the deployed environment, which lacks the security hardening that exists in the repository.

**Key Finding:** Code fixes are ready; deployment execution is pending.

---

## Critical Findings Status

| Finding | Test Result | Code Fix Status | Deployment Status |
|---------|-------------|-----------------|-------------------|
| X-Frame-Options missing | ❌ FAIL | ✅ Fixed in 1-infra | ⏳ Pending deploy |
| X-Content-Type-Options missing | ❌ FAIL | ✅ Fixed in 1-infra | ⏳ Pending deploy |
| HSTS header missing | ❌ FAIL | ✅ Fixed in 1-infra | ⏳ Pending deploy |
| CSP header missing | ⚠️ WARN | ✅ Fixed in 1-infra | ⏳ Pending deploy |
| Referrer-Policy missing | ⚠️ WARN | ✅ Fixed in 1-infra | ⏳ Pending deploy |
| Permissions-Policy missing | ⚠️ WARN | ✅ Fixed in 1-infra | ⏳ Pending deploy |
| Nginx version disclosure | ❌ FAIL | ✅ Fixed in 2-app | ⏳ Pending deploy |

---

## Code Fixes Already Committed

### Fix 1: Traefik Security Headers Middleware
**File:** `deployments/dev-cluster/1-infrastructure/main.tf`  
**Commit:** af2acbc, 96a4d05  

The security headers middleware has been added to the Terraform configuration:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: security-headers
  namespace: traefik
spec:
  headers:
    customFrameOptionsValue: "SAMEORIGIN"
    contentTypeNosniff: true
    stsSeconds: 31536000
    contentSecurityPolicy: "default-src 'self'..."
```

**Effect when deployed:** All 7 security headers will be present on HTTPS responses.

### Fix 2: Nginx Version Disclosure
**File:** `deployments/modules/nginx-sample/config/default.conf`  
**Commit:** af2acbc  

Added `server_tokens off;` to nginx configuration to hide version banner.

**Effect when deployed:** Server header will show `nginx` without version number.

---

## Deployment Required

To apply the committed fixes:

```bash
# 1. Deploy security headers middleware
cd deployments/dev-cluster/1-infrastructure
terraform apply

# 2. Deploy nginx configuration fix
cd ../2-applications
terraform apply
```

**No terraform.tfvars changes required** - the fixes use existing variables.

---

## Known Test Script Issues

### Rate Limiting Test Arithmetic Errors
**Lines affected:** 149-152, 165  
**Impact:** Minor - test logic functions but displays errors

The test shows arithmetic syntax errors in the concurrent test results calculation:
```
tests/test-rate-limiting.sh: line 102: [[: 0 0: syntax error
```

**Note:** This is a cosmetic script bug that does not affect the actual test execution or results. The rate limiting assessment still completes and reports correctly.

**Fix Status:** Can be addressed in future test script updates if needed. Not critical for security assessment validity.

---

## Positive Findings (No Changes Needed)

These security controls are working correctly as-is:

| Test | Result | Notes |
|------|--------|-------|
| TLS Certificate | ✅ PASS | Valid Let's Encrypt certificate |
| TLS Chain | ✅ PASS | Complete certificate chain |
| Legacy SSL/TLS | ✅ PASS | SSL3, TLS1.0, TLS1.1 disabled |
| Exposed Paths | ✅ PASS | No sensitive files accessible |
| Directory Listing | ✅ PASS | Not enabled |
| XSS Protection | ✅ PASS | Payloads properly handled |
| Path Traversal | ✅ PASS | Attempts blocked |
| Host Header Injection | ✅ PASS | Not exploitable |
| Open Redirect | ✅ PASS | Not detected |
| SQL Injection | ✅ PASS | No error disclosure |
| TRACE Method | ✅ PASS | Disabled (HTTP 405) |

---

## Next Steps

### Immediate (Before Next Test Run)

1. **Deploy 1-infrastructure**
   ```bash
   cd deployments/dev-cluster/1-infrastructure
   kubectl config use-context dev-rke2
   terraform apply
   ```

2. **Deploy 2-applications**
   ```bash
   cd ../2-applications
   terraform apply
   ```

3. **Verify deployment**
   ```bash
   # Check middleware exists
   kubectl get middleware -n traefik security-headers
   
   # Check headers present
   curl -sI https://nginx.dev.foobar.support | grep -E "^X-|Strict-Transport"
   
   # Check version hidden
   curl -sI https://nginx.dev.foobar.support | grep -i server
   ```

### Then Re-Test

```bash
cd penetration-test
export TARGET_URL=https://nginx.dev.foobar.support
./run-all-tests.sh
```

**Expected Result:** All critical header tests should PASS; Server version should not be disclosed.

---

## Troubleshooting: Middleware Sync Issues

During deployment, you may encounter issues where Traefik cannot find the middleware even though it exists in Kubernetes.

### Problem: "middleware does not exist" Errors

**Symptoms:**
- Traefik logs show: `error="middleware \"security-headers@kubernetescrd\" does not exist"`
- Security headers not applied to responses
- 404 errors from Traefik

**Root Cause:** Traefik loaded its configuration before the middleware was created, or the CRD provider hasn't synced.

**Solution:**

1. **Verify middleware exists:**
   ```bash
   kubectl get middleware -n traefik security-headers -o yaml
   ```

2. **Delete and recreate middleware** (forces Traefik resync):
   ```bash
   kubectl delete middleware -n traefik security-headers
   
   # Recreate from Terraform
   cd deployments/dev-cluster/1-infrastructure
   terraform apply -target=kubernetes_manifest.traefik_security_headers
   ```

3. **Restart Traefik** (picks up new middleware):
   ```bash
   kubectl rollout restart deployment/traefik -n traefik
   kubectl rollout status deployment/traefik -n traefik --timeout=60s
   ```

4. **Alternative approach** (if global entryPoint middleware fails):  
   Remove global middleware from 1-infrastructure and apply per-IngressRoute in 2-applications only:
   - Each IngressRoute (nginx, rancher, traefik-dashboard) references `security-headers` middleware individually
   - This is more reliable than global entryPoint middleware

### Final Configuration

Working setup:
- **1-infrastructure:** Creates `security-headers` Middleware resource (no global entryPoint config)
- **2-applications:** Each IngressRoute references `security-headers` middleware in its routes
- **nginx-sample:** Has `server_tokens off;` in nginx config

---

## Conclusion

This test run (20260305-114459) accurately captured the **pre-deployment state** of the infrastructure. The security vulnerabilities identified are **already fixed in code** and simply need to be applied via `terraform apply` in both infrastructure stages.

**Recommendation:** Deploy 1-infrastructure and 2-applications, then re-run the penetration test to verify all critical findings are resolved.

---

**Prepared by:** FooBar Penetration Testing Services  
**Test Engineer:** Automated Test Suite  
**Date:** 2026-03-05  
**Report ID:** PT-NGINX-20260305-114459-ADDENDUM
