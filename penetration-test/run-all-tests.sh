#!/bin/bash
# SecureGuard Penetration Testing - Main Test Runner
# Runs all security tests against nginx target

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TARGET_URL="${TARGET_URL:-https://nginx.dev.foobar.support}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RUN_DIR="penetration-run/$TIMESTAMP"
REPORT_FILE="$RUN_DIR/security-assessment-$TIMESTAMP.txt"

echo "=============================================="
echo "FooBar Penetration Testing Suite"
echo "Target: $TARGET_URL"
echo "Started: $(date)"
echo "Report will be saved to: $RUN_DIR/"
echo "=============================================="
echo ""

# Create timestamped run directory
mkdir -p "$RUN_DIR"

# Initialize report
{
    echo "FooBar Penetration Testing Report"
    echo "======================================"
    echo "Target: $TARGET_URL"
    echo "Date: $(date)"
    echo "Report ID: PT-NGINX-$TIMESTAMP"
    echo "Run Directory: $RUN_DIR"
    echo ""
} > "$REPORT_FILE"

# Test counter
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# Function to run a test category
run_test_category() {
    local test_script="$1"
    local category_name="$2"
    
    echo -e "${BLUE}[*] Running: $category_name${NC}"
    echo "" >> "$REPORT_FILE"
    echo "=== $category_name ===" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    if [[ -x "$test_script" ]]; then
        if "$test_script" >> "$REPORT_FILE" 2>&1; then
            echo -e "${GREEN}[+] $category_name completed${NC}"
        else
            echo -e "${YELLOW}[!] $category_name completed with warnings${NC}"
        fi
    else
        echo -e "${RED}[-] Test script not found or not executable: $test_script${NC}"
        echo "ERROR: Test script not found: $test_script" >> "$REPORT_FILE"
    fi
    echo ""
}

# Run all test categories
echo -e "${BLUE}[*] Starting comprehensive security assessment...${NC}"
echo ""

run_test_category "tests/test-headers.sh" "Security Headers Assessment"
run_test_category "tests/test-tls.sh" "TLS/SSL Configuration Assessment"
run_test_category "tests/test-info-disclosure.sh" "Information Disclosure Assessment"
run_test_category "tests/test-attack-vectors.sh" "Attack Vector Validation"
run_test_category "tests/test-rate-limiting.sh" "Rate Limiting Assessment"

# Generate summary
echo ""
echo "=============================================="
echo -e "${BLUE}[*] Assessment Complete${NC}"
echo "=============================================="
echo ""

# Count results from report
TOTAL_TESTS=$(grep -c "^\[TEST\]" "$REPORT_FILE" 2>/dev/null || echo 0)
PASSED_TESTS=$(grep -c "^\[PASS\]" "$REPORT_FILE" 2>/dev/null || echo 0)
FAILED_TESTS=$(grep -c "^\[FAIL\]" "$REPORT_FILE" 2>/dev/null || echo 0)
WARNINGS=$(grep -c "^\[WARN\]" "$REPORT_FILE" 2>/dev/null || echo 0)

# Display summary
echo "Test Results Summary:"
echo "---------------------"
echo -e "Total Tests:  $TOTAL_TESTS"
echo -e "${GREEN}Passed:       $PASSED_TESTS${NC}"
echo -e "${RED}Failed:       $FAILED_TESTS${NC}"
echo -e "${YELLOW}Warnings:     $WARNINGS${NC}"
echo ""
echo "Full report saved to: $REPORT_FILE"
echo ""

# Final verdict
if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}[+] SECURITY ASSESSMENT: PASSED${NC}"
    echo "No critical vulnerabilities found."
    exit 0
else
    echo -e "${YELLOW}[!] SECURITY ASSESSMENT: REVIEW REQUIRED${NC}"
    echo "$FAILED_TESTS test(s) failed. Review the report for details."
    exit 1
fi
