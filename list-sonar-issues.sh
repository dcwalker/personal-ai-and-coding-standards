#!/bin/bash

# Script to list SonarQube issues for this project
# Usage: ./list-sonar-issues.sh [OPTIONS]
# Run with -h or --help for full usage information

SONAR_HOST="${SONAR_HOST_URL}"
SONAR_HOST="${SONAR_HOST%/}/"  # Ensure trailing slash
SONAR_TOKEN="${SONAR_TOKEN}"

# Try to get project key from environment variable, or read from sonar-project.properties
if [ -n "$SONAR_PROJECT_KEY" ]; then
  PROJECT_KEY="$SONAR_PROJECT_KEY"
elif [ -f "sonar-project.properties" ]; then
  PROJECT_KEY=$(grep "^sonar.projectKey=" sonar-project.properties 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
  if [ -z "$PROJECT_KEY" ]; then
    echo "Error: Could not find sonar.projectKey in sonar-project.properties"
    exit 1
  fi
else
  echo "Error: SONAR_PROJECT_KEY environment variable is not set and sonar-project.properties file not found"
  exit 1
fi

PULL_REQUEST=""
SEVERITY=""
TYPE=""
STATUS=""
RULE=""
ISSUE_KEY=""
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
      echo "  -t, --type <type>             Filter by type: CODE_SMELL, BUG, VULNERABILITY"
      echo "  --status <status>             Filter by status: OPEN, CONFIRMED, REOPENED, RESOLVED, CLOSED"
      echo "  -r, --rule <ruleKey>          Filter by rule key (e.g., typescript:S6606)"
      echo "  -k, --key <issueKey>          Filter by specific issue key (e.g., AZsvly6yO42lZpvH9OC5)"
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
      echo "  $0 -r typescript:S6606                List issues for a specific rule"
      echo "  $0 -k AZsvly6yO42lZpvH9OC5            Show details for a specific issue"
      echo "                                       Note: Issue key search may not find issues"
      echo "                                       that only exist in PR context. Use -pr with"
      echo "                                       the key for better results."
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

# Build API URL
API_URL="${SONAR_HOST}api/issues/search"

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
if [ -n "$TYPE" ]; then
  # Validate type value
  case "$TYPE" in
    CODE_SMELL|BUG|VULNERABILITY)
      PARAMS="${PARAMS}&types=${TYPE}"
      FILTER_MSG="${FILTER_MSG}, Type: ${TYPE}"
      ;;
    *)
      echo "Error: Invalid type '${TYPE}'. Must be one of: CODE_SMELL, BUG, VULNERABILITY"
      exit 1
      ;;
  esac
fi

# Add rule filter if provided
if [ -n "$RULE" ]; then
  PARAMS="${PARAMS}&rules=${RULE}"
  FILTER_MSG="${FILTER_MSG}, Rule: ${RULE}"
fi

# Issue key filter is already handled above in the initial PARAMS setup

if [ -z "$JSON_OUTPUT" ]; then
  echo "$FILTER_MSG"
fi

# Make API request
RESPONSE=$(curl -s -u "${SONAR_TOKEN}:" "${API_URL}?${PARAMS}")

# Check if jq is available for pretty formatting
if command -v jq &> /dev/null; then
  # When searching by issue key, filter by key client-side (API 'issues' parameter is unreliable)
  # When searching by key, we search broadly, so we only filter by key (not project)
  # Otherwise, filter issues to only include our project (API sometimes returns issues from other projects)
  if [ -n "$ISSUE_KEY" ]; then
    FILTERED_RESPONSE=$(echo "$RESPONSE" | jq --arg key "$ISSUE_KEY" '{
      total: ([.issues[] | select(.key == $key)] | length),
      paging: .paging,
      issues: [.issues[] | select(.key == $key)],
      components: .components,
      rules: .rules,
      users: .users
    }')
    # If not found with resolved=false, try without the filter (might be a resolved issue)
    if [ "$(echo "$FILTERED_RESPONSE" | jq -r '.total')" = "0" ] && [ -z "$STATUS" ]; then
      # Retry without resolved filter
      RETRY_PARAMS="${PARAMS//&resolved=false/}"
      RETRY_RESPONSE=$(curl -s -u "${SONAR_TOKEN}:" "${API_URL}?${RETRY_PARAMS}")
      FILTERED_RESPONSE=$(echo "$RETRY_RESPONSE" | jq --arg key "$ISSUE_KEY" '{
        total: ([.issues[] | select(.key == $key)] | length),
        paging: .paging,
        issues: [.issues[] | select(.key == $key)],
        components: .components,
        rules: .rules,
        users: .users
      }')
    fi
  else
    FILTERED_RESPONSE=$(echo "$RESPONSE" | jq --arg project "$PROJECT_KEY" '{
      total: ([.issues[] | select(.project == $project)] | length),
      paging: .paging,
      issues: [.issues[] | select(.project == $project)],
      components: .components,
      rules: .rules,
      users: .users
    }')
  fi
  
  TOTAL=$(echo "$FILTERED_RESPONSE" | jq -r '.total // 0')
  
  # Output count only if --count flag is set
  if [ -n "$COUNT_ONLY" ]; then
    if [ -n "$JSON_OUTPUT" ]; then
      echo "$FILTERED_RESPONSE" | jq '{total: .total}'
    else
      echo "Total: $TOTAL"
    fi
  elif [ -n "$JSON_OUTPUT" ]; then
    echo "$FILTERED_RESPONSE" | jq '.'
  else
    echo ""
    echo "=== Issues Summary ==="
    if [ -n "$ISSUE_KEY" ]; then
      echo "Total issues found: $TOTAL"
    else
      echo "Total issues for project '${PROJECT_KEY}': $TOTAL"
    fi
    echo ""
    
    # Display each issue with all available details
    ISSUE_COUNT=$(echo "$FILTERED_RESPONSE" | jq '.issues | length')
    
    # Only loop if there are issues
    if [ "$ISSUE_COUNT" -gt 0 ]; then
      for i in $(seq 0 $((ISSUE_COUNT - 1))); do
      ISSUE=$(echo "$FILTERED_RESPONSE" | jq ".issues[$i]")
      
      echo ""
      echo "Issue #$((i + 1))"
      echo "---"
      
      # Display all available fields
      echo "$ISSUE" | jq -r '
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
      
      # Display text range if available
      TEXT_RANGE=$(echo "$ISSUE" | jq '.textRange // empty')
      if [ -n "$TEXT_RANGE" ] && [ "$TEXT_RANGE" != "null" ]; then
        echo "Text Range:"
        echo "$ISSUE" | jq -r '.textRange | "  Start Line:   \(.startLine // "N/A")
  Start Offset:  \(.startOffset // "N/A")
  End Line:      \(.endLine // "N/A")
  End Offset:    \(.endOffset // "N/A")"'
      fi
      
      # Display flows if available (for multi-location issues)
      FLOWS=$(echo "$ISSUE" | jq '.flows // empty')
      if [ -n "$FLOWS" ] && [ "$FLOWS" != "null" ] && [ "$FLOWS" != "[]" ]; then
        echo "Flows:"
        echo "$ISSUE" | jq -r '.flows[] | "  Flow with \(.locations | length) locations"'
      fi
      
        # Display URL
        ISSUE_KEY_VALUE=$(echo "$ISSUE" | jq -r '.key')
        ISSUE_PROJECT=$(echo "$ISSUE" | jq -r '.project // "'${PROJECT_KEY}'"')
        echo "URL:              ${SONAR_HOST}project/issues?id=${ISSUE_PROJECT}&issues=${ISSUE_KEY_VALUE}&open=${ISSUE_KEY_VALUE}"
        echo ""
      done
    else
      echo "No issues found."
    fi
  fi
else
  # Fallback if jq is not available
  if [ -n "$COUNT_ONLY" ]; then
    # Try to extract count using python
    COUNT=$(echo "$RESPONSE" | python3 -c "import sys, json; data = json.load(sys.stdin); print(len(data.get('issues', [])))" 2>/dev/null || echo "0")
    if [ -n "$JSON_OUTPUT" ]; then
      echo "{\"total\": $COUNT}"
    else
      echo "Total: $COUNT"
    fi
  else
    # Always outputs JSON when jq is not available
    echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
  fi
fi

