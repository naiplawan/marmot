#!/bin/bash
# Quick test runner script
# Runs all tests before committing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "================================"
echo "  marmot Test Runner"
echo "================================"
echo ""

# Track failures
FAILED=0

# 1. ShellCheck
echo "1. Running ShellCheck..."
if command -v shellcheck > /dev/null 2>&1; then
    if shellcheck marmot bin/*.sh 2> /dev/null &&
        find lib -name "*.sh" -type f -exec shellcheck {} + 2> /dev/null; then
        echo -e "${GREEN}✓ ShellCheck passed${NC}"
    else
        echo -e "${RED}✗ ShellCheck failed${NC}"
        ((FAILED++))
    fi
else
    echo -e "${YELLOW}⚠ ShellCheck not installed, skipping${NC}"
fi
echo ""

# 2. Syntax Check
echo "2. Running syntax check..."
if bash -n marmot &&
    bash -n bin/*.sh 2> /dev/null &&
    find lib -name "*.sh" -type f -exec bash -n {} \; 2> /dev/null; then
    echo -e "${GREEN}✓ Syntax check passed${NC}"
else
    echo -e "${RED}✗ Syntax check failed${NC}"
    ((FAILED++))
fi
echo ""

# 3. Unit Tests
echo "3. Running unit tests..."
if command -v bats > /dev/null 2>&1; then
    if bats tests/*.bats; then
        echo -e "${GREEN}✓ Unit tests passed${NC}"
    else
        echo -e "${RED}✗ Unit tests failed${NC}"
        ((FAILED++))
    fi
else
    echo -e "${YELLOW}⚠ Bats not installed, skipping unit tests${NC}"
    echo "  Install with: sudo apt install bats-core"
fi
echo ""

# 4. Go Tests
echo "4. Running Go tests..."
if command -v go > /dev/null 2>&1; then
    if go build ./... && go vet ./cmd/...; then
        echo -e "${GREEN}✓ Go tests passed${NC}"
    else
        echo -e "${RED}✗ Go tests failed${NC}"
        ((FAILED++))
    fi
else
    echo -e "${YELLOW}⚠ Go not installed, skipping Go tests${NC}"
fi
echo ""

# 5. Module Loading Test
echo "5. Testing module loading..."
if bash -c 'source lib/core/common.sh && echo "OK"' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Module loading passed${NC}"
else
    echo -e "${RED}✗ Module loading failed${NC}"
    ((FAILED++))
fi
echo ""

# 6. Integration Tests
echo "6. Running integration tests..."
if ./bin/clean.sh --dry-run > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Clean dry-run passed${NC}"
else
    echo -e "${RED}✗ Clean dry-run failed${NC}"
    ((FAILED++))
fi
echo ""

# Summary
echo "================================"
if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    echo ""
    echo "You can now commit your changes."
    exit 0
else
    echo -e "${RED}$FAILED test(s) failed!${NC}"
    echo ""
    echo "Please fix the failing tests before committing."
    exit 1
fi
