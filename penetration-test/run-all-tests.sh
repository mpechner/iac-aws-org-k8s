#!/bin/bash
# FooBar Penetration Testing - Multi-Site Test Runner
# Runs all security tests against multiple sites from a file
#
# Usage: ./run-all-tests.sh [SITES_FILE]
#   SITES_FILE: Path to file containing URLs to test (one per line)
#   Default: tests/sites.txt
#
# Example sites.txt:
#   https://nginx.dev.foobar.support
#   https://traefik.dev.foobar.support
#   https://rancher.dev.foobar.support

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
SITES_FILE="${1:-sites.txt}"

# Validate sites file
if [[ ! -f "$SITES_FILE" ]]; then
    echo -e "${RED}Error: Sites file not found: $SITES_FILE${NC}"
    echo "Usage: $0 [SITES_FILE]"
    echo "Create a file with one URL per line, e.g.:"
    echo "  https://nginx.dev.foobar.support"
    echo "  https://traefik.dev.foobar.support"
    exit 1
fi

# Timestamp for this test run
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RUN_DIR="penetration-run/$TIMESTAMP"

# Create timestamped run directory
mkdir -p "$RUN_DIR"

# Read sites into array (portable, works with bash 3.2+)
SITES=()
while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "${line// }" ]] && continue
    # Trim trailing whitespace
    line=$(echo "$line" | sed 's/[[:space:]]*$//')
    SITES+=("$line")
done < "$SITES_FILE"

if [[ ${#SITES[@]} -eq 0 ]]; then
    echo -e "${RED}Error: No valid sites found in $SITES_FILE${NC}"
    exit 1
fi

echo "=============================================="
echo "FooBar Penetration Testing Suite"
echo "Started: $(date)"
echo "Sites File: $SITES_FILE"
echo "Sites to Test: ${#SITES[@]}"
echo "Run Directory: $RUN_DIR"
echo "=============================================="
echo ""

# Global counters
TOTAL_SITES=${#SITES[@]}
SITES_PASSED=0
SITES_FAILED=0

# Function to sanitize site name for filenames
sanitize_site_name() {
    local site="$1"
    # Remove protocol, replace dots and slashes with dashes
    echo "$site" | sed 's|https*://||' | sed 's|/|-|g' | sed 's|\.|_|g'
}

# Function to run all tests against a single site
run_site_tests() {
    local site="$1"
    local site_safe=$(sanitize_site_name "$site")
    local site_report="$RUN_DIR/security-assessment-${site_safe}-${TIMESTAMP}.txt"
    local site_log="$RUN_DIR/test-${site_safe}.log"
    
    echo -e "${BLUE}[*] Testing: $site${NC}"
    
    # Initialize site report
    {
        echo "FooBar Penetration Testing Report"
        echo "======================================"
        echo "Target: $site"
        echo "Date: $(date)"
        echo "Report ID: PT-${site_safe}-${TIMESTAMP}"
        echo "Run Directory: $RUN_DIR"
        echo ""
    } > "$site_report"
    
    # Export target for test scripts
    export TARGET_URL="$site"
    
    # Run all test categories
    run_test_category "tests/test-headers.sh" "Security Headers Assessment" "$site_report"
    run_test_category "tests/test-tls.sh" "TLS/SSL Configuration Assessment" "$site_report"
    run_test_category "tests/test-info-disclosure.sh" "Information Disclosure Assessment" "$site_report"
    run_test_category "tests/test-attack-vectors.sh" "Attack Vector Validation" "$site_report"
    run_test_category "tests/test-rate-limiting.sh" "Rate Limiting Assessment" "$site_report"
    
    # Count results for this site (strip newlines with tr)
    local site_total=$(grep -c "^\[TEST\]" "$site_report" 2>/dev/null | tr -d '\n' || echo 0)
    local site_passed=$(grep -c "^\[PASS\]" "$site_report" 2>/dev/null | tr -d '\n' || echo 0)
    local site_failed=$(grep -c "^\[FAIL\]" "$site_report" 2>/dev/null | tr -d '\n' || echo 0)
    local site_warnings=$(grep -c "^\[WARN\]" "$site_report" 2>/dev/null | tr -d '\n' || echo 0)
    
    # Add site summary to report
    {
        echo ""
        echo "=============================================="
        echo "Site Test Summary: $site"
        echo "=============================================="
        echo "Total Tests:  $site_total"
        echo "Passed:       $site_passed"
        echo "Failed:       $site_failed"
        echo "Warnings:     $site_warnings"
        echo ""
        if [[ $site_failed -eq 0 ]]; then
            echo "[+] SECURITY ASSESSMENT: PASSED"
        else
            echo "[!] SECURITY ASSESSMENT: REVIEW REQUIRED"
        fi
    } >> "$site_report"
    
    # Print site result
    if [[ $site_failed -eq 0 ]]; then
        echo -e "${GREEN}[+] $site: PASSED ($site_passed/$site_total tests)${NC}"
        ((SITES_PASSED++))
    else
        echo -e "${YELLOW}[!] $site: REVIEW REQUIRED ($site_failed failed)${NC}"
        ((SITES_FAILED++))
    fi
    echo "  Report: $site_report"
    echo ""
}

# Function to run a test category
run_test_category() {
    local test_script="$1"
    local category_name="$2"
    local report_file="$3"
    
    echo "  - $category_name"
    
    {
        echo ""
        echo "=== $category_name ==="
        echo ""
    } >> "$report_file"
    
    if [[ -x "$test_script" ]]; then
        # Export TARGET_URL for test scripts
        if TARGET_URL="$TARGET_URL" "$test_script" >> "$report_file" 2>&1; then
            : # Success
        else
            : # Warnings (non-zero exit is OK)
        fi
    else
        echo "ERROR: Test script not found: $test_script" >> "$report_file"
    fi
}

# Run tests for each site
for site in "${SITES[@]}"; do
    run_site_tests "$site"
done

# Generate master summary report
MASTER_REPORT="$RUN_DIR/MASTER-SUMMARY-${TIMESTAMP}.txt"
{
    echo "FooBar Penetration Testing - Master Summary"
    echo "=============================================="
    echo "Date: $(date)"
    echo "Sites Tested: $TOTAL_SITES"
    echo "Run Directory: $RUN_DIR"
    echo ""
    echo "=============================================="
    echo "Results Summary"
    echo "=============================================="
    echo ""
    echo "Sites Passed: $SITES_PASSED / $TOTAL_SITES"
    echo "Sites Failed: $SITES_FAILED / $TOTAL_SITES"
    echo ""
    echo "Per-Site Reports:"
    for site in "${SITES[@]}"; do
        site_safe=$(sanitize_site_name "$site")
        echo "  - $site: security-assessment-${site_safe}-${TIMESTAMP}.txt"
    done
    echo ""
    echo "=============================================="
    if [[ $SITES_FAILED -eq 0 ]]; then
        echo "[+] OVERALL ASSESSMENT: ALL SITES PASSED"
    else
        echo "[!] OVERALL ASSESSMENT: $SITES_FAILED SITE(S) REQUIRE REVIEW"
    fi
    echo "=============================================="
} > "$MASTER_REPORT"

# Print final summary
echo "=============================================="
echo -e "${BLUE}[*] All Tests Complete${NC}"
echo "=============================================="
echo ""
echo "Results:"
echo "  Sites Tested: $TOTAL_SITES"
echo -e "  ${GREEN}Sites Passed: $SITES_PASSED${NC}"
echo -e "  ${YELLOW}Sites Failed: $SITES_FAILED${NC}"
echo ""
echo "Reports Generated:"
echo "  Master Summary: $MASTER_REPORT"
echo "  Per-Site Reports in: $RUN_DIR/"
echo ""

# Exit code based on results
if [[ $SITES_FAILED -eq 0 ]]; then
    echo -e "${GREEN}[+] OVERALL ASSESSMENT: PASSED${NC}"
    exit 0
else
    echo -e "${YELLOW}[!] OVERALL ASSESSMENT: REVIEW REQUIRED${NC}"
    exit 1
fi
