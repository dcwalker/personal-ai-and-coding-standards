#!/bin/bash

# Run all CircleCI checks locally
# This script runs the same checks that CircleCI runs, allowing developers to verify changes before pushing
# It continues through all checks and reports all failures at the end

set +e  # Don't exit on error - we want to run all checks

echo "Running local CI checks..."
echo ""

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
  echo "Error: package.json not found. Please run this script from the project root."
  exit 1
fi

# Install dependencies if node_modules doesn't exist
if [ ! -d "node_modules" ]; then
  echo "Installing dependencies..."
  yarn install
fi

ERRORS=0
FAILED_CHECKS=()

# Run checks in the same order as CircleCI
# Skip depcheck if script doesn't exist
if yarn run depcheck >/dev/null 2>&1; then
  echo "1. Running depcheck..."
  if ! yarn run depcheck; then
    ERRORS=$((ERRORS + 1))
    FAILED_CHECKS+=("depcheck")
  fi
else
  echo "1. Skipping depcheck (script not found)"
fi

echo ""
echo "2. Running format check..."
if ! yarn run format:check; then
  ERRORS=$((ERRORS + 1))
  FAILED_CHECKS+=("format:check")
fi

echo ""
echo "3. Running ESLint..."
if ! yarn run lint:check; then
  ERRORS=$((ERRORS + 1))
  FAILED_CHECKS+=("lint:check")
fi

echo ""
echo "4. Running typecheck..."
if ! yarn run typecheck; then
  ERRORS=$((ERRORS + 1))
  FAILED_CHECKS+=("typecheck")
fi

echo ""
echo "5. Checking for eslint-disable comments..."
if ! .circleci/helpers/check-eslint-disable.sh; then
  ERRORS=$((ERRORS + 1))
  FAILED_CHECKS+=("check-eslint-disable")
fi

echo ""
echo "6. Checking markdown file placement..."
if ! .circleci/helpers/check-markdown-placement.sh; then
  ERRORS=$((ERRORS + 1))
  FAILED_CHECKS+=("check-markdown-placement")
fi

echo ""
echo "7. Checking for unpkg.com usage..."
if ! .circleci/helpers/check-unpkg-usage.sh; then
  ERRORS=$((ERRORS + 1))
  FAILED_CHECKS+=("check-unpkg-usage")
fi

echo ""
echo "8. Running backend unit tests with coverage..."
if ! yarn run test:cov; then
  ERRORS=$((ERRORS + 1))
  FAILED_CHECKS+=("test:cov")
fi

echo ""
echo "9. Running frontend unit tests with coverage..."
if ! yarn run test:cov:frontend; then
  ERRORS=$((ERRORS + 1))
  FAILED_CHECKS+=("test:cov:frontend")
fi

echo ""
if [ $ERRORS -eq 0 ]; then
  echo "All local CI checks passed!"
  exit 0
else
  echo "========================================="
  echo "CI Checks Summary: $ERRORS check(s) failed"
  echo "========================================="
  echo ""
  echo "Failed checks:"
  for check in "${FAILED_CHECKS[@]}"; do
    echo "  - $check"
  done
  echo ""
  echo "Please fix the errors above and run again."
  exit 1
fi
