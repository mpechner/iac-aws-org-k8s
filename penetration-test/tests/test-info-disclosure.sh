#!/bin/bash
# SecureGuard PT - Information Disclosure Assessment
# Checks for information leakage vulnerabilities

set -e

TARGET_URL="${TARGET_URL:-https://nginx.dev.foobar.support}"
TARGET_HOST=$(echo "$TARGET_URL" | sed -E 's|https?://||' | cut -d'/' -f1)

echo "=== Information Disclosure Assessment ==="
echo "Target: $TARGET_URL"
echo ""

# Common paths that should not exist or return 404
SENSITIVE_PATHS=(
    "/.git"
    "/.env"
    "/.htaccess"
    "/config.php"
    "/wp-config.php"
    "/phpmyadmin"
    "/admin"
    "/backup"
    "/.svn"
    "/.hg"
    "/docker-compose.yml"
    "/Dockerfile"
    "/server-status"
    "/phpinfo.php"
    "/test"
    "/debug"
    "/api/v1/swagger"
    "/swagger.json"
    "/api-docs"
)

echo "[TEST] Checking for exposed sensitive paths..."
echo ""

# First, get the size of the homepage to detect default page behavior
home_response=$(curl -s --max-time 5 -k "$TARGET_URL" 2>/dev/null || true)
home_size=${#home_response}
echo "[INFO] Homepage content size: ${home_size}b (used to detect default page serving)"
echo ""

exposed_count=0
for path in "${SENSITIVE_PATHS[@]}"; do
    url="${TARGET_URL}${path}"
    response=$(curl -s --max-time 5 -k "$url" 2>/dev/null || true)
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -k "$url" 2>/dev/null || echo "000")
    size=${#response}
    
    # Skip if it's the same size as homepage (likely default page serving)
    size_diff=$((size - home_size))
    if [[ ${size_diff#-} -lt 100 ]] && [[ "$http_code" == "200" ]]; then
        # Content is same size as homepage - probably default page, skip
        continue
    fi
    
    # Check for actual indicators of the resource type
    is_exposed=false
    case "$path" in
        /.git)
            if echo "$response" | grep -qiE "git.*config|refs/heads|objects"; then
                is_exposed=true
            fi
            ;;
        /.env)
            if echo "$response" | grep -qiE "^[A-Z_]+=.*$|DB_|API_KEY|SECRET"; then
                is_exposed=true
            fi
            ;;
        /.htaccess)
            if echo "$response" | grep -qiE "Rewrite|Auth|Order|Deny"; then
                is_exposed=true
            fi
            ;;
        *config.php|*wp-config.php)
            if echo "$response" | grep -qiE "define\(|DB_|PASSWORD|SECRET"; then
                is_exposed=true
            fi
            ;;
        /phpmyadmin)
            if echo "$response" | grep -qiE "phpMyAdmin|pma_|mysql"; then
                is_exposed=true
            fi
            ;;
        /admin)
            if echo "$response" | grep -qiE "login|admin|password|dashboard"; then
                is_exposed=true
            fi
            ;;
        /server-status)
            if echo "$response" | grep -qiE "Server Version|Current Time|CPU Usage|requests"; then
                is_exposed=true
            fi
            ;;
        /phpinfo.php)
            if echo "$response" | grep -qiE "phpinfo\(\)|PHP Version|php.ini"; then
                is_exposed=true
            fi
            ;;
        /swagger.json|/api-docs|/api/v1/swagger)
            if echo "$response" | grep -qiE '"swagger"|"openapi"|"paths"|"definitions"'; then
                is_exposed=true
            fi
            ;;
        *)
            # For other paths, check if content differs significantly from homepage
            # and has meaningful structure
            if [[ "$http_code" == "200" ]] && [[ $size -gt 100 ]] && [[ ${size_diff#-} -gt 500 ]]; then
                # Large size difference and has structure
                if echo "$response" | grep -qiE "<html|<title|error|docker|version"; then
                    is_exposed=true
                fi
            fi
            ;;
    esac
    
    if [[ "$is_exposed" == true ]]; then
        echo "[FAIL] Exposed path found: $path (HTTP $http_code, ${size}b)"
        ((exposed_count++))
    fi
done

if [[ $exposed_count -eq 0 ]]; then
    echo "[PASS] No sensitive paths exposed (default page serving or 404)"
fi

# Test for directory listing
echo ""
echo "[TEST] Checking for directory listing enabled..."

listing_paths=(
    "/images/"
    "/css/"
    "/js/"
    "/assets/"
    "/static/"
)

listing_found=false
for path in "${listing_paths[@]}"; do
    url="${TARGET_URL}${path}"
    content=$(curl -s --max-time 5 -k "$url" 2>/dev/null || true)
    
    # Check for common directory listing indicators
    if echo "$content" | grep -qiE "<title>Index of|Directory Listing|Parent Directory|<h1>Index"; then
        echo "[FAIL] Directory listing enabled at: $path"
        listing_found=true
    fi
done

if [[ "$listing_found" == false ]]; then
    echo "[PASS] Directory listing not detected"
fi

# Test error pages
echo ""
echo "[TEST] Checking error pages for information disclosure..."

error_codes=(
    "404:/nonexistent-page-12345"
    "500:/trigger-error-test"
)

for error_test in "${error_codes[@]}"; do
    code=$(echo "$error_test" | cut -d':' -f1)
    path=$(echo "$error_test" | cut -d':' -f2)
    url="${TARGET_URL}${path}"
    
    response=$(curl -s --max-time 5 -k "$url" 2>/dev/null || true)
    
    # Check for information leakage in error pages
    if echo "$response" | grep -qiE "stack trace|debug mode|Server:.*Apache|nginx/[0-9]|PHP/[0-9]|version|phpinfo"; then
        echo "[FAIL] Error page $code discloses information"
        echo "       Sample: $(echo "$response" | head -3)"
    else
        echo "[PASS] Error page $code does not disclose sensitive information"
    fi
done

# Test for server fingerprinting
echo ""
echo "[TEST] Checking server fingerprinting..."

headers=$(curl -sI --max-time 5 -k "$TARGET_URL" 2>/dev/null || true)

server_header=$(echo "$headers" | grep -i "^Server:" || true)
if [[ -n "$server_header" ]]; then
    if echo "$server_header" | grep -qE "[0-9]+\.[0-9]+"; then
        echo "[FAIL] Server version disclosed: $server_header"
    else
        echo "[PASS] Server header present without version: $server_header"
    fi
else
    echo "[PASS] Server header not present (best practice)"
fi

# Check for other identifying headers
identifying_headers=("X-Powered-By" "X-AspNet-Version" "X-Generator" "Via")
for header in "${identifying_headers[@]}"; do
    if echo "$headers" | grep -qi "^$header:"; then
        echo "[WARN] Identifying header present: $(echo "$headers" | grep -i "^$header:")"
    fi
done

# Test HTTP methods
echo ""
echo "[TEST] Checking for dangerous HTTP methods..."

options_response=$(curl -s -X OPTIONS -i --max-time 5 -k "$TARGET_URL" 2>/dev/null | grep -i "Allow:" || true)
if [[ -n "$options_response" ]]; then
    echo "[INFO] Allowed methods: $options_response"
    
    if echo "$options_response" | grep -qiE "PUT|DELETE|TRACE|CONNECT|PROPFIND"; then
        echo "[FAIL] Potentially dangerous HTTP methods enabled: $options_response"
    else
        echo "[PASS] No dangerous HTTP methods detected"
    fi
else
    echo "[INFO] OPTIONS method did not return Allow header"
fi

# Check TRACE method (XST vulnerability)
trace_test=$(curl -s -X TRACE -o /dev/null -w "%{http_code}" --max-time 5 -k "$TARGET_URL" 2>/dev/null || echo "000")
if [[ "$trace_test" == "200" ]]; then
    echo "[FAIL] TRACE method enabled (XST vulnerability risk)"
elif [[ "$trace_test" == "405" ]]; then
    echo "[PASS] TRACE method properly blocked (HTTP 405 Method Not Allowed)"
else
    echo "[PASS] TRACE method disabled or not allowed (HTTP $trace_test)"
fi

echo ""
echo "=== Information Disclosure Assessment Complete ==="
echo ""
