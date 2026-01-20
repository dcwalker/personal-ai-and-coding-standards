#!/bin/bash

# Script to list all status checks for a pull request
# Usage: ./list-pr-checks.sh [OPTIONS]
# Run with -h or --help for full usage information

# Auto-detect repository from git remote
REPO=$(git remote get-url origin 2>/dev/null | sed -E 's/.*github.com[:/]([^/]+)\/([^/]+)(\.git)?$/\1\/\2/' | sed 's/\.git$//')
if [ -z "$REPO" ]; then
  if [ -n "$GITHUB_REPOSITORY" ]; then
    REPO="$GITHUB_REPOSITORY"
  else
    echo "Error: Could not detect repository. Set GITHUB_REPOSITORY environment variable or run from a git repository."
    exit 1
  fi
fi

# Extract owner and repo name
OWNER=$(echo "$REPO" | cut -d'/' -f1)
REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)

# CircleCI project slug format: vcs-type/org/repo (e.g., gh/owner/repo)
# Default to GitHub (gh) if not specified
if [ -n "$CIRCLE_PROJECT_SLUG" ]; then
  PROJECT_SLUG="$CIRCLE_PROJECT_SLUG"
else
  PROJECT_SLUG="gh/${OWNER}/${REPO_NAME}"
fi

# Extract vcs-type, org, and repo from project slug
VCS_TYPE=$(echo "$PROJECT_SLUG" | cut -d'/' -f1)
ORG=$(echo "$PROJECT_SLUG" | cut -d'/' -f2)
PROJECT_REPO=$(echo "$PROJECT_SLUG" | cut -d'/' -f3)

PULL_REQUEST=""
WORKFLOW_FILTER=""
JOB_FILTER=""
SHOW_FAILING=""
SHOW_PASSING=""
SHOW_IN_PROGRESS=""
JSON_OUTPUT=""
COUNT_ONLY=""
DETAILS=""
HIDE_JOB_OUTPUT=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -pr|--pull-request)
      PULL_REQUEST="$2"
      shift 2
      ;;
    -w|--workflow)
      WORKFLOW_FILTER="$2"
      shift 2
      ;;
    -j|--job)
      JOB_FILTER="$2"
      shift 2
      ;;
    --show-failing)
      SHOW_FAILING="1"
      shift
      ;;
    --show-passing)
      SHOW_PASSING="1"
      shift
      ;;
    --show-in-progress)
      SHOW_IN_PROGRESS="1"
      shift
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
    --hide-job-output)
      HIDE_JOB_OUTPUT="1"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -pr, --pull-request <number>  Filter by pull request number (required)"
      echo "  -w, --workflow <name>          Filter by workflow name (CircleCI checks only)"
      echo "  -j, --job <name>              Filter by check/job name"
      echo "  --show-failing                 Filter to show only failing/errored checks (default: show all statuses)"
      echo "  --show-passing                 Filter to show only passing/successful checks (default: show all statuses)"
      echo "  --show-in-progress             Filter to show only in-progress/running checks (default: show all statuses)"
      echo "  --json                         Output only JSON (no formatted text)"
      echo "  --count                        Output only the count of items"
      echo "  --details                      Include detailed information (test failures, step logs, CircleCI only)"
      echo "  --hide-job-output              Hide job output for failed checks (default: show output for failed CircleCI checks)"
      echo "  -h, --help                     Show this help message"
      echo ""
      echo "Note: By default, only checks from the most recent pipeline/run are shown (matching GitHub UI)."
      echo ""
      echo "Note: Status filters (--show-failing, --show-passing, --show-in-progress) can be combined."
      echo "      If multiple are specified, checks matching any of the specified statuses will be shown (OR logic)."
      echo ""
      echo "Environment Variables:"
      echo "  CIRCLE_TOKEN                   CircleCI API token (required for CircleCI check details)"
      echo "                                Documentation: https://circleci.com/docs/managing-api-tokens/"
      echo "  CIRCLE_PROJECT_SLUG            Optional project slug override (format: vcs-type/org/repo, e.g., gh/owner/repo)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use -h or --help for usage information"
      exit 1
      ;;
  esac
done

# Note: CIRCLE_TOKEN is only required if there are CircleCI checks to enrich
# We'll validate it later when we actually need it

# Validate PR number is provided
if [ -z "$PULL_REQUEST" ]; then
  echo "Error: Pull request number is required. Use -pr or --pull-request to specify the PR number."
  echo "Use -h or --help for usage information"
  exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo "Error: jq is not installed. Install it to use this script."
  exit 1
fi

# Check if curl is available
if ! command -v curl &> /dev/null; then
  echo "Error: curl is not installed. Install it to use this script."
  exit 1
fi

# Check if gh CLI is available (for GitHub API)
if ! command -v gh &> /dev/null; then
  echo "Error: GitHub CLI (gh) is not installed or not in PATH"
  echo "Install it from: https://cli.github.com/"
  exit 1
fi

# Check if gh is authenticated
if ! gh auth status &> /dev/null; then
  echo "Error: GitHub CLI is not authenticated."
  if [ -n "$GITHUB_TOKEN" ]; then
    echo ""
    echo "The GITHUB_TOKEN environment variable is set but appears to be invalid or expired."
    echo "To fix this, you can either:"
    echo "  1. Clear the invalid token: unset GITHUB_TOKEN"
    echo "  2. Set a valid token: export GITHUB_TOKEN=your_valid_token"
    echo "  3. Use GitHub CLI credentials: unset GITHUB_TOKEN && gh auth login"
  else
    echo "Run: gh auth login"
  fi
  exit 1
fi

# CircleCI API base URL
CIRCLE_API_BASE="https://circleci.com/api/v2"

# Function to make CircleCI API request
circleci_api_request() {
  local url="$1"
  local response
  response=$(curl -s -H "Circle-Token: ${CIRCLE_TOKEN}" "$url")
  local exit_code=$?
  
  if [ $exit_code -ne 0 ]; then
    echo "Error: Failed to make API request to $url" >&2
    return 1
  fi
  
  # Check for API errors in response
  if echo "$response" | jq -e '.message // .error // empty' >/dev/null 2>&1; then
    local error_msg
    error_msg=$(echo "$response" | jq -r '.message // .error // "Unknown error"')
    echo "Error: CircleCI API returned: $error_msg" >&2
    return 1
  fi
  
  echo "$response"
}

# Function to get PR branch name from GitHub
get_pr_branch() {
  local pr_num="$1"
  
  local branch_info
  branch_info=$(gh api "repos/${REPO}/pulls/${pr_num}" 2>/dev/null | jq -r '.head.ref // empty' 2>/dev/null)
  if [ -n "$branch_info" ] && [ "$branch_info" != "null" ]; then
    echo "$branch_info"
    return 0
  fi
  
  return 1
}

# Function to get all status checks for a PR from GitHub
get_github_status_checks() {
  local pr_num="$1"
  
  # Get PR details to get the head SHA
  local pr_data
  pr_data=$(gh api "repos/${REPO}/pulls/${pr_num}" 2>/dev/null)
  if [ $? -ne 0 ] || [ -z "$pr_data" ]; then
    echo "[]"
    return 0
  fi
  
  local head_sha
  head_sha=$(echo "$pr_data" | jq -r '.head.sha // empty' 2>/dev/null)
  if [ -z "$head_sha" ] || [ "$head_sha" = "null" ]; then
    echo "[]"
    return 0
  fi
  
  # Get check runs for the commit (REST API - more reliable)
  local check_runs
  check_runs=$(gh api "repos/${REPO}/commits/${head_sha}/check-runs?per_page=100" 2>/dev/null)
  local check_runs_exit=$?
  
  # Get status contexts for the commit (REST API)
  local statuses
  statuses=$(gh api "repos/${REPO}/commits/${head_sha}/status" 2>/dev/null)
  local statuses_exit=$?
  
  local all_checks="[]"
  
  # Process check runs
  if [ $check_runs_exit -eq 0 ] && [ -n "$check_runs" ]; then
    local runs
    runs=$(echo "$check_runs" | jq -r '
      .check_runs[]? | {
        name: .name,
        status: (if .status == "completed" then (.conclusion | ascii_downcase) else (.status | ascii_downcase) end),
        conclusion: (.conclusion // "" | ascii_downcase),
        description: (.output.summary // .app.name // "Unknown"),
        html_url: .html_url,
        started_at: .started_at,
        completed_at: .completed_at,
        context: .name,
        is_circleci: ((.app.slug // .app.name // "") | test("circleci"; "i")),
        type: "check_run"
      }
    ' 2>/dev/null | jq -s '.' 2>/dev/null)
    
    if [ -n "$runs" ] && [ "$runs" != "null" ] && [ "$runs" != "[]" ]; then
      all_checks=$(echo "$all_checks" | jq --argjson runs "$runs" '. + $runs' 2>/dev/null || echo "$all_checks")
    fi
  fi
  
  # Process status contexts
  if [ $statuses_exit -eq 0 ] && [ -n "$statuses" ]; then
    local contexts
    contexts=$(echo "$statuses" | jq -r '
      .statuses[]? | {
        name: .context,
        status: (.state | ascii_downcase),
        conclusion: (.state | ascii_downcase),
        description: .description // "",
        html_url: .target_url,
        started_at: null,
        completed_at: null,
        context: .context,
        is_circleci: (.context | test("circleci"; "i")),
        type: "status"
      }
    ' 2>/dev/null | jq -s '.' 2>/dev/null)
    
    if [ -n "$contexts" ] && [ "$contexts" != "null" ] && [ "$contexts" != "[]" ]; then
      all_checks=$(echo "$all_checks" | jq --argjson contexts "$contexts" '. + $contexts' 2>/dev/null || echo "$all_checks")
    fi
  fi
  
  # Remove duplicates (same context/name) - prefer check_runs over status contexts
  all_checks=$(echo "$all_checks" | jq '
    group_by(.context) |
    map(
      # If multiple entries for same context, prefer check_run over status
      (sort_by(.type == "status") | .[0])
    )
  ' 2>/dev/null || echo "$all_checks")
  
  if [ -z "$all_checks" ] || [ "$all_checks" = "null" ]; then
    echo "[]"
  else
    echo "$all_checks"
  fi
}

# Function to get all pipelines for a PR (handling pagination)
get_pipelines_for_pr() {
  local pr_num="$1"
  local all_pipelines="[]"
  local page_token=""
  
  # Get the actual branch name from GitHub PR
  local actual_branch=""
  actual_branch=$(get_pr_branch "$pr_num")
  
  # Build list of branch formats to try
  local branch_formats=()
  
  # Add actual branch name if we got it
  if [ -n "$actual_branch" ] && [ "$actual_branch" != "null" ]; then
    branch_formats+=("$actual_branch")
  fi
  
  # Add standard PR branch formats
  branch_formats+=("pull/${pr_num}/head" "pull/${pr_num}/merge")
  
  # Try each branch format
  for branch_format in "${branch_formats[@]}"; do
    local url="${CIRCLE_API_BASE}/project/${PROJECT_SLUG}/pipeline?branch=${branch_format}"
    page_token=""
    
    while true; do
      local request_url="$url"
      if [ -n "$page_token" ]; then
        # Check if URL already has query params
        if echo "$request_url" | grep -q "?"; then
          request_url="${request_url}&page-token=${page_token}"
        else
          request_url="${request_url}?page-token=${page_token}"
        fi
      fi
      
      local response
      response=$(circleci_api_request "$request_url" 2>/dev/null)
      if [ $? -ne 0 ]; then
        break
      fi
      
      # Check if response is valid JSON
      if ! echo "$response" | jq empty 2>/dev/null; then
        break
      fi
      
      local pipelines
      pipelines=$(echo "$response" | jq -r '.items // []' 2>/dev/null)
      if [ -z "$pipelines" ] || [ "$pipelines" = "null" ] || [ "$pipelines" = "[]" ]; then
        break
      fi
      
      # Merge pipelines into all_pipelines array
      all_pipelines=$(echo "$all_pipelines" | jq --argjson new "$pipelines" '. + $new' 2>/dev/null || echo "$all_pipelines")
      
      # Check for next page token
      page_token=$(echo "$response" | jq -r '.next_page_token // empty' 2>/dev/null)
      if [ -z "$page_token" ] || [ "$page_token" = "null" ]; then
        break
      fi
    done
    
    # If we found pipelines, we can stop trying other formats
    local found_count
    found_count=$(echo "$all_pipelines" | jq 'length' 2>/dev/null || echo "0")
    if [ "$found_count" -gt 0 ]; then
      break
    fi
  done
  
  echo "$all_pipelines"
}

# Function to get workflows for a pipeline
get_workflows_for_pipeline() {
  local pipeline_id="$1"
  local url="${CIRCLE_API_BASE}/pipeline/${pipeline_id}/workflow"
  local all_workflows="[]"
  local page_token=""
  
  while true; do
    local request_url="$url"
    if [ -n "$page_token" ]; then
      request_url="${url}?page-token=${page_token}"
    fi
    
    local response
    response=$(circleci_api_request "$request_url")
    if [ $? -ne 0 ]; then
      break
    fi
    
    local workflows
    workflows=$(echo "$response" | jq -r '.items // []' 2>/dev/null)
    if [ -z "$workflows" ] || [ "$workflows" = "null" ] || [ "$workflows" = "[]" ]; then
      break
    fi
    
    # Merge workflows into all_workflows array
    all_workflows=$(echo "$all_workflows" | jq --argjson new "$workflows" '. + $new' 2>/dev/null || echo "$all_workflows")
    
    # Check for next page token
    page_token=$(echo "$response" | jq -r '.next_page_token // empty' 2>/dev/null)
    if [ -z "$page_token" ] || [ "$page_token" = "null" ]; then
      break
    fi
  done
  
  echo "$all_workflows"
}

# Function to get jobs for a workflow
get_jobs_for_workflow() {
  local workflow_id="$1"
  local url="${CIRCLE_API_BASE}/workflow/${workflow_id}/job"
  local all_jobs="[]"
  local page_token=""
  
  while true; do
    local request_url="$url"
    if [ -n "$page_token" ]; then
      request_url="${url}?page-token=${page_token}"
    fi
    
    local response
    response=$(circleci_api_request "$request_url")
    if [ $? -ne 0 ]; then
      break
    fi
    
    local jobs
    jobs=$(echo "$response" | jq -r '.items // []' 2>/dev/null)
    if [ -z "$jobs" ] || [ "$jobs" = "null" ] || [ "$jobs" = "[]" ]; then
      break
    fi
    
    # Merge jobs into all_jobs array
    all_jobs=$(echo "$all_jobs" | jq --argjson new "$jobs" '. + $new' 2>/dev/null || echo "$all_jobs")
    
    # Check for next page token
    page_token=$(echo "$response" | jq -r '.next_page_token // empty' 2>/dev/null)
    if [ -z "$page_token" ] || [ "$page_token" = "null" ]; then
      break
    fi
  done
  
  echo "$all_jobs"
}

# Function to get job details
get_job_details() {
  local job_number="$1"
  local url="${CIRCLE_API_BASE}/project/${PROJECT_SLUG}/job/${job_number}"
  circleci_api_request "$url"
}

# Function to get test metadata for a job
get_job_tests() {
  local job_number="$1"
  local url="${CIRCLE_API_BASE}/project/${PROJECT_SLUG}/${job_number}/tests"
  circleci_api_request "$url"
}

# Function to get job output/logs (using v1.1 API for step output)
get_job_output() {
  local job_number="$1"
  # CircleCI v1.1 API endpoint for job output
  local url="https://circleci.com/api/v1.1/project/${PROJECT_SLUG}/${job_number}/output"
  local response
  response=$(curl -s -H "Circle-Token: ${CIRCLE_TOKEN}" "$url" 2>/dev/null)
  local exit_code=$?
  
  if [ $exit_code -ne 0 ]; then
    return 1
  fi
  
  # Check for API errors
  if echo "$response" | jq -e '.message // .error // empty' >/dev/null 2>&1; then
    return 1
  fi
  
  echo "$response"
}

# Function to query recent pipelines as fallback (when branch-based query fails)
get_recent_pipelines() {
  local url="${CIRCLE_API_BASE}/project/${PROJECT_SLUG}/pipeline?page-size=50"
  local all_pipelines="[]"
  local page_token=""
  
  # Get first page of recent pipelines
  while true; do
    local request_url="$url"
    if [ -n "$page_token" ]; then
      if echo "$request_url" | grep -q "?"; then
        request_url="${request_url}&page-token=${page_token}"
      else
        request_url="${request_url}?page-token=${page_token}"
      fi
    fi
    
    local response
    response=$(circleci_api_request "$request_url" 2>/dev/null)
    if [ $? -ne 0 ]; then
      break
    fi
    
    if ! echo "$response" | jq empty 2>/dev/null; then
      break
    fi
    
    local pipelines
    pipelines=$(echo "$response" | jq -r '.items // []' 2>/dev/null)
    if [ -z "$pipelines" ] || [ "$pipelines" = "null" ] || [ "$pipelines" = "[]" ]; then
      break
    fi
    
    # Filter pipelines that might be related to this PR by checking branch name or vcs metadata
    # We'll check if the branch contains the PR number or matches PR branch patterns
    local filtered
    filtered=$(echo "$pipelines" | jq --arg pr "$PULL_REQUEST" '
      [.[] | 
        select(
          (.vcs.branch // "" | test("pull/" + $pr + "/"; "")) or
          (.vcs.branch // "" | test("pr/" + $pr; "")) or
          (.vcs.branch // "" | test("/" + $pr + "/"; "")) or
          (.vcs.branch // "" | test("^" + $pr + "-"; "")) or
          (.vcs.branch // "" | test("-" + $pr + "-"; "")) or
          (.vcs.branch // "" | test("-" + $pr + "$"; ""))
        )
      ]
    ' 2>/dev/null || echo "[]")
    
    if [ -n "$filtered" ] && [ "$filtered" != "null" ] && [ "$filtered" != "[]" ]; then
      all_pipelines=$(echo "$all_pipelines" | jq --argjson new "$filtered" '. + $new' 2>/dev/null || echo "$all_pipelines")
    fi
    
    # Only check first page for performance
    break
  done
  
  echo "$all_pipelines"
}

# Main execution
if [ -z "$JSON_OUTPUT" ]; then
  echo "Fetching status checks for PR #${PULL_REQUEST}..."
fi

# Get all status checks from GitHub
GITHUB_CHECKS=$(get_github_status_checks "$PULL_REQUEST")

# Ensure we have valid JSON
if ! echo "$GITHUB_CHECKS" | jq empty 2>/dev/null; then
  GITHUB_CHECKS="[]"
fi

CHECK_COUNT=$(echo "$GITHUB_CHECKS" | jq 'length // 0' 2>/dev/null || echo "0")

# Ensure CHECK_COUNT is numeric
if ! [[ "$CHECK_COUNT" =~ ^[0-9]+$ ]]; then
  CHECK_COUNT=0
fi

if [ "$CHECK_COUNT" -eq 0 ]; then
  if [ -z "$JSON_OUTPUT" ]; then
    echo "No status checks found for PR #${PULL_REQUEST}"
  else
    echo '{"checks": []}'
  fi
  exit 0
fi

if [ -z "$JSON_OUTPUT" ]; then
  echo "Found $CHECK_COUNT status check(s)"
fi

# For CircleCI checks, enrich with CircleCI API data
# Get CircleCI pipelines to match jobs
CIRCLE_JOBS_MAP="{}"
if echo "$GITHUB_CHECKS" | jq '[.[] | select(.is_circleci == true)] | length' 2>/dev/null | grep -q '[1-9]'; then
  # We have CircleCI checks, validate CIRCLE_TOKEN is set
  if [ -z "$CIRCLE_TOKEN" ]; then
    echo "Error: CIRCLE_TOKEN environment variable is not set (required for CircleCI check details)"
    echo ""
    echo "Documentation: https://circleci.com/docs/managing-api-tokens/"
    exit 1
  fi
  
  # We have CircleCI checks, fetch pipeline data
  PIPELINES=$(get_pipelines_for_pr "$PULL_REQUEST")
  PIPELINE_COUNT=$(echo "$PIPELINES" | jq 'length' 2>/dev/null || echo "0")
  
  if [ "$PIPELINE_COUNT" -gt 0 ]; then
    # Filter to latest pipeline
    PIPELINES=$(echo "$PIPELINES" | jq 'sort_by(.created_at // "") | reverse | .[0:1]' 2>/dev/null || echo "$PIPELINES")
    PIPELINE_IDS=$(echo "$PIPELINES" | jq -r '.[].id' 2>/dev/null)
    
    for pipeline_id in $PIPELINE_IDS; do
      if [ -z "$pipeline_id" ] || [ "$pipeline_id" = "null" ]; then
        continue
      fi
      
      PIPELINE_NUMBER=$(echo "$PIPELINES" | jq -r --arg id "$pipeline_id" '.[] | select(.id == $id) | .number // "N/A"' 2>/dev/null)
      PIPELINE_CREATED=$(echo "$PIPELINES" | jq -r --arg id "$pipeline_id" '.[] | select(.id == $id) | .created_at // "N/A"' 2>/dev/null)
      PIPELINE_VCS_BRANCH=$(echo "$PIPELINES" | jq -r --arg id "$pipeline_id" '.[] | select(.id == $id) | .vcs.branch // "N/A"' 2>/dev/null)
      
      WORKFLOWS=$(get_workflows_for_pipeline "$pipeline_id")
      WORKFLOW_IDS=$(echo "$WORKFLOWS" | jq -r '.[].id' 2>/dev/null)
      
      for workflow_id in $WORKFLOW_IDS; do
        if [ -z "$workflow_id" ] || [ "$workflow_id" = "null" ]; then
          continue
        fi
        
        WORKFLOW_NAME=$(echo "$WORKFLOWS" | jq -r --arg id "$workflow_id" '.[] | select(.id == $id) | .name' 2>/dev/null)
        JOBS=$(get_jobs_for_workflow "$workflow_id")
        
        # Create a map of job name -> job data for quick lookup
        JOBS_MAP=$(echo "$JOBS" | jq --arg workflow_name "$WORKFLOW_NAME" --arg pipeline_number "$PIPELINE_NUMBER" --arg pipeline_created "$PIPELINE_CREATED" --arg pipeline_branch "$PIPELINE_VCS_BRANCH" '
          reduce .[] as $job ({}; .[$job.name] = ($job + {
            workflow_name: $workflow_name,
            pipeline_number: ($pipeline_number | if . == "N/A" then null else . end),
            pipeline_created_at: ($pipeline_created | if . == "N/A" then null else . end),
            pipeline_branch: ($pipeline_branch | if . == "N/A" then null else . end)
          }))
        ' 2>/dev/null || echo "{}")
        
        # Merge into CIRCLE_JOBS_MAP
        CIRCLE_JOBS_MAP=$(echo "$CIRCLE_JOBS_MAP" | jq --argjson jobs "$JOBS_MAP" '. + $jobs' 2>/dev/null || echo "$CIRCLE_JOBS_MAP")
      done
    done
  fi
fi

# Enrich GitHub checks with CircleCI data where applicable
ALL_CHECKS=$(echo "$GITHUB_CHECKS" | jq --argjson circle_jobs "$CIRCLE_JOBS_MAP" '
  map(
    . as $check |
    if $check.is_circleci == true then
      # Extract job name from context (e.g., "ci/circleci: job_name" -> "job_name")
      ($check.context | split(": ") | if length > 1 then .[1] else $check.context end) as $job_name |
      ($circle_jobs[$job_name] // {}) as $circle_job |
      $check + {
        job_number: $circle_job.job_number,
        workflow_name: $circle_job.workflow_name,
        pipeline_number: $circle_job.pipeline_number,
        pipeline_created_at: $circle_job.pipeline_created_at,
        pipeline_branch: $circle_job.pipeline_branch,
        started_at: ($circle_job.started_at // $check.started_at),
        stopped_at: ($circle_job.stopped_at // $check.completed_at)
      }
    else
      $check
    end
  )
' 2>/dev/null || echo "$GITHUB_CHECKS")

# Apply filters
FILTERED_CHECKS="$ALL_CHECKS"

# Apply job/check name filter
if [ -n "$JOB_FILTER" ]; then
  FILTERED_CHECKS=$(echo "$FILTERED_CHECKS" | jq --arg filter "$JOB_FILTER" '[.[] | select(.name == $filter or .context == $filter or (.context | contains($filter)))]' 2>/dev/null || echo "$FILTERED_CHECKS")
fi

# Apply workflow filter (only applies to CircleCI checks)
if [ -n "$WORKFLOW_FILTER" ]; then
  FILTERED_CHECKS=$(echo "$FILTERED_CHECKS" | jq --arg filter "$WORKFLOW_FILTER" '[.[] | select(.is_circleci != true or .workflow_name == $filter)]' 2>/dev/null || echo "$FILTERED_CHECKS")
fi

# Apply status filters (OR logic - if multiple are specified, show checks matching any)
# Map GitHub status values to our filter values
if [ -n "$SHOW_FAILING" ] || [ -n "$SHOW_PASSING" ] || [ -n "$SHOW_IN_PROGRESS" ]; then
  STATUS_FILTER_PARTS=()
  
  if [ -n "$SHOW_FAILING" ]; then
    STATUS_FILTER_PARTS+=("failed|error|failure")
  fi
  
  if [ -n "$SHOW_PASSING" ]; then
    STATUS_FILTER_PARTS+=("success|successful")
  fi
  
  if [ -n "$SHOW_IN_PROGRESS" ]; then
    STATUS_FILTER_PARTS+=("running|pending|in_progress|queued|in_progress|waiting")
  fi
  
  # Join all filter parts with |
  STATUS_FILTER=$(IFS='|'; echo "${STATUS_FILTER_PARTS[*]}")
  
  # Filter checks by status (case-insensitive)
  FILTERED_CHECKS=$(echo "$FILTERED_CHECKS" | jq --arg filter "$STATUS_FILTER" '
    [.[] | select(.status | ascii_downcase | test($filter; "i"))]
  ' 2>/dev/null || echo "$FILTERED_CHECKS")
fi

# Enrich checks with details if requested (for CircleCI checks only)
if [ -n "$DETAILS" ]; then
  ENRICHED_CHECKS="[]"
  CHECK_COUNT=$(echo "$FILTERED_CHECKS" | jq 'length' 2>/dev/null || echo "0")
  
  for i in $(seq 0 $((CHECK_COUNT - 1))); do
    CHECK=$(echo "$FILTERED_CHECKS" | jq ".[$i]" 2>/dev/null)
    IS_CIRCLECI=$(echo "$CHECK" | jq -r '.is_circleci // false' 2>/dev/null)
    JOB_NUMBER=$(echo "$CHECK" | jq -r '.job_number // empty' 2>/dev/null)
    
    if [ "$IS_CIRCLECI" = "true" ] && [ -n "$JOB_NUMBER" ] && [ "$JOB_NUMBER" != "null" ]; then
      # Get job details
      JOB_DETAILS=$(get_job_details "$JOB_NUMBER")
      if [ $? -eq 0 ] && [ -n "$JOB_DETAILS" ]; then
        CHECK=$(echo "$CHECK" | jq --argjson details "$JOB_DETAILS" '. + $details' 2>/dev/null || echo "$CHECK")
      fi
      
      # Get test metadata for failed jobs
      CHECK_STATUS=$(echo "$CHECK" | jq -r '.status // "unknown"' 2>/dev/null | tr '[:upper:]' '[:lower:]')
      if [ "$CHECK_STATUS" = "failed" ] || [ "$CHECK_STATUS" = "error" ] || [ "$CHECK_STATUS" = "failure" ]; then
        TEST_DATA=$(get_job_tests "$JOB_NUMBER" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$TEST_DATA" ]; then
          # Check if test data is valid JSON and has tests
          if echo "$TEST_DATA" | jq empty 2>/dev/null; then
            # Extract failed tests
            FAILED_TESTS=$(echo "$TEST_DATA" | jq '[.tests[]? | select(.result == "failure" or .result == "error")]' 2>/dev/null)
            if [ -n "$FAILED_TESTS" ] && [ "$FAILED_TESTS" != "null" ] && [ "$FAILED_TESTS" != "[]" ]; then
              CHECK=$(echo "$CHECK" | jq --argjson tests "$FAILED_TESTS" '. + {failed_tests: $tests}' 2>/dev/null || echo "$CHECK")
            fi
          fi
        fi
      fi
    fi
    
    ENRICHED_CHECKS=$(echo "$ENRICHED_CHECKS" | jq --argjson check "$CHECK" '. + [$check]' 2>/dev/null || echo "$ENRICHED_CHECKS")
  done
  
  FILTERED_CHECKS="$ENRICHED_CHECKS"
fi

# Output results
TOTAL=$(echo "$FILTERED_CHECKS" | jq 'length // 0' 2>/dev/null || echo "0")

# Ensure TOTAL is numeric
if ! [[ "$TOTAL" =~ ^[0-9]+$ ]]; then
  TOTAL=0
fi

if [ -n "$COUNT_ONLY" ]; then
  if [ -n "$JSON_OUTPUT" ]; then
    echo "$FILTERED_CHECKS" | jq "{total: length, checks: .}"
  else
    echo "Total: $TOTAL"
  fi
elif [ -n "$JSON_OUTPUT" ]; then
  echo "$FILTERED_CHECKS" | jq '.'
else
  if [ "$TOTAL" -gt 0 ]; then
    for i in $(seq 0 $((TOTAL - 1))); do
      CHECK=$(echo "$FILTERED_CHECKS" | jq ".[$i]" 2>/dev/null)
      
      CHECK_NAME=$(echo "$CHECK" | jq -r '.name // .context // "N/A"')
      CHECK_STATUS=$(echo "$CHECK" | jq -r '.status // "N/A"')
      CHECK_DESCRIPTION=$(echo "$CHECK" | jq -r '.description // "N/A"')
      CHECK_URL=$(echo "$CHECK" | jq -r '.html_url // .url // .detailsUrl // "N/A"')
      STARTED_AT=$(echo "$CHECK" | jq -r '.started_at // "N/A"')
      STOPPED_AT=$(echo "$CHECK" | jq -r '.stopped_at // .completed_at // "N/A"')
      IS_CIRCLECI=$(echo "$CHECK" | jq -r '.is_circleci // false' 2>/dev/null)
      
      # CircleCI-specific fields
      WORKFLOW_NAME=$(echo "$CHECK" | jq -r '.workflow_name // "N/A"')
      JOB_NUMBER=$(echo "$CHECK" | jq -r '.job_number // "N/A"')
      PIPELINE_NUMBER=$(echo "$CHECK" | jq -r '.pipeline_number // "N/A"')
      PIPELINE_CREATED=$(echo "$CHECK" | jq -r '.pipeline_created_at // "N/A"')
      PIPELINE_BRANCH=$(echo "$CHECK" | jq -r '.pipeline_branch // "N/A"')
      
      # Determine emoji based on status
      STATUS_LOWER=$(echo "$CHECK_STATUS" | tr '[:upper:]' '[:lower:]')
      case "$STATUS_LOWER" in
        success|successful)
          STATUS_EMOJI="🟢"
          ;;
        failure|failed|error)
          STATUS_EMOJI="🔴"
          ;;
        pending|queued|waiting)
          STATUS_EMOJI="🟡"
          ;;
        in_progress|running|inprogress)
          STATUS_EMOJI="🟠"
          ;;
        neutral|cancelled|canceled|skipped)
          STATUS_EMOJI="⚪"
          ;;
        *)
          STATUS_EMOJI="⚫"
          ;;
      esac
      
      echo ""
      echo "Check: $CHECK_NAME"
      echo "---"
      echo "Status:           $STATUS_EMOJI $CHECK_STATUS"
      if [ "$CHECK_DESCRIPTION" != "N/A" ] && [ "$CHECK_DESCRIPTION" != "null" ] && [ "$CHECK_DESCRIPTION" != "" ]; then
        echo "Description:      $CHECK_DESCRIPTION"
      fi
      
      # Show CircleCI-specific info if applicable
      if [ "$IS_CIRCLECI" = "true" ]; then
        if [ "$WORKFLOW_NAME" != "N/A" ] && [ "$WORKFLOW_NAME" != "null" ]; then
          echo "Workflow:         $WORKFLOW_NAME"
        fi
        # Format pipeline info more descriptively
        if [ "$PIPELINE_BRANCH" != "N/A" ] && [ "$PIPELINE_BRANCH" != "null" ] && [ "$PIPELINE_NUMBER" != "N/A" ]; then
          echo "Pipeline:         #${PIPELINE_NUMBER} (${PIPELINE_BRANCH})"
        elif [ "$PIPELINE_NUMBER" != "N/A" ]; then
          echo "Pipeline:         #${PIPELINE_NUMBER}"
        fi
        if [ "$PIPELINE_CREATED" != "N/A" ] && [ "$PIPELINE_CREATED" != "null" ]; then
          echo "Pipeline Created: $PIPELINE_CREATED"
        fi
        if [ "$JOB_NUMBER" != "N/A" ] && [ "$JOB_NUMBER" != "null" ]; then
          echo "Job Number:       $JOB_NUMBER"
        fi
      fi
      
      if [ "$STARTED_AT" != "N/A" ] && [ "$STARTED_AT" != "null" ]; then
        echo "Started:          $STARTED_AT"
      fi
      if [ "$STOPPED_AT" != "N/A" ] && [ "$STOPPED_AT" != "null" ]; then
        echo "Completed:        $STOPPED_AT"
      fi
      
      # Calculate duration if both started and completed are available
      if [ "$STARTED_AT" != "N/A" ] && [ "$STARTED_AT" != "null" ] && [ "$STOPPED_AT" != "N/A" ] && [ "$STOPPED_AT" != "null" ]; then
        # Convert ISO 8601 timestamps to seconds since epoch
        # Handle both with and without timezone (Z suffix)
        STARTED_SECONDS=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$STARTED_AT" +%s 2>/dev/null)
        if [ $? -ne 0 ]; then
          # Try without Z suffix
          STARTED_SECONDS=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$STARTED_AT" +%s 2>/dev/null)
        fi
        
        STOPPED_SECONDS=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$STOPPED_AT" +%s 2>/dev/null)
        if [ $? -ne 0 ]; then
          # Try without Z suffix
          STOPPED_SECONDS=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$STOPPED_AT" +%s 2>/dev/null)
        fi
        
        if [ -n "$STARTED_SECONDS" ] && [ -n "$STOPPED_SECONDS" ] && [ "$STARTED_SECONDS" != "" ] && [ "$STOPPED_SECONDS" != "" ]; then
          DURATION_SECONDS=$((STOPPED_SECONDS - STARTED_SECONDS))
          
          # Format duration in human-readable format
          if [ "$DURATION_SECONDS" -lt 0 ]; then
            DURATION="N/A (invalid)"
          elif [ "$DURATION_SECONDS" -lt 60 ]; then
            DURATION="${DURATION_SECONDS}s"
          elif [ "$DURATION_SECONDS" -lt 3600 ]; then
            MINUTES=$((DURATION_SECONDS / 60))
            SECONDS=$((DURATION_SECONDS % 60))
            if [ "$SECONDS" -eq 0 ]; then
              DURATION="${MINUTES}m"
            else
              DURATION="${MINUTES}m ${SECONDS}s"
            fi
          else
            HOURS=$((DURATION_SECONDS / 3600))
            REMAINING_SECONDS=$((DURATION_SECONDS % 3600))
            MINUTES=$((REMAINING_SECONDS / 60))
            SECONDS=$((REMAINING_SECONDS % 60))
            if [ "$MINUTES" -eq 0 ] && [ "$SECONDS" -eq 0 ]; then
              DURATION="${HOURS}h"
            elif [ "$SECONDS" -eq 0 ]; then
              DURATION="${HOURS}h ${MINUTES}m"
            else
              DURATION="${HOURS}h ${MINUTES}m ${SECONDS}s"
            fi
          fi
          
          echo "Duration:         $DURATION"
        fi
      fi
      
      if [ "$CHECK_URL" != "N/A" ] && [ "$CHECK_URL" != "null" ] && [ "$CHECK_URL" != "" ]; then
        echo "URL:              $CHECK_URL"
      fi
      
      # Show failed tests if available (CircleCI only)
      if [ "$IS_CIRCLECI" = "true" ]; then
        FAILED_TESTS=$(echo "$CHECK" | jq '.failed_tests // empty' 2>/dev/null)
        if [ -n "$FAILED_TESTS" ] && [ "$FAILED_TESTS" != "null" ] && [ "$FAILED_TESTS" != "[]" ]; then
          FAILED_COUNT=$(echo "$FAILED_TESTS" | jq 'length' 2>/dev/null || echo "0")
          echo ""
          echo "Failed Tests:     $FAILED_COUNT"
          echo "$FAILED_TESTS" | jq -r '.[] | "  - \(.name // "Unknown test"): \(.message // "No message")"' 2>/dev/null
        fi
        
        # Show job output for failed jobs (unless --hide-job-output is set)
        if [ -z "$HIDE_JOB_OUTPUT" ] && [ "$CHECK_STATUS" != "success" ] && [ "$CHECK_STATUS" != "successful" ] && [ "$CHECK_STATUS" != "N/A" ] && [ "$JOB_NUMBER" != "N/A" ] && [ "$JOB_NUMBER" != "null" ]; then
          JOB_OUTPUT=$(get_job_output "$JOB_NUMBER" 2>/dev/null)
          if [ $? -eq 0 ] && [ -n "$JOB_OUTPUT" ]; then
            # Check if output is valid JSON and has content
            if echo "$JOB_OUTPUT" | jq empty 2>/dev/null; then
              # CircleCI v1.1 API returns array of output items
              # Each item has: time, type, message, step, etc.
              # Filter for error/failure messages and step outputs
              ERROR_OUTPUTS=$(echo "$JOB_OUTPUT" | jq '[.[]? | select(.type == "out" or .type == "stderr" or .type == "error" or (.message != null and (.message | test("error|fail|Error|Fail"; "i"))))] | .[0:50]' 2>/dev/null)
              
              if [ -n "$ERROR_OUTPUTS" ] && [ "$ERROR_OUTPUTS" != "null" ] && [ "$ERROR_OUTPUTS" != "[]" ]; then
                OUTPUT_COUNT=$(echo "$ERROR_OUTPUTS" | jq 'length' 2>/dev/null || echo "0")
                if [ "$OUTPUT_COUNT" -gt 0 ]; then
                  echo ""
                  echo "Job Output:"
                  # Show step name and message for each output item
                  echo "$ERROR_OUTPUTS" | jq -r '.[] | 
                    if .step then "  [\(.step)]" else "" end,
                    if .message then (.message | split("\n") | map("    " + .) | join("\n")) else "" end
                  ' 2>/dev/null | head -100
                  if [ "$OUTPUT_COUNT" -ge 50 ]; then
                    echo "    ... (output truncated, showing first 50 items)"
                  fi
                fi
              fi
            fi
          fi
        fi
      fi
      
      echo ""
    done
      else
        echo "No checks found matching the specified filters."
      fi
    fi
