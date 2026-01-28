#!/bin/bash

# Check that markdown files are in the correct location
# Documentation files should be in docs/ directory, not in root
# Exceptions: README.md, CONTRIBUTING.md, and AGENTS.md are allowed in root only
# Dot directories (like .github, .cursor) and node_modules are ignored

set -e

echo "Checking markdown file placement..."

# Files allowed in root directory
ALLOWED_ROOT_FILES=(
  "README.md"
  "CONTRIBUTING.md"
  "AGENTS.md"
)

ERRORS=0

# Find all .md files, excluding dot directories and node_modules
# Use find with -path to exclude directories starting with . and node_modules
while IFS= read -r -d '' file; do
  # Get the directory and filename, normalize path (remove ./ prefix)
  dir=$(dirname "$file")
  dir=$(echo "$dir" | sed 's|^\./||')
  filename=$(basename "$file")
  
  # Skip if in a dot directory or node_modules (shouldn't happen with our find, but double-check)
  if [[ "$dir" =~ ^\. ]] || [[ "$dir" =~ /\. ]] || [[ "$dir" =~ node_modules ]]; then
    continue
  fi
  
  # Check if file is in root directory
  if [ "$dir" = "." ] || [ -z "$dir" ]; then
    # Check if it's one of the allowed root files
    allowed=false
    for allowed_file in "${ALLOWED_ROOT_FILES[@]}"; do
      if [ "$filename" = "$allowed_file" ]; then
        allowed=true
        break
      fi
    done
    
    if [ "$allowed" = false ]; then
      echo "Error: $filename should be in docs/ directory, not in root"
      ERRORS=$((ERRORS + 1))
    fi
  # Check if file is in docs/ directory (including subdirectories)
  elif [[ "$dir" == "docs" ]] || [[ "$dir" == "docs/"* ]]; then
    # Files in docs/ are allowed
    continue
  else
    # File is in some other directory (not root, not docs/)
    echo "Error: $file should be in docs/ directory"
    ERRORS=$((ERRORS + 1))
  fi
done < <(find . -name "*.md" -type f -not -path "*/\.*" -not -path "*/node_modules/*" -print0)

if [ $ERRORS -gt 0 ]; then
  echo "Found $ERRORS markdown file placement issue(s)"
  exit 1
fi

echo "All markdown files are in correct locations."
exit 0
