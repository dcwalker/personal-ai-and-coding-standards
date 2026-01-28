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
echo "1. Running depcheck..."
if ! yarn run depcheck; then
  ERRORS=$((ERRORS + 1))
  FAILED_CHECKS+=("depcheck")
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
echo "4. Running ESLint on all static pages..."
STATIC_PAGE_ERRORS=0
for page in static/*-page; do
  page_name=$(basename "$page")
  echo "Installing dependencies for $page_name..."
  if ! (cd "$page" && yarn install --frozen-lockfile); then
    STATIC_PAGE_ERRORS=$((STATIC_PAGE_ERRORS + 1))
    FAILED_CHECKS+=("install:$page_name")
    continue
  fi
  echo "Linting $page_name..."
  if ! (cd "$page" && yarn lint); then
    STATIC_PAGE_ERRORS=$((STATIC_PAGE_ERRORS + 1))
    FAILED_CHECKS+=("lint:$page_name")
  fi
done
if [ $STATIC_PAGE_ERRORS -gt 0 ]; then
  ERRORS=$((ERRORS + STATIC_PAGE_ERRORS))
fi

echo ""
echo "5. Running typecheck..."
if ! yarn run typecheck; then
  ERRORS=$((ERRORS + 1))
  FAILED_CHECKS+=("typecheck")
fi

echo ""
echo "6. Checking for eslint-disable comments..."
if ! .circleci/helpers/check-eslint-disable.sh; then
  ERRORS=$((ERRORS + 1))
  FAILED_CHECKS+=("check-eslint-disable")
fi

echo ""
echo "7. Checking markdown file placement..."
if ! .circleci/helpers/check-markdown-placement.sh; then
  ERRORS=$((ERRORS + 1))
  FAILED_CHECKS+=("check-markdown-placement")
fi

echo ""
echo "8. Checking for unpkg.com usage..."
if ! .circleci/helpers/check-unpkg-usage.sh; then
  ERRORS=$((ERRORS + 1))
  FAILED_CHECKS+=("check-unpkg-usage")
fi

echo ""
echo "9. Running unit tests with coverage..."
if ! yarn run test:cov; then
  ERRORS=$((ERRORS + 1))
  FAILED_CHECKS+=("test:cov")
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
