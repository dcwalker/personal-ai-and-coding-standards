#!/bin/bash
set -euo pipefail
echo "Checking for eslint-disable comments..."
# Use two-step grep: first find all eslint-disable, then filter out allowed patterns and node_modules
DISABLED_FILES=$(grep -r --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  --exclude-dir=node_modules \
  "eslint-disable" \
  src/ test/ static/ 2>/dev/null | grep -v "eslint-disable-next-line" | grep -v "eslint-disable-line" || true)
if [ -n "$DISABLED_FILES" ]; then
  echo "Error: Found eslint-disable comments (eslint-disable-next-line is allowed):"
  echo "$DISABLED_FILES"
  exit 1
fi
echo "No eslint-disable comments found (excluding eslint-disable-next-line)."
exit 0