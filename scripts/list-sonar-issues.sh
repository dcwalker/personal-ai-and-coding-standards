#!/bin/bash

# Script to list SonarQube issues for this project
# Usage: ./list-sonar-issues.sh [OPTIONS]
# Run with -h or --help for full usage information

SONAR_HOST="${SONAR_HOST_URL}"
SONAR_HOST="${SONAR_HOST%/}/"  # Ensure trailing slash
SONAR_TOKEN="${SONAR_TOKEN}"

# Find project root by searching up the directory tree for sonar-project.properties
find_project_root() {
  local dir="$1"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/sonar-project.properties" ]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

# Try to get project key from environment variable, or read from sonar-project.properties
if [ -n "$SONAR_PROJECT_KEY" ]; then
  PROJECT_KEY="$SONAR_PROJECT_KEY"
else
  # Find project root by searching up from current directory
  PROJECT_ROOT=$(find_project_root "$(pwd)")
  if [ -z "$PROJECT_ROOT" ]; then
    echo "Error: SONAR_PROJECT_KEY environment variable is not set and sonar-project.properties file not found"
    exit 1
  fi
  
  PROPERTIES_FILE="$PROJECT_ROOT/sonar-project.properties"
  PROJECT_KEY=$(grep "^sonar.projectKey=" "$PROPERTIES_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
  if [ -z "$PROJECT_KEY" ]; then
    echo "Error: Could not find sonar.projectKey in sonar-project.properties"
    exit 1
  fi
fi

PULL_REQUEST=""
SEVERITY=""
TYPE=""
STATUS=""
RULE=""
ISSUE_KEY=""
COMPONENT=""
JSON_OUTPUT=""
COUNT_ONLY=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -pr|--pull-request)
      PULL_REQUEST="$2"
      shift 2
      ;;
    -s|--severity)
      SEVERITY="$2"
      shift 2
      ;;
    -t|--type)
      TYPE="$2"
      shift 2
      ;;
    --status)
      STATUS="$2"
      shift 2
      ;;
    -r|--rule)
      RULE="$2"
      shift 2
      ;;
    -k|--key)
      ISSUE_KEY="$2"
      shift 2
      ;;
    -c|--component)
      COMPONENT="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT="1"
      shift
      ;;
    --count)
      COUNT_ONLY="1"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -pr, --pull-request <number>  Filter issues for a specific pull request"
      echo "  -s, --severity <level>        Filter by severity: BLOCKER, CRITICAL, MAJOR, MINOR, INFO"
      echo "  -t, --type <type>             Filter by type: CODE_SMELL, BUG, VULNERABILITY, SECURITY_HOTSPOT"
      echo "  --status <status>             Filter by status: OPEN, CONFIRMED, REOPENED, RESOLVED, CLOSED"
      echo "  -r, --rule <ruleKey>          Filter by rule key (e.g., typescript:S6606)"
      echo "  -k, --key <issueKey>          Filter by specific issue key (e.g., AZsvly6yO42lZpvH9OC5)"
      echo "  -c, --component <path>        Filter by component (file path, exact match)"
      echo "  --json                        Output only JSON (no formatted text)"
      echo "  --count                       Output only the count of items"
      echo "  -h, --help                    Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                                    List all open issues for the project"
      echo "  $0 -pr 19                             List issues for pull request #19"
      echo "  $0 -s CRITICAL                        List all CRITICAL severity issues"
      echo "  $0 -pr 19 -s MAJOR                    List MAJOR issues for PR #19"
      echo "  $0 -t BUG -s BLOCKER                  List BLOCKER severity BUGs"
      echo "  $0 -t SECURITY_HOTSPOT                 List all security hotspots"
      echo "  $0 -r typescript:S6606                List issues for a specific rule"
      echo "  $0 -k AZsvly6yO42lZpvH9OC5            Show details for a specific issue"
      echo "                                       Note: Issue key search may not find issues"
      echo "                                       that only exist in PR context. Use -pr with"
      echo "                                       the key for better results."
      echo "  $0 -c src/utils/logger.ts             List issues for a specific component"
      echo "  $0 -pr 19 -s MAJOR -t CODE_SMELL      Combine multiple filters"
      echo "  $0 --json                              Output only JSON format"
      echo "  $0 -pr 19 --json                      Output JSON for PR #19 issues"
      echo "  $0 --count                            Output only the count"
      echo "  $0 -pr 19 -s MAJOR --count            Output count of MAJOR issues for PR #19"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use -h or --help for usage information"
      exit 1
      ;;
  esac
done

if [ -z "$SONAR_HOST_URL" ]; then
  echo "Error: SONAR_HOST_URL environment variable is not set"
  exit 1
fi

if [ -z "$SONAR_TOKEN" ]; then
  echo "Error: SONAR_TOKEN environment variable is not set"
  exit 1
fi

# Build API URLs
ISSUES_API_URL="${SONAR_HOST}api/issues/search"
HOTSPOTS_API_URL="${SONAR_HOST}api/hotspots/search"

# When searching by issue key, search within project and filter client-side
# The 'issues' API parameter doesn't work reliably, so we filter client-side instead
# Note: Issues that only exist in PR context may not be found without -pr flag
if [ -n "$ISSUE_KEY" ]; then
  # Search with project filter and large page size
  # If issue is in a PR, user should combine with -pr flag
  PARAMS="componentKeys=${PROJECT_KEY}&ps=500"
  FILTER_MSG="Fetching issue by key: ${ISSUE_KEY}"
  if [ -z "$PULL_REQUEST" ]; then
    FILTER_MSG="${FILTER_MSG} (tip: use -pr <number> if issue is from a PR)"
  fi
else
  # Use componentKeys instead of projectKeys for better filtering with pullRequest
  PARAMS="componentKeys=${PROJECT_KEY}"
  FILTER_MSG="Fetching issues for project: ${PROJECT_KEY}"
fi

# Add status filter if provided, otherwise default to unresolved issues
# When searching by key, try resolved=false first (most searches are for open issues)
# If not found, user can retry without status filter or with --status RESOLVED
if [ -n "$STATUS" ]; then
  # Validate status value
  case "$STATUS" in
    OPEN|CONFIRMED|REOPENED|RESOLVED|CLOSED)
      PARAMS="${PARAMS}&statuses=${STATUS}"
      FILTER_MSG="${FILTER_MSG}, Status: ${STATUS}"
      ;;
    *)
      echo "Error: Invalid status '${STATUS}'. Must be one of: OPEN, CONFIRMED, REOPENED, RESOLVED, CLOSED"
      exit 1
      ;;
  esac
else
  # Default to unresolved issues if no status filter is specified
  PARAMS="${PARAMS}&resolved=false"
fi

# Add pull request parameter if provided
if [ -n "$PULL_REQUEST" ]; then
  PARAMS="${PARAMS}&pullRequest=${PULL_REQUEST}"
  FILTER_MSG="${FILTER_MSG}, PR: ${PULL_REQUEST}"
fi

# Add severity filter if provided
if [ -n "$SEVERITY" ]; then
  # Validate severity value
  case "$SEVERITY" in
    BLOCKER|CRITICAL|MAJOR|MINOR|INFO)
      PARAMS="${PARAMS}&severities=${SEVERITY}"
      FILTER_MSG="${FILTER_MSG}, Severity: ${SEVERITY}"
      ;;
    *)
      echo "Error: Invalid severity '${SEVERITY}'. Must be one of: BLOCKER, CRITICAL, MAJOR, MINOR, INFO"
      exit 1
      ;;
  esac
fi

# Add type filter if provided
# Note: SECURITY_HOTSPOT uses a different API endpoint, so we don't add it to PARAMS here
if [ -n "$TYPE" ]; then
  # Validate type value
  case "$TYPE" in
    CODE_SMELL|BUG|VULNERABILITY)
      PARAMS="${PARAMS}&types=${TYPE}"
      FILTER_MSG="${FILTER_MSG}, Type: ${TYPE}"
      ;;
    SECURITY_HOTSPOT)
      FILTER_MSG="${FILTER_MSG}, Type: ${TYPE}"
      ;;
    *)
      echo "Error: Invalid type '${TYPE}'. Must be one of: CODE_SMELL, BUG, VULNERABILITY, SECURITY_HOTSPOT"
      exit 1
      ;;
  esac
fi

# Add rule filter if provided
if [ -n "$RULE" ]; then
  PARAMS="${PARAMS}&rules=${RULE}"
  FILTER_MSG="${FILTER_MSG}, Rule: ${RULE}"
fi

# Add component filter if provided (note: this will be applied client-side in jq)
if [ -n "$COMPONENT" ]; then
  FILTER_MSG="${FILTER_MSG}, Component: ${COMPONENT}"
fi

# Issue key filter is already handled above in the initial PARAMS setup

# Determine which endpoints to query based on type filter
# Note: When searching by issue key, only search issues (not hotspots)
FETCH_ISSUES="false"
FETCH_HOTSPOTS="false"

if [ -n "$ISSUE_KEY" ]; then
  # Issue key search only applies to issues, not hotspots
  FETCH_ISSUES="true"
elif [ -z "$TYPE" ]; then
  # No type filter: fetch both issues and hotspots
  FETCH_ISSUES="true"
  FETCH_HOTSPOTS="true"
elif [ "$TYPE" = "SECURITY_HOTSPOT" ]; then
  # Only fetch hotspots
  FETCH_HOTSPOTS="true"
else
  # Only fetch issues (CODE_SMELL, BUG, VULNERABILITY)
  FETCH_ISSUES="true"
fi

if [ -z "$JSON_OUTPUT" ]; then
  echo "$FILTER_MSG"
fi

# Build hotspots parameters (similar to issues but may have different parameter names)
# Note: Hotspots API uses similar parameters but status values differ (TO_REVIEW, REVIEWED, FIXED, SAFE)
# Use projectKey for hotspots API (componentKeys may not be supported)
HOTSPOTS_PARAMS=""
if [ -n "$ISSUE_KEY" ]; then
  HOTSPOTS_PARAMS="projectKey=${PROJECT_KEY}&ps=500"
else
  HOTSPOTS_PARAMS="projectKey=${PROJECT_KEY}"
fi

# Add pull request parameter if provided
# Note: Hotspots API supports pullRequest parameter (not available in community edition)
if [ -n "$PULL_REQUEST" ]; then
  HOTSPOTS_PARAMS="${HOTSPOTS_PARAMS}&pullRequest=${PULL_REQUEST}"
fi

# Add status filter for hotspots if provided
# Hotspots use different status values: TO_REVIEW, REVIEWED, FIXED, SAFE
# Note: Don't filter by status by default - return all hotspots to match UI behavior
if [ -n "$STATUS" ]; then
  # Map common status values to hotspot statuses if needed
  # For now, pass through if it's a valid hotspot status
  case "$STATUS" in
    TO_REVIEW|REVIEWED|FIXED|SAFE)
      HOTSPOTS_PARAMS="${HOTSPOTS_PARAMS}&status=${STATUS}"
      ;;
    # For other statuses, we'll filter client-side or skip status filter for hotspots
    *)
      # Don't add status parameter, will filter client-side
      ;;
  esac
fi
# Note: We don't filter by status by default - return all hotspots to see what's available

# Add severity filter if provided (hotspots also support severity)
if [ -n "$SEVERITY" ]; then
  HOTSPOTS_PARAMS="${HOTSPOTS_PARAMS}&severity=${SEVERITY}"
fi

# Add rule filter if provided
if [ -n "$RULE" ]; then
  HOTSPOTS_PARAMS="${HOTSPOTS_PARAMS}&ruleKey=${RULE}"
fi

# Make API requests
ISSUES_RESPONSE=""
HOTSPOTS_RESPONSE=""

if [ "$FETCH_ISSUES" = "true" ]; then
  ISSUES_RESPONSE=$(curl -s -u "${SONAR_TOKEN}:" "${ISSUES_API_URL}?${PARAMS}")
fi

if [ "$FETCH_HOTSPOTS" = "true" ]; then
  HOTSPOTS_RESPONSE=$(curl -s -u "${SONAR_TOKEN}:" "${HOTSPOTS_API_URL}?${HOTSPOTS_PARAMS}")
  # Check for errors in the response
  if [ -n "$HOTSPOTS_RESPONSE" ] && echo "$HOTSPOTS_RESPONSE" | jq empty 2>/dev/null; then
    ERROR_MSG=$(echo "$HOTSPOTS_RESPONSE" | jq -r '.errors[]?.msg // empty' 2>/dev/null)
    if [ -n "$ERROR_MSG" ]; then
      if [ -z "$JSON_OUTPUT" ] && [ -z "$COUNT_ONLY" ]; then
        echo "Warning: Hotspots API returned error: $ERROR_MSG" >&2
        if echo "$ERROR_MSG" | grep -qi "privilege\|permission\|access"; then
          echo "Note: Your SonarQube token may not have permission to access security hotspots." >&2
          echo "      Contact your SonarQube administrator to grant 'Browse' permission for security hotspots." >&2
        fi
      fi
      # Clear the response so we don't try to process an error response
      HOTSPOTS_RESPONSE=""
    fi
  fi
fi

# Check if jq is available for pretty formatting
if command -v jq &> /dev/null; then
  # Process issues response
  FILTERED_ISSUES_RESPONSE=""
  ISSUES_TOTAL=0
  
  if [ "$FETCH_ISSUES" = "true" ] && [ -n "$ISSUES_RESPONSE" ]; then
    # When searching by issue key, filter by key client-side (API 'issues' parameter is unreliable)
    # When searching by key, we search broadly, so we only filter by key (not project)
    # Otherwise, filter issues to only include our project (API sometimes returns issues from other projects)
    if [ -n "$ISSUE_KEY" ]; then
      if [ -n "$COMPONENT" ]; then
        FILTERED_ISSUES_RESPONSE=$(echo "$ISSUES_RESPONSE" | jq --arg key "$ISSUE_KEY" --arg component "$COMPONENT" '{
          total: ([.issues[] | select(.key == $key and .component == $component)] | length),
          paging: .paging,
          issues: [.issues[] | select(.key == $key and .component == $component)],
          components: .components,
          rules: .rules,
          users: .users
        }' 2>/dev/null)
      else
        FILTERED_ISSUES_RESPONSE=$(echo "$ISSUES_RESPONSE" | jq --arg key "$ISSUE_KEY" '{
          total: ([.issues[] | select(.key == $key)] | length),
          paging: .paging,
          issues: [.issues[] | select(.key == $key)],
          components: .components,
          rules: .rules,
          users: .users
        }' 2>/dev/null)
      fi
      # If not found with resolved=false, try without the filter (might be a resolved issue)
      if [ -n "$FILTERED_ISSUES_RESPONSE" ] && [ "$(echo "$FILTERED_ISSUES_RESPONSE" | jq -r '.total // 0')" = "0" ] && [ -z "$STATUS" ]; then
        # Retry without resolved filter
        RETRY_PARAMS="${PARAMS//&resolved=false/}"
        RETRY_RESPONSE=$(curl -s -u "${SONAR_TOKEN}:" "${ISSUES_API_URL}?${RETRY_PARAMS}")
        if [ -n "$COMPONENT" ]; then
          FILTERED_ISSUES_RESPONSE=$(echo "$RETRY_RESPONSE" | jq --arg key "$ISSUE_KEY" --arg component "$COMPONENT" '{
            total: ([.issues[] | select(.key == $key and .component == $component)] | length),
            paging: .paging,
            issues: [.issues[] | select(.key == $key and .component == $component)],
            components: .components,
            rules: .rules,
            users: .users
          }' 2>/dev/null)
        else
          FILTERED_ISSUES_RESPONSE=$(echo "$RETRY_RESPONSE" | jq --arg key "$ISSUE_KEY" '{
            total: ([.issues[] | select(.key == $key)] | length),
            paging: .paging,
            issues: [.issues[] | select(.key == $key)],
            components: .components,
            rules: .rules,
            users: .users
          }' 2>/dev/null)
        fi
      fi
    else
      if [ -n "$COMPONENT" ]; then
        FILTERED_ISSUES_RESPONSE=$(echo "$ISSUES_RESPONSE" | jq --arg project "$PROJECT_KEY" --arg component "$COMPONENT" '{
          total: ([.issues[] | select(.project == $project and .component == $component)] | length),
          paging: .paging,
          issues: [.issues[] | select(.project == $project and .component == $component)],
          components: .components,
          rules: .rules,
          users: .users
        }' 2>/dev/null)
      else
        FILTERED_ISSUES_RESPONSE=$(echo "$ISSUES_RESPONSE" | jq --arg project "$PROJECT_KEY" '{
          total: ([.issues[] | select(.project == $project)] | length),
          paging: .paging,
          issues: [.issues[] | select(.project == $project)],
          components: .components,
          rules: .rules,
          users: .users
        }' 2>/dev/null)
      fi
    fi
    # Ensure we have valid JSON, default to empty if jq failed
    if [ -z "$FILTERED_ISSUES_RESPONSE" ] || ! echo "$FILTERED_ISSUES_RESPONSE" | jq empty 2>/dev/null; then
      FILTERED_ISSUES_RESPONSE='{"total": 0, "issues": []}'
    fi
    ISSUES_TOTAL=$(echo "$FILTERED_ISSUES_RESPONSE" | jq -r '.total // 0')
  fi
  
  # Process hotspots response
  FILTERED_HOTSPOTS_RESPONSE=""
  HOTSPOTS_TOTAL=0
  
  if [ "$FETCH_HOTSPOTS" = "true" ] && [ -n "$HOTSPOTS_RESPONSE" ]; then
    # Hotspots API response structure: {hotspots: [...], paging: {...}}
    # First check if response is valid JSON and has hotspots
    if ! echo "$HOTSPOTS_RESPONSE" | jq empty 2>/dev/null; then
      # Invalid JSON response
      FILTERED_HOTSPOTS_RESPONSE='{"total": 0, "hotspots": []}'
    else
      # Filter by component if provided, and filter by status if needed
      if [ -n "$COMPONENT" ]; then
        FILTERED_HOTSPOTS_RESPONSE=$(echo "$HOTSPOTS_RESPONSE" | jq --arg project "$PROJECT_KEY" --arg component "$COMPONENT" '{
          total: ([.hotspots[]? | select(.project == $project and .component == $component)] | length),
          paging: .paging,
          hotspots: [.hotspots[]? | select(.project == $project and .component == $component)]
        }' 2>/dev/null)
      else
        # Don't filter by project - hotspots API already filters by projectKey parameter
        # Extract all hotspots (API already filtered by pullRequest if provided)
        FILTERED_HOTSPOTS_RESPONSE=$(echo "$HOTSPOTS_RESPONSE" | jq '{
          total: ([.hotspots[]?] | length),
          paging: .paging,
          hotspots: [.hotspots[]?]
        }' 2>/dev/null)
      fi
    fi
    
    # Ensure we have valid JSON before further processing
    if [ -z "$FILTERED_HOTSPOTS_RESPONSE" ] || ! echo "$FILTERED_HOTSPOTS_RESPONSE" | jq empty 2>/dev/null; then
      FILTERED_HOTSPOTS_RESPONSE='{"total": 0, "hotspots": []}'
    fi
    
    # Filter by status if provided and not already filtered by API
    # Hotspots status values: TO_REVIEW, REVIEWED, FIXED, SAFE
    if [ -n "$STATUS" ]; then
      case "$STATUS" in
        TO_REVIEW|REVIEWED|FIXED|SAFE)
          # Already filtered by API, no need to filter again
          ;;
        *)
          # For other statuses (OPEN, CONFIRMED, etc.), filter to show only unresolved (TO_REVIEW)
          FILTERED_HOTSPOTS_RESPONSE=$(echo "$FILTERED_HOTSPOTS_RESPONSE" | jq '{
            total: ([.hotspots[] | select(.status == "TO_REVIEW")] | length),
            paging: .paging,
            hotspots: [.hotspots[] | select(.status == "TO_REVIEW")]
          }' 2>/dev/null)
          # Re-validate after filtering
          if [ -z "$FILTERED_HOTSPOTS_RESPONSE" ] || ! echo "$FILTERED_HOTSPOTS_RESPONSE" | jq empty 2>/dev/null; then
            FILTERED_HOTSPOTS_RESPONSE='{"total": 0, "hotspots": []}'
          fi
          ;;
      esac
    else
      # Default: show all hotspots (no status filter by default)
      # Note: Unlike issues which default to unresolved, hotspots are shown regardless of status
      # This matches the SonarQube UI behavior where all hotspots are visible
      : # No-op: all hotspots already included, no filtering needed
    fi
    
    HOTSPOTS_TOTAL=$(echo "$FILTERED_HOTSPOTS_RESPONSE" | jq -r '.total // 0')
  fi
  
  # Combine issues and hotspots into a unified response
  # Convert hotspots to issues-like format for unified display
  if [ -z "$FILTERED_ISSUES_RESPONSE" ] || [ "$FILTERED_ISSUES_RESPONSE" = "null" ]; then
    FILTERED_ISSUES_RESPONSE='{"total": 0, "issues": []}'
  fi
  if [ -z "$FILTERED_HOTSPOTS_RESPONSE" ] || [ "$FILTERED_HOTSPOTS_RESPONSE" = "null" ]; then
    FILTERED_HOTSPOTS_RESPONSE='{"total": 0, "hotspots": []}'
  fi
  
  # Ensure valid JSON before passing to jq
  if ! echo "$FILTERED_ISSUES_RESPONSE" | jq empty 2>/dev/null; then
    FILTERED_ISSUES_RESPONSE='{"total": 0, "issues": []}'
  fi
  if ! echo "$FILTERED_HOTSPOTS_RESPONSE" | jq empty 2>/dev/null; then
    FILTERED_HOTSPOTS_RESPONSE='{"total": 0, "hotspots": []}'
  fi
  
  # Determine paging from available response
  PAGING_VALUE="{}"
  if [ -n "$FILTERED_ISSUES_RESPONSE" ] && echo "$FILTERED_ISSUES_RESPONSE" | jq -e '.paging' >/dev/null 2>&1; then
    PAGING_VALUE=$(echo "$FILTERED_ISSUES_RESPONSE" | jq '.paging')
  elif [ -n "$FILTERED_HOTSPOTS_RESPONSE" ] && echo "$FILTERED_HOTSPOTS_RESPONSE" | jq -e '.paging' >/dev/null 2>&1; then
    PAGING_VALUE=$(echo "$FILTERED_HOTSPOTS_RESPONSE" | jq '.paging')
  fi
  
  COMBINED_RESPONSE=$(jq -n \
    --argjson issues "$FILTERED_ISSUES_RESPONSE" \
    --argjson hotspots "$FILTERED_HOTSPOTS_RESPONSE" \
    --argjson paging "$PAGING_VALUE" \
    '{
      issues: (
        (if $issues.issues then $issues.issues else [] end) +
        (if $hotspots.hotspots then [$hotspots.hotspots[] | . + {type: "SECURITY_HOTSPOT", isHotspot: true}] else [] end)
      ),
      hotspots: (if $hotspots.hotspots then $hotspots.hotspots else [] end),
      total: (
        (if $issues.total then $issues.total else 0 end) +
        (if $hotspots.total then $hotspots.total else 0 end)
      ),
      issuesTotal: (if $issues.total then $issues.total else 0 end),
      hotspotsTotal: (if $hotspots.total then $hotspots.total else 0 end),
      paging: $paging,
      components: (if $issues.components then $issues.components else [] end),
      rules: (if $issues.rules then $issues.rules else [] end),
      users: (if $issues.users then $issues.users else [] end)
    }')
  
  FILTERED_RESPONSE="$COMBINED_RESPONSE"
  TOTAL=$(echo "$FILTERED_RESPONSE" | jq -r '.total // 0')
  ISSUES_TOTAL=$(echo "$FILTERED_RESPONSE" | jq -r '.issuesTotal // 0')
  HOTSPOTS_TOTAL=$(echo "$FILTERED_RESPONSE" | jq -r '.hotspotsTotal // 0')
  
  # Output count only if --count flag is set
  if [ -n "$COUNT_ONLY" ]; then
    if [ -n "$JSON_OUTPUT" ]; then
      echo "$FILTERED_RESPONSE" | jq '{total: .total, issuesTotal: .issuesTotal, hotspotsTotal: .hotspotsTotal}'
    else
      if [ "$FETCH_ISSUES" = "true" ] && [ "$FETCH_HOTSPOTS" = "true" ]; then
        echo "Total: $TOTAL (Issues: $ISSUES_TOTAL, Security Hotspots: $HOTSPOTS_TOTAL)"
      elif [ "$FETCH_HOTSPOTS" = "true" ]; then
        echo "Total Security Hotspots: $HOTSPOTS_TOTAL"
      else
        echo "Total Issues: $ISSUES_TOTAL"
      fi
    fi
  elif [ -n "$JSON_OUTPUT" ]; then
    echo "$FILTERED_RESPONSE" | jq '.'
  else
    echo ""
    echo "=== Summary ==="
    if [ -n "$ISSUE_KEY" ]; then
      if [ "$FETCH_ISSUES" = "true" ] && [ "$FETCH_HOTSPOTS" = "true" ]; then
        echo "Total items found: $TOTAL (Issues: $ISSUES_TOTAL, Security Hotspots: $HOTSPOTS_TOTAL)"
      elif [ "$FETCH_HOTSPOTS" = "true" ]; then
        echo "Total security hotspots found: $HOTSPOTS_TOTAL"
      else
        echo "Total issues found: $ISSUES_TOTAL"
      fi
    else
      if [ "$FETCH_ISSUES" = "true" ] && [ "$FETCH_HOTSPOTS" = "true" ]; then
        echo "Total items for project '${PROJECT_KEY}': $TOTAL (Issues: $ISSUES_TOTAL, Security Hotspots: $HOTSPOTS_TOTAL)"
      elif [ "$FETCH_HOTSPOTS" = "true" ]; then
        echo "Total security hotspots for project '${PROJECT_KEY}': $HOTSPOTS_TOTAL"
      else
        echo "Total issues for project '${PROJECT_KEY}': $ISSUES_TOTAL"
      fi
    fi
    echo ""
    
    # Display each issue with all available details
    ISSUE_COUNT=$(echo "$FILTERED_RESPONSE" | jq -r '.issues | length // 0')
    
    # Only loop if there are items
    if [ -n "$ISSUE_COUNT" ] && [ "$ISSUE_COUNT" -gt 0 ]; then
      for i in $(seq 0 $((ISSUE_COUNT - 1))); do
      ITEM=$(echo "$FILTERED_RESPONSE" | jq ".issues[$i]")
      ITEM_KEY=$(echo "$ITEM" | jq -r '.key // "N/A"')
      IS_HOTSPOT=$(echo "$ITEM" | jq -r '.isHotspot // false')
      
      echo ""
      if [ "$IS_HOTSPOT" = "true" ]; then
        echo "Security Hotspot Key: $ITEM_KEY"
      else
        echo "Issue Key: $ITEM_KEY"
      fi
      echo "---"
      
      # Display all available fields
      if [ "$IS_HOTSPOT" = "true" ]; then
        # Display hotspot-specific fields
        echo "$ITEM" | jq -r '
          "Key:              \(.key // "N/A")
Severity:          \((.vulnerabilityProbability // .severity // "N/A") | ascii_upcase)
Type:              SECURITY_HOTSPOT
Status:            \(.status // "N/A")
Rule:              \(.ruleKey // .rule // "N/A")
Component:         \(.component // "N/A")
Project:           \(.project // "N/A")
Line:              \(.line // "N/A")
Message:           \(.message // "N/A")
Author:            \(.author // "N/A")
Creation Date:     \(.creationDate // "N/A")
Update Date:       \(.updateDate // "N/A")"
        '
      else
        # Display issue fields
        echo "$ITEM" | jq -r '
          "Key:              \(.key // "N/A")
Severity:          \((.severity // "N/A") | ascii_upcase)
Type:              \(.type // "N/A")
Status:            \(.status // "N/A")
Rule:              \(.rule // "N/A")
Component:         \(.component // "N/A")
Project:           \(.project // "N/A")
Line:              \(.line // "N/A")
Message:           \(.message // "N/A")
Author:            \(.author // "N/A")
Creation Date:     \(.creationDate // "N/A")
Update Date:       \(.updateDate // "N/A")
Resolution:        \(.resolution // "N/A")
Effort:            \(.effort // "N/A")
Debt:              \(.debt // "N/A")"
        '
      fi
      
      # Display text range if available
      TEXT_RANGE=$(echo "$ITEM" | jq '.textRange // empty')
      if [ -n "$TEXT_RANGE" ] && [ "$TEXT_RANGE" != "null" ]; then
        echo "Text Range:"
        echo "$ITEM" | jq -r '.textRange | "  Start Line:   \(.startLine // "N/A")
  Start Offset:  \(.startOffset // "N/A")
  End Line:      \(.endLine // "N/A")
  End Offset:    \(.endOffset // "N/A")"'
      fi
      
      # Display flows if available (for multi-location issues)
      FLOWS=$(echo "$ITEM" | jq '.flows // empty')
      if [ -n "$FLOWS" ] && [ "$FLOWS" != "null" ] && [ "$FLOWS" != "[]" ]; then
        echo "Flows:"
        echo "$ITEM" | jq -r '.flows[] | "  Flow with \(.locations | length) locations"'
      fi
      
      # Display URL
      ITEM_KEY=$(echo "$ITEM" | jq -r '.key')
      ITEM_PROJECT=$(echo "$ITEM" | jq -r '.project // "'${PROJECT_KEY}'"')
      if [ "$IS_HOTSPOT" = "true" ]; then
        echo "URL:              ${SONAR_HOST}security_hotspots?id=${ITEM_PROJECT}&hotspots=${ITEM_KEY}"
      else
        echo "URL:              ${SONAR_HOST}project/issues?id=${ITEM_PROJECT}&issues=${ITEM_KEY}&open=${ITEM_KEY}"
      fi
      echo ""
      done
    else
      if [ "$FETCH_ISSUES" = "true" ] && [ "$FETCH_HOTSPOTS" = "true" ]; then
        echo "No issues or security hotspots found."
      elif [ "$FETCH_HOTSPOTS" = "true" ]; then
        echo "No security hotspots found."
      else
        echo "No issues found."
      fi
    fi
  fi
else
  # Fallback if jq is not available
  if [ -n "$COUNT_ONLY" ]; then
    # Try to extract count using python
    ISSUES_COUNT=0
    HOTSPOTS_COUNT=0
    if [ "$FETCH_ISSUES" = "true" ] && [ -n "$ISSUES_RESPONSE" ]; then
      ISSUES_COUNT=$(echo "$ISSUES_RESPONSE" | python3 -c "import sys, json; data = json.load(sys.stdin); print(len(data.get('issues', [])))" 2>/dev/null || echo "0")
    fi
    if [ "$FETCH_HOTSPOTS" = "true" ] && [ -n "$HOTSPOTS_RESPONSE" ]; then
      HOTSPOTS_COUNT=$(echo "$HOTSPOTS_RESPONSE" | python3 -c "import sys, json; data = json.load(sys.stdin); print(len(data.get('hotspots', [])))" 2>/dev/null || echo "0")
    fi
    TOTAL=$((ISSUES_COUNT + HOTSPOTS_COUNT))
    if [ -n "$JSON_OUTPUT" ]; then
      echo "{\"total\": $TOTAL, \"issuesTotal\": $ISSUES_COUNT, \"hotspotsTotal\": $HOTSPOTS_COUNT}"
    else
      if [ "$FETCH_ISSUES" = "true" ] && [ "$FETCH_HOTSPOTS" = "true" ]; then
        echo "Total: $TOTAL (Issues: $ISSUES_COUNT, Security Hotspots: $HOTSPOTS_COUNT)"
      elif [ "$FETCH_HOTSPOTS" = "true" ]; then
        echo "Total Security Hotspots: $HOTSPOTS_COUNT"
      else
        echo "Total Issues: $ISSUES_COUNT"
      fi
    fi
  else
    # Always outputs JSON when jq is not available
    if [ "$FETCH_ISSUES" = "true" ] && [ "$FETCH_HOTSPOTS" = "true" ]; then
      echo "{\"issues\": $ISSUES_RESPONSE, \"hotspots\": $HOTSPOTS_RESPONSE}" | python3 -m json.tool 2>/dev/null || echo "{\"issues\": $ISSUES_RESPONSE, \"hotspots\": $HOTSPOTS_RESPONSE}"
    elif [ "$FETCH_HOTSPOTS" = "true" ]; then
      echo "$HOTSPOTS_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$HOTSPOTS_RESPONSE"
    else
      echo "$ISSUES_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$ISSUES_RESPONSE"
    fi
  fi
fi

