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
DETAILS=""

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
    --details)
      DETAILS="1"
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
      echo "  --details                      Include detailed information (risk, fix guidance, etc.)"
      echo "                                Note: Details are always included when searching by key (-k)"
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
      echo "  $0 --details                          List all issues with detailed information"
      echo "  $0 -k AZsvly6yO42lZpvH9OC5            Show details for a specific issue (details auto-included)"
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
ISSUE_DETAIL_API_URL="${SONAR_HOST}api/issues/show"
HOTSPOT_DETAIL_API_URL="${SONAR_HOST}api/hotspots/show"

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
# Note: When searching by issue key, search both issues and hotspots (key could be either)
FETCH_ISSUES="false"
FETCH_HOTSPOTS="false"

if [ -n "$ISSUE_KEY" ]; then
  # Issue key search applies to both issues and hotspots (key could be either)
  FETCH_ISSUES="true"
  FETCH_HOTSPOTS="true"
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
      # When searching by issue key, filter by key client-side (API doesn't support key parameter)
      if [ -n "$ISSUE_KEY" ]; then
        if [ -n "$COMPONENT" ]; then
          FILTERED_HOTSPOTS_RESPONSE=$(echo "$HOTSPOTS_RESPONSE" | jq --arg key "$ISSUE_KEY" --arg component "$COMPONENT" '{
            total: ([.hotspots[]? | select(.key == $key and .component == $component)] | length),
            paging: .paging,
            hotspots: [.hotspots[]? | select(.key == $key and .component == $component)]
          }' 2>/dev/null)
        else
          FILTERED_HOTSPOTS_RESPONSE=$(echo "$HOTSPOTS_RESPONSE" | jq --arg key "$ISSUE_KEY" '{
            total: ([.hotspots[]? | select(.key == $key)] | length),
            paging: .paging,
            hotspots: [.hotspots[]? | select(.key == $key)]
          }' 2>/dev/null)
        fi
      elif [ -n "$COMPONENT" ]; then
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
    # Fetch detailed information if requested (--details flag or when searching by key)
    FETCH_DETAILS="false"
    if [ -n "$DETAILS" ] || [ -n "$ISSUE_KEY" ]; then
      FETCH_DETAILS="true"
    fi
    
    # If fetching details, enrich each item with detailed information
    if [ "$FETCH_DETAILS" = "true" ]; then
      ISSUE_COUNT=$(echo "$FILTERED_RESPONSE" | jq -r '.issues | length // 0')
      ENRICHED_ITEMS="[]"
      
      for i in $(seq 0 $((ISSUE_COUNT - 1))); do
        ITEM=$(echo "$FILTERED_RESPONSE" | jq ".issues[$i]")
        ITEM_KEY=$(echo "$ITEM" | jq -r '.key // ""')
        IS_HOTSPOT=$(echo "$ITEM" | jq -r '.isHotspot // false')
        
        if [ -n "$ITEM_KEY" ] && [ "$ITEM_KEY" != "N/A" ]; then
          DETAIL_RESPONSE=""
          if [ "$IS_HOTSPOT" = "true" ]; then
            # Fetch hotspot details
            DETAIL_RESPONSE=$(curl -s -u "${SONAR_TOKEN}:" "${HOTSPOT_DETAIL_API_URL}?hotspot=${ITEM_KEY}")
          else
            # Fetch issue details
            DETAIL_RESPONSE=$(curl -s -u "${SONAR_TOKEN}:" "${ISSUE_DETAIL_API_URL}?issue=${ITEM_KEY}")
          fi
          
          # Merge detail response with item if valid
          if [ -n "$DETAIL_RESPONSE" ] && echo "$DETAIL_RESPONSE" | jq empty 2>/dev/null; then
            ERROR_MSG=$(echo "$DETAIL_RESPONSE" | jq -r '.errors[]?.msg // empty' 2>/dev/null)
            if [ -z "$ERROR_MSG" ]; then
              # Extract the actual detail data (API may return nested structure)
              if [ "$IS_HOTSPOT" = "true" ]; then
                # Hotspot detail API returns {hotspot: {...}}
                DETAIL_DATA=$(echo "$DETAIL_RESPONSE" | jq '.hotspot // . // {}')
              else
                # Issue detail API returns {issue: {...}}
                DETAIL_DATA=$(echo "$DETAIL_RESPONSE" | jq '.issue // . // {}')
              fi
              
              # Merge the detail data into the item
              if [ -n "$DETAIL_DATA" ] && [ "$DETAIL_DATA" != "null" ] && [ "$DETAIL_DATA" != "{}" ]; then
                ITEM=$(echo "$ITEM" | jq --argjson details "$DETAIL_DATA" '. + $details')
              fi
            fi
          fi
        fi
        
        # Add enriched item to array
        ENRICHED_ITEMS=$(echo "$ENRICHED_ITEMS" | jq --argjson item "$ITEM" '. + [$item]')
      done
      
      # Replace issues in filtered response with enriched items
      FILTERED_RESPONSE=$(echo "$FILTERED_RESPONSE" | jq --argjson items "$ENRICHED_ITEMS" '.issues = $items')
    fi
    
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
      
      # Display all available fields with aligned values
      if [ "$IS_HOTSPOT" = "true" ]; then
        # Display hotspot-specific fields
        KEY=$(echo "$ITEM" | jq -r '.key // "N/A"')
        SEVERITY=$(echo "$ITEM" | jq -r '(.vulnerabilityProbability // .severity // "N/A") | ascii_upcase')
        STATUS=$(echo "$ITEM" | jq -r '.status // "N/A"')
        RULE=$(echo "$ITEM" | jq -r '.ruleKey // .rule // "N/A"')
        COMPONENT=$(echo "$ITEM" | jq -r '.component // "N/A"')
        PROJECT=$(echo "$ITEM" | jq -r '.project // "N/A"')
        LINE=$(echo "$ITEM" | jq -r '.line // "N/A"')
        MESSAGE=$(echo "$ITEM" | jq -r '.message // "N/A"')
        AUTHOR=$(echo "$ITEM" | jq -r '.author // "N/A"')
        CREATION_DATE=$(echo "$ITEM" | jq -r '.creationDate // "N/A"')
        UPDATE_DATE=$(echo "$ITEM" | jq -r '.updateDate // "N/A"')
        
        printf "Key:              %s\n" "$KEY"
        printf "Severity:         %s\n" "$SEVERITY"
        printf "Type:             %s\n" "SECURITY_HOTSPOT"
        printf "Status:           %s\n" "$STATUS"
        printf "Rule:             %s\n" "$RULE"
        printf "Component:        %s\n" "$COMPONENT"
        printf "Project:          %s\n" "$PROJECT"
        printf "Line:             %s\n" "$LINE"
        printf "Author:           %s\n" "$AUTHOR"
        printf "Creation Date:    %s\n" "$CREATION_DATE"
        printf "Update Date:      %s\n" "$UPDATE_DATE"
        
        # Display message with same pattern as body content in PR comments script
        if [ -n "$MESSAGE" ] && [ "$MESSAGE" != "N/A" ] && [ "$MESSAGE" != "" ]; then
          echo "Message:"
          echo ""
          echo "$MESSAGE" | sed 's/^/                   /'
          echo ""
        fi
      else
        # Display issue fields
        KEY=$(echo "$ITEM" | jq -r '.key // "N/A"')
        SEVERITY=$(echo "$ITEM" | jq -r '(.severity // "N/A") | ascii_upcase')
        TYPE=$(echo "$ITEM" | jq -r '.type // "N/A"')
        STATUS=$(echo "$ITEM" | jq -r '.status // "N/A"')
        RULE=$(echo "$ITEM" | jq -r '.rule // "N/A"')
        COMPONENT=$(echo "$ITEM" | jq -r '.component // "N/A"')
        PROJECT=$(echo "$ITEM" | jq -r '.project // "N/A"')
        LINE=$(echo "$ITEM" | jq -r '.line // "N/A"')
        MESSAGE=$(echo "$ITEM" | jq -r '.message // "N/A"')
        AUTHOR=$(echo "$ITEM" | jq -r '.author // "N/A"')
        CREATION_DATE=$(echo "$ITEM" | jq -r '.creationDate // "N/A"')
        UPDATE_DATE=$(echo "$ITEM" | jq -r '.updateDate // "N/A"')
        RESOLUTION=$(echo "$ITEM" | jq -r '.resolution // "N/A"')
        EFFORT=$(echo "$ITEM" | jq -r '.effort // "N/A"')
        DEBT=$(echo "$ITEM" | jq -r '.debt // "N/A"')
        
        printf "Key:              %s\n" "$KEY"
        printf "Severity:         %s\n" "$SEVERITY"
        printf "Type:             %s\n" "$TYPE"
        printf "Status:           %s\n" "$STATUS"
        printf "Rule:             %s\n" "$RULE"
        printf "Component:        %s\n" "$COMPONENT"
        printf "Project:          %s\n" "$PROJECT"
        printf "Line:             %s\n" "$LINE"
        printf "Author:           %s\n" "$AUTHOR"
        printf "Creation Date:    %s\n" "$CREATION_DATE"
        printf "Update Date:      %s\n" "$UPDATE_DATE"
        printf "Resolution:       %s\n" "$RESOLUTION"
        printf "Effort:           %s\n" "$EFFORT"
        printf "Debt:             %s\n" "$DEBT"
        
        # Display message with same pattern as body content in PR comments script
        if [ -n "$MESSAGE" ] && [ "$MESSAGE" != "N/A" ] && [ "$MESSAGE" != "" ]; then
          echo "Message:"
          echo ""
          echo "$MESSAGE" | sed 's/^/                   /'
          echo ""
        fi
      fi
      
      # Display text range if available
      TEXT_RANGE=$(echo "$ITEM" | jq '.textRange // empty')
      if [ -n "$TEXT_RANGE" ] && [ "$TEXT_RANGE" != "null" ]; then
        START_LINE=$(echo "$ITEM" | jq -r '.textRange.startLine // "N/A"')
        START_OFFSET=$(echo "$ITEM" | jq -r '.textRange.startOffset // "N/A"')
        END_LINE=$(echo "$ITEM" | jq -r '.textRange.endLine // "N/A"')
        END_OFFSET=$(echo "$ITEM" | jq -r '.textRange.endOffset // "N/A"')
        echo "Text Range:"
        printf "  Start Line:     %s\n" "$START_LINE"
        printf "  Start Offset:   %s\n" "$START_OFFSET"
        printf "  End Line:       %s\n" "$END_LINE"
        printf "  End Offset:     %s\n" "$END_OFFSET"
      fi
      
      # Display flows if available (for multi-location issues)
      FLOWS=$(echo "$ITEM" | jq '.flows // empty')
      if [ -n "$FLOWS" ] && [ "$FLOWS" != "null" ] && [ "$FLOWS" != "[]" ]; then
        echo "Flows:"
        echo "$ITEM" | jq -r '.flows[] | "  Flow with \(.locations | length) locations"'
      fi
      
      # Display detailed information if available (from detail API call)
      if [ "$FETCH_DETAILS" = "true" ]; then
        # For hotspots, display risk and fix guidance
        if [ "$IS_HOTSPOT" = "true" ]; then
          # Try various possible field names for risk description
          RISK_DESCRIPTION=$(echo "$ITEM" | jq -r '.riskDescription // .message // .rule.description // empty' 2>/dev/null)
          VULNERABILITY_DESCRIPTION=$(echo "$ITEM" | jq -r '.vulnerabilityDescription // .rule.vulnerabilityDescription // empty' 2>/dev/null)
          FIX_RECOMMENDATIONS=$(echo "$ITEM" | jq -r '.fixRecommendations // .rule.fixRecommendations // .rule.remediation.func // empty' 2>/dev/null)
          RULE_DESCRIPTION=$(echo "$ITEM" | jq -r '.rule.description // .rule.htmlDescription // empty' 2>/dev/null)
          
          if [ -n "$RULE_DESCRIPTION" ] && [ "$RULE_DESCRIPTION" != "null" ] && [ "$RULE_DESCRIPTION" != "" ]; then
            echo ""
            echo "Rule Description:"
            # Strip HTML tags if present and indent
            echo "$RULE_DESCRIPTION" | sed 's/<[^>]*>//g' | sed 's/^/  /'
          fi
          
          if [ -n "$RISK_DESCRIPTION" ] && [ "$RISK_DESCRIPTION" != "null" ] && [ "$RISK_DESCRIPTION" != "" ] && [ "$RISK_DESCRIPTION" != "$RULE_DESCRIPTION" ]; then
            echo ""
            echo "What's the risk?:"
            echo "$RISK_DESCRIPTION" | sed 's/<[^>]*>//g' | sed 's/^/  /'
          fi
          
          if [ -n "$VULNERABILITY_DESCRIPTION" ] && [ "$VULNERABILITY_DESCRIPTION" != "null" ] && [ "$VULNERABILITY_DESCRIPTION" != "" ]; then
            echo ""
            echo "Vulnerability Description:"
            echo "$VULNERABILITY_DESCRIPTION" | sed 's/<[^>]*>//g' | sed 's/^/  /'
          fi
          
          if [ -n "$FIX_RECOMMENDATIONS" ] && [ "$FIX_RECOMMENDATIONS" != "null" ] && [ "$FIX_RECOMMENDATIONS" != "" ]; then
            echo ""
            echo "How can I fix it?:"
            echo "$FIX_RECOMMENDATIONS" | sed 's/<[^>]*>//g' | sed 's/^/  /'
          fi
        else
          # For issues, display rule description, "Why is this an issue?", and other details
          RULE_DESCRIPTION=$(echo "$ITEM" | jq -r '.rule.description // .rule.htmlDescription // .ruleDescription // empty' 2>/dev/null)
          RULE_NAME=$(echo "$ITEM" | jq -r '.rule.name // empty' 2>/dev/null)
          WHY_IS_THIS_AN_ISSUE=$(echo "$ITEM" | jq -r '.rule.whyIsThisAnIssue // .whyIsThisAnIssue // .rule.htmlNote // .rule.note // empty' 2>/dev/null)
          HOW_TO_FIX_IT=$(echo "$ITEM" | jq -r '.rule.howToFixIt // .howToFixIt // .rule.remediation.func // empty' 2>/dev/null)
          
          if [ -n "$RULE_NAME" ] && [ "$RULE_NAME" != "null" ] && [ "$RULE_NAME" != "" ]; then
            echo ""
            echo "Rule Name:"
            echo "  $RULE_NAME"
          fi
          
          if [ -n "$RULE_DESCRIPTION" ] && [ "$RULE_DESCRIPTION" != "null" ] && [ "$RULE_DESCRIPTION" != "" ]; then
            echo ""
            echo "Rule Description:"
            # Strip HTML tags if present and indent
            echo "$RULE_DESCRIPTION" | sed 's/<[^>]*>//g' | sed 's/^/  /'
          fi
          
          if [ -n "$WHY_IS_THIS_AN_ISSUE" ] && [ "$WHY_IS_THIS_AN_ISSUE" != "null" ] && [ "$WHY_IS_THIS_AN_ISSUE" != "" ]; then
            echo ""
            echo "Why is this an issue?:"
            # Strip HTML tags if present and indent
            echo "$WHY_IS_THIS_AN_ISSUE" | sed 's/<[^>]*>//g' | sed 's/^/  /'
          fi
          
          if [ -n "$HOW_TO_FIX_IT" ] && [ "$HOW_TO_FIX_IT" != "null" ] && [ "$HOW_TO_FIX_IT" != "" ]; then
            echo ""
            echo "How can I fix it?:"
            # Strip HTML tags if present and indent
            echo "$HOW_TO_FIX_IT" | sed 's/<[^>]*>//g' | sed 's/^/  /'
          fi
        fi
      fi
      
      # Display URL
      ITEM_KEY=$(echo "$ITEM" | jq -r '.key')
      ITEM_PROJECT=$(echo "$ITEM" | jq -r '.project // "'${PROJECT_KEY}'"')
      if [ "$IS_HOTSPOT" = "true" ]; then
        URL="${SONAR_HOST}security_hotspots?id=${ITEM_PROJECT}&hotspots=${ITEM_KEY}"
      else
        URL="${SONAR_HOST}project/issues?id=${ITEM_PROJECT}&issues=${ITEM_KEY}&open=${ITEM_KEY}"
      fi
      printf "URL:              %s\n" "$URL"
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
    
    # Display summary at the end
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

