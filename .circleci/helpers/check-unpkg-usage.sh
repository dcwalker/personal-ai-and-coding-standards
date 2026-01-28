#!/bin/bash
set -e
echo "Checking for unpkg.com usage..."
UNPKG_FILES=$(grep -r --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.html" --include="*.json" \
  -i "unpkg\.com" \
  . 2>/dev/null | grep -v "node_modules" | grep -v ".git" | grep -v "$(basename $0)" || true)
if [ -n "$UNPKG_FILES" ]; then
  echo "Error: Found unpkg.com usage (security risk - all packages must be bundled):"
  echo "$UNPKG_FILES"
  exit 1
fi
echo "No unpkg.com usage found."
exit 0
