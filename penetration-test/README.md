# Penetration Testing Suite

**Company:** FooBar Penetration Testing Services  
**Assessment Date:** 2026-03-05  
**Target:** nginx.dev.foobar.support  
**Scope:** External infrastructure assessment of the Nginx ingress endpoint

## Executive Summary

This penetration testing suite validates the security posture of the Nginx web server deployment within the Kubernetes ingress stack. The tests verify:

- HTTP security headers configuration
- TLS/SSL implementation strength
- Information disclosure vulnerabilities
- Common web attack vectors (XSS, clickjacking, MIME sniffing)
- Server hardening and version disclosure

## Test Environment

```bash
# Set target URL
export TARGET_URL="https://nginx.dev.foobar.support"
export TARGET_IP="<NLB_IP_FROM_DIG>"  # Optional for network-level tests
```

## Quick Start

### Single Site Testing

```bash
# Run all tests against default site (nginx.dev.foobar.support)
./run-all-tests.sh

# Run specific test category against a specific site
export TARGET_URL="https://nginx.dev.foobar.support"
./tests/test-headers.sh
./tests/test-tls.sh
./tests/test-info-disclosure.sh
```

### Multi-Site Testing

```bash
# Create a sites file (one URL per line)
cat > sites.txt << 'EOF'
# Public site
https://nginx.dev.foobar.support

# Internal sites (require VPN)
https://traefik.dev.foobar.support
https://rancher.dev.foobar.support
EOF

# Run tests against all sites
./run-all-tests.sh sites.txt

# Or use default sites file (sites.txt)
./run-all-tests.sh
```

**Output Structure:**
```
penetration-run/20260305-121457/
├── MASTER-SUMMARY-20260305-121457.txt    # Overall summary
├── security-assessment-nginx_dev_foobar_support-20260305-121457.txt
├── security-assessment-traefik_dev_foobar_support-20260305-121457.txt
├── security-assessment-rancher_dev_foobar_support-20260305-121457.txt
└── test-nginx_dev_foobar_support.log
```

## Test Categories

### 1. Security Headers Test (`tests/test-headers.sh`)
Validates presence and correctness of HTTP security headers:
- X-Frame-Options (clickjacking protection)
- X-Content-Type-Options (MIME sniffing protection)
- X-XSS-Protection (legacy XSS filter)
- Strict-Transport-Security (HSTS)
- Content-Security-Policy
- Referrer-Policy

### 2. TLS/SSL Configuration Test (`tests/test-tls.sh`)
Validates TLS implementation:
- Certificate validity and chain
- Protocol versions (TLS 1.2+ required)
- Cipher suite strength
- Certificate transparency
- OCSP stapling

### 3. Information Disclosure Test (`tests/test-info-disclosure.sh`)
Checks for information leakage:
- Server version banners
- Error page information leakage
- Directory listing enabled
- Backup files exposed
- Debug endpoints accessible

### 4. Web Attack Vectors Test (`tests/test-attack-vectors.sh`)
Tests common attack mitigations:
- XSS protection (reflected and stored)
- CSRF token validation
- SQL injection attempts (safe simulation)
- Path traversal attempts

### 5. Rate Limiting Test (`tests/test-rate-limiting.sh`)
Validates DoS protection:
- Connection rate limiting
- Request throttling
- Ban duration verification

## Test Results Interpretation

**PASS:** Security control is properly implemented and effective  
**FAIL:** Security control is missing, misconfigured, or ineffective  
**WARN:** Recommendation for improvement, not a critical vulnerability  
**INFO:** Informational finding, no immediate action required  

## Report Templates

- `reports/template-executive-summary.md` - High-level findings for management
- `reports/template-technical-findings.md` - Detailed technical findings
- `reports/template-remediation.md` - Remediation guidance

## Tools Used

- `curl` - HTTP request testing
- `openssl` - TLS/SSL analysis
- `nmap` - Network scanning (optional)
- `nikto` - Web vulnerability scanner (optional)

## AWS Penetration Testing Policy Compliance

**Important:** These tests comply with [AWS Penetration Testing Policy](https://aws.amazon.com/security/penetration-testing/) for resources you own:

- ✅ **Permitted without approval:** Testing EC2 instances, NLBs, and Route53 records in your own AWS account
- ✅ **Low volume:** Tests use minimal requests (single-digit to ~25 requests max) - well below abuse thresholds
- ✅ **Non-exploitative:** Tests validate security controls without actual exploitation
- ✅ **No DoS testing:** Rate limiting test uses gentle load (20 sequential + 5 concurrent requests)

**Prohibited activities (NOT performed by these tests):**
- DNS zone walking on Route53
- Resource exhaustion or volumetric DoS attacks
- Testing other AWS customers' resources
- Testing AWS services themselves (only your application layer)

**Always ensure:**
1. You own the target infrastructure (your NLB, your domain)
2. You have authorization if testing shared/multi-tenant resources
3. Tests are run against your own account only

## Disclaimer

These tests are designed to be non-destructive and safe for production environments. However, always obtain proper authorization before testing any system you do not own. The tests do not exploit vulnerabilities - they only validate the presence and effectiveness of security controls.

---

**Classification:** Confidential - Client Use Only  
**Report ID:** PT-NGINX-20260305-001
