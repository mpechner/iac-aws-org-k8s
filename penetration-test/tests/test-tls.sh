#!/bin/bash
# SecureGuard PT - TLS/SSL Configuration Assessment
# Validates TLS implementation strength

set -e

TARGET_URL="${TARGET_URL:-https://nginx.dev.foobar.support}"
TARGET_HOST=$(echo "$TARGET_URL" | sed -E 's|https?://||' | cut -d'/' -f1)
TARGET_PORT=443

echo "=== TLS/SSL Configuration Assessment ==="
echo "Target: $TARGET_HOST:$TARGET_PORT"
echo ""

# Test 1: Certificate validity
echo "[TEST] Checking certificate validity..."
if echo | openssl s_client -connect "$TARGET_HOST:$TARGET_PORT" -servername "$TARGET_HOST" 2>/dev/null | openssl x509 -noout -checkend 0 > /dev/null 2>&1; then
    echo "[PASS] Certificate is valid and not expired"
else
    echo "[FAIL] Certificate is expired or invalid"
fi

# Test 2: Certificate chain
echo ""
echo "[TEST] Checking certificate chain..."
chain_depth=$(echo | openssl s_client -connect "$TARGET_HOST:$TARGET_PORT" -servername "$TARGET_HOST" -showcerts 2>/dev/null | grep -c "BEGIN CERTIFICATE" || echo 0)
if [[ $chain_depth -ge 2 ]]; then
    echo "[PASS] Certificate chain complete ($chain_depth certificates)"
else
    echo "[WARN] Certificate chain may be incomplete ($chain_depth certificate found)"
fi

# Test 3: TLS version support
echo ""
echo "[TEST] Checking TLS version support..."

# Check TLS 1.2
tls12_output=$(echo | timeout 5 openssl s_client -connect "$TARGET_HOST:$TARGET_PORT" -tls1_2 2>/dev/null)
tls12_supported=$(echo "$tls12_output" | grep -c "Verification" || echo 0)
tls12_supported=$(echo "$tls12_supported" | tr -d '\n')
if [[ "$tls12_supported" -gt 0 ]]; then
    echo "[PASS] TLS 1.2 is supported"
else
    echo "[FAIL] TLS 1.2 is NOT supported (required)"
fi

# Check TLS 1.3
tls13_output=$(echo | timeout 5 openssl s_client -connect "$TARGET_HOST:$TARGET_PORT" -tls1_3 2>/dev/null)
tls13_supported=$(echo "$tls13_output" | grep -c "Verification" || echo 0)
tls13_supported=$(echo "$tls13_supported" | tr -d '\n')
if [[ "$tls13_supported" -gt 0 ]]; then
    echo "[PASS] TLS 1.3 is supported (modern)"
else
    echo "[INFO] TLS 1.3 not available (acceptable if TLS 1.2 is enabled)"
fi

# Check for legacy SSL/TLS versions (should fail)
echo ""
echo "[TEST] Checking for legacy SSL/TLS versions (should be disabled)..."

for version in ssl3 tls1 tls1_1; do
    if echo | timeout 5 openssl s_client -connect "$TARGET_HOST:$TARGET_PORT" "-$version" 2>/dev/null | grep -q "Cipher.*:"; then
        echo "[FAIL] $version is ENABLED (security risk - deprecated protocol)"
    else
        echo "[PASS] $version is disabled"
    fi
done

# Test 4: Certificate details
echo ""
echo "[TEST] Checking certificate details..."
cert_info=$(echo | openssl s_client -connect "$TARGET_HOST:$TARGET_PORT" -servername "$TARGET_HOST" 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null)
if [[ -n "$cert_info" ]]; then
    echo "[INFO] Certificate Information:"
    echo "$cert_info" | while read line; do
        echo "       $line"
    done
fi

# Test 5: Certificate transparency
echo ""
echo "[TEST] Checking for Certificate Transparency (CT)..."
ct_headers=$(echo | timeout 5 openssl s_client -connect "$TARGET_HOST:$TARGET_PORT" -servername "$TARGET_HOST" -tlsextdebug 2>&1 | grep -i "transparency\|sct" || true)
if [[ -n "$ct_headers" ]]; then
    echo "[PASS] Certificate Transparency extension present"
else
    echo "[INFO] Certificate Transparency status unknown (check with external tools)"
fi

# Test 6: OCSP Stapling
echo ""
echo "[TEST] Checking OCSP Stapling..."
ocsp_status=$(echo | timeout 5 openssl s_client -connect "$TARGET_HOST:$TARGET_PORT" -servername "$TARGET_HOST" -status 2>/dev/null | grep -A5 "OCSP response" | head -10 || true)
if echo "$ocsp_status" | grep -q "OCSP Response Status"; then
    echo "[PASS] OCSP Stapling is enabled"
    echo "       $ocsp_status"
else
    echo "[WARN] OCSP Stapling may not be enabled (recommended for performance)"
fi

# Test 7: Strong cipher suites
echo ""
echo "[TEST] Checking cipher suite configuration..."
cipher_list=$(echo | timeout 5 openssl s_client -connect "$TARGET_HOST:$TARGET_PORT" -servername "$TARGET_HOST" 2>/dev/null | grep "Cipher.*:" || true)
if [[ -n "$cipher_list" ]]; then
    echo "[INFO] Negotiated cipher: $cipher_list"
    
    # Check for weak ciphers
    if echo "$cipher_list" | grep -qiE "NULL|EXPORT|DES|RC4|MD5|SHA1"; then
        echo "[FAIL] Weak cipher detected: $cipher_list"
    elif echo "$cipher_list" | grep -qiE "ECDHE|AES.*GCM|AES.*CCM|CHACHA20"; then
        echo "[PASS] Strong cipher suite detected"
    else
        echo "[INFO] Cipher strength: $cipher_list"
    fi
fi

# Test 8: HSTS header from TLS perspective
echo ""
echo "[TEST] Validating HSTS (HTTP Strict Transport Security)..."
hsts_headers=$(echo -e "GET / HTTP/1.1\r\nHost: $TARGET_HOST\r\nConnection: close\r\n\r\n" | timeout 5 openssl s_client -connect "$TARGET_HOST:$TARGET_PORT" -servername "$TARGET_HOST" -quiet 2>/dev/null | grep -i "strict-transport-security" || true)
if [[ -n "$hsts_headers" ]]; then
    echo "[PASS] HSTS header present:"
    echo "       $hsts_headers"
else
    echo "[WARN] HSTS header not detected at TLS layer (may be added by application layer)"
fi

echo ""
echo "=== TLS Assessment Complete ==="
echo ""
