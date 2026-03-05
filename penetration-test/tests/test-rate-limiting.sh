#!/bin/bash
# SecureGuard PT - Rate Limiting Assessment
# Tests DoS protection mechanisms

set -e

TARGET_URL="${TARGET_URL:-https://nginx.dev.foobar.support}"

echo "=== Rate Limiting Assessment ==="
echo "Target: $TARGET_URL"
echo ""

# Configuration
TEST_REQUESTS=20
CONCURRENT_REQUESTS=5
RATE_LIMIT_THRESHOLD=10  # Requests per second that would trigger concern

echo "[TEST] Basic rate limiting test..."
echo "Sending $TEST_REQUESTS requests in rapid succession..."
echo ""

# Sequential rapid requests
echo "[*] Sequential rapid request test..."
start_time=$(date +%s.%N)
success_count=0
rate_limited_count=0
error_count=0

for i in $(seq 1 $TEST_REQUESTS); do
    response_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 -k "$TARGET_URL" 2>/dev/null || echo "000")
    
    case "$response_code" in
        200|301|302|304)
            ((success_count++))
            ;;
        429)
            ((rate_limited_count++))
            echo "Request $i: RATE LIMITED (HTTP 429)"
            ;;
        503|502|500)
            ((error_count++))
            echo "Request $i: Server error (HTTP $response_code)"
            ;;
        *)
            ((error_count++))
            echo "Request $i: Other response (HTTP $response_code)"
            ;;
    esac
done

end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)
rps=$(echo "scale=2; $TEST_REQUESTS / $duration" | bc)

echo ""
echo "Sequential test results:"
echo "  Successful: $success_count/$TEST_REQUESTS"
echo "  Rate limited (429): $rate_limited_count"
echo "  Errors: $error_count"
echo "  Duration: ${duration}s"
echo "  Requests/sec: $rps"

if [[ $rate_limited_count -gt 0 ]]; then
    echo "[PASS] Rate limiting detected (HTTP 429 responses)"
elif [[ $success_count -eq $TEST_REQUESTS ]]; then
    echo "[INFO] All requests succeeded - rate limiting may not be active or threshold not reached"
else
    echo "[WARN] Unexpected results - check server status"
fi

# Test 2: Concurrent connection test
echo ""
echo "[TEST] Concurrent connection test..."
echo "Launching $CONCURRENT_REQUESTS parallel requests..."

concurrent_start=$(date +%s.%N)

# Initialize results file
> /tmp/concurrent_results.txt

# Use xargs for parallel execution
seq $CONCURRENT_REQUESTS | xargs -P $CONCURRENT_REQUESTS -I {} \
    sh -c "curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 -k '$TARGET_URL' >> /tmp/concurrent_results.txt 2>/dev/null || true"

concurrent_end=$(date +%s.%N)
concurrent_duration=$(echo "$concurrent_end - $concurrent_start" | bc)

# Analyze concurrent results
total_concurrent=$(wc -l < /tmp/concurrent_results.txt 2>/dev/null || echo 0)
success_concurrent=$(grep -cE "^200$|^301$|^302$" /tmp/concurrent_results.txt 2>/dev/null || echo 0)
rate_limit_concurrent=$(grep -c "^429$" /tmp/concurrent_results.txt 2>/dev/null || echo 0)
error_concurrent=$(grep -c "^5" /tmp/concurrent_results.txt 2>/dev/null || echo 0)

echo ""
echo "Concurrent test results:"
echo "  Total responses: $total_concurrent"
echo "  Successful: $success_concurrent"
echo "  Rate limited (429): $rate_limit_concurrent"
echo "  Server errors: $error_concurrent"
echo "  Duration: ${concurrent_duration}s"

if [[ $rate_limit_concurrent -gt 0 ]]; then
    echo "[PASS] Rate limiting active under concurrent load"
elif [[ $error_concurrent -gt $((CONCURRENT_REQUESTS / 2)) ]]; then
    echo "[WARN] High error rate under concurrent load - possible resource exhaustion"
else
    echo "[INFO] Concurrent requests handled - check if rate limiting is configured"
fi

# Cleanup
rm -f /tmp/concurrent_results.txt

# Test 3: Slowloris-style slow connection (limited, safe check)
echo ""
echo "[TEST] Slow connection behavior..."
echo "Testing with intentionally slow request (partial data)..."

# Send a request with partial headers and check timeout behavior
slow_response=$(curl -s -o /dev/null -w "%{http_code},%{time_total}" \
    --max-time 10 \
    -H "X-Slow-Test: true" \
    -k "$TARGET_URL" 2>/dev/null || echo "000,0")

slow_code=$(echo "$slow_response" | cut -d',' -f1)
slow_time=$(echo "$slow_response" | cut -d',' -f2)

if [[ "$slow_code" == "200" ]]; then
    echo "[INFO] Slow request completed in ${slow_time}s"
    if (( $(echo "$slow_time > 5" | bc -l) )); then
        echo "[INFO] Request took >5s - may indicate slow connection handling"
    fi
else
    echo "[INFO] Slow request response: HTTP $slow_code (${slow_time}s)"
fi

# Test 4: Check for rate limit headers
echo ""
echo "[TEST] Checking for rate limit headers..."

headers=$(curl -sI --max-time 5 -k "$TARGET_URL" 2>/dev/null || true)

rate_limit_headers=(
    "X-RateLimit-Limit"
    "X-RateLimit-Remaining"
    "X-RateLimit-Reset"
    "Retry-After"
    "X-Rate-Limit"
)

headers_found=false
for header in "${rate_limit_headers[@]}"; do
    if echo "$headers" | grep -qi "^$header"; then
        echo "[INFO] Rate limit header found: $(echo "$headers" | grep -i "^$header")"
        headers_found=true
    fi
done

if [[ "$headers_found" == false ]]; then
    echo "[INFO] No rate limit headers detected (rate limiting may be at infrastructure level)"
fi

# Summary recommendations
echo ""
echo "=== Rate Limiting Assessment Summary ==="
echo ""

if [[ $rate_limited_count -gt 0 ]] || [[ $rate_limit_concurrent -gt 0 ]]; then
    echo "[PASS] Rate limiting is active"
    echo "Recommendation: Verify rate limits align with expected traffic patterns"
elif [[ $success_count -eq $TEST_REQUESTS ]] && [[ $success_concurrent -eq $CONCURRENT_REQUESTS ]]; then
    echo "[WARN] No rate limiting detected in basic tests"
    echo "Recommendations:"
    echo "  1. Verify Traefik/ingress rate limiting is configured"
    echo "  2. Check AWS WAF or NLB rate limiting settings"
    echo "  3. Consider implementing application-level rate limiting"
    echo "  4. Test with higher volume for production readiness"
else
    echo "[INFO] Results inconclusive - review individual test results above"
fi

echo ""
echo "=== Rate Limiting Assessment Complete ==="
echo ""
