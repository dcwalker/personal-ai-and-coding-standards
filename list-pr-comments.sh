#!/bin/bash

# Script to list GitHub PR comments
# Usage: ./list-pr-comments.sh [OPTIONS]
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

PULL_REQUEST=""
COMMENT_URL=""
BOT_FILTER="bots"
COMMENT_TYPE="all"
JSON_OUTPUT=""
COUNT_ONLY=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -pr|--pull-request)
      PULL_REQUEST="$2"
      shift 2
      ;;
    -u|--url)
      COMMENT_URL="$2"
      shift 2
      ;;
    --bots)
      BOT_FILTER="bots"
      shift
      ;;
    --humans)
      BOT_FILTER="humans"
      shift
      ;;
    --all-users)
      BOT_FILTER="all"
      shift
      ;;
    -t|--type)
      COMMENT_TYPE="$2"
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
      echo "  -pr, --pull-request <number>  Filter comments for a specific pull request"
      echo "  -u, --url <url>               Get a specific comment by URL"
      echo "  --bots                        Show only bot comments (default)"
      echo "  --humans                      Show only human comments"
      echo "  --all-users                   Show comments from both bots and humans"
      echo "  -t, --type <type>            Filter by comment type: all, review, issue (default: all)"
      echo "                               - all: both review comments and issue comments"
      echo "                               - review: inline code review comments"
      echo "                               - issue: PR conversation comments"
      echo "  --json                        Output only JSON (no formatted text)"
      echo "  --count                       Output only the count of items"
      echo "  -h, --help                    Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0 -pr 19                     List all bot comments for PR #19"
      echo "  $0 -pr 19 --humans            List all human comments for PR #19"
      echo "  $0 -pr 19 -t review           List only inline review comments from bots"
      echo "  $0 -u <comment-url>           Get details for a specific comment by URL"
      echo "  $0 --json                     Output only JSON format"
      echo "  $0 -pr 19 --json              Output JSON for PR #19 comments"
      echo "  $0 --count                    Output only the count"
      echo "  $0 -pr 19 --humans --count    Output count of human comments for PR #19"
      echo ""
      echo "Repository: $REPO"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use -h or --help for usage information"
      exit 1
      ;;
  esac
done

# Validate comment type
case "$COMMENT_TYPE" in
  all|review|issue)
    ;;
  *)
    echo "Error: Invalid comment type '${COMMENT_TYPE}'. Must be one of: all, review, issue"
    exit 1
    ;;
esac

# Validate bot filter
case "$BOT_FILTER" in
  bots|humans|all)
    ;;
  *)
    echo "Error: Invalid bot filter '${BOT_FILTER}'. Must be one of: bots, humans, all"
    exit 1
    ;;
esac

# Check if gh CLI is available
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

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo "Error: jq is not installed. Install it to use this script."
  exit 1
fi

# Initialize ALL_COMMENTS to empty array
ALL_COMMENTS="[]"

# If URL is provided, extract comment ID and fetch that specific comment
if [ -n "$COMMENT_URL" ]; then
  # Parse URL to extract comment ID
  # URLs can be in formats like:
  # https://github.com/owner/repo/pull/PR_NUMBER#discussion_rCOMMENT_ID (review comment)
  # https://github.com/owner/repo/pull/PR_NUMBER#issuecomment-COMMENT_ID (issue comment)
  # https://github.com/owner/repo/pull/PR_NUMBER (just PR, will need to list all)
  
  if echo "$COMMENT_URL" | grep -q "#discussion_r"; then
    # Review comment
    COMMENT_ID=$(echo "$COMMENT_URL" | sed -E 's/.*#discussion_r([0-9]+)/\1/')
    PR_NUM=$(echo "$COMMENT_URL" | sed -E 's/.*\/pull\/([0-9]+).*/\1/')
    
    if [ -n "$COMMENT_ID" ] && [ -n "$PR_NUM" ]; then
      if [ -z "$JSON_OUTPUT" ]; then
        echo "Fetching review comment #${COMMENT_ID} from PR #${PR_NUM}"
      fi
      COMMENT=$(gh api "repos/${REPO}/pulls/comments/${COMMENT_ID}" 2>/dev/null)
      if [ $? -eq 0 ] && [ -n "$COMMENT" ]; then
        COMMENT_WITH_TYPE=$(echo "$COMMENT" | jq '. + {type: "review"}' 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$COMMENT_WITH_TYPE" ]; then
          ALL_COMMENTS="[$COMMENT_WITH_TYPE]"
        else
          echo "Error: Could not process comment #${COMMENT_ID}"
          exit 1
        fi
      else
        echo "Error: Could not fetch comment #${COMMENT_ID}"
        exit 1
      fi
    else
      echo "Error: Could not parse review comment ID from URL: $COMMENT_URL"
      exit 1
    fi
  elif echo "$COMMENT_URL" | grep -q "#issuecomment-"; then
    # Issue comment
    COMMENT_ID=$(echo "$COMMENT_URL" | sed -E 's/.*#issuecomment-([0-9]+)/\1/')
    PR_NUM=$(echo "$COMMENT_URL" | sed -E 's/.*\/pull\/([0-9]+).*/\1/')
    
    if [ -n "$COMMENT_ID" ] && [ -n "$PR_NUM" ]; then
      if [ -z "$JSON_OUTPUT" ]; then
        echo "Fetching issue comment #${COMMENT_ID} from PR #${PR_NUM}"
      fi
      COMMENT=$(gh api "repos/${REPO}/issues/comments/${COMMENT_ID}" 2>/dev/null)
      if [ $? -eq 0 ] && [ -n "$COMMENT" ]; then
        COMMENT_WITH_TYPE=$(echo "$COMMENT" | jq '. + {type: "issue"}' 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$COMMENT_WITH_TYPE" ]; then
          ALL_COMMENTS="[$COMMENT_WITH_TYPE]"
        else
          echo "Error: Could not process comment #${COMMENT_ID}"
          exit 1
        fi
      else
        echo "Error: Could not fetch comment #${COMMENT_ID}"
        exit 1
      fi
    else
      echo "Error: Could not parse issue comment ID from URL: $COMMENT_URL"
      exit 1
    fi
  elif echo "$COMMENT_URL" | grep -q "/pull/"; then
    # Just a PR URL, extract PR number and list all comments
    PULL_REQUEST=$(echo "$COMMENT_URL" | sed -E 's/.*\/pull\/([0-9]+).*/\1/')
    if [ -z "$PULL_REQUEST" ]; then
      echo "Error: Could not parse PR number from URL: $COMMENT_URL"
      exit 1
    fi
    if [ -z "$JSON_OUTPUT" ]; then
      echo "Extracted PR #${PULL_REQUEST} from URL, fetching all comments..."
    fi
  else
    echo "Error: Invalid comment URL format: $COMMENT_URL"
    echo "Expected format: https://github.com/owner/repo/pull/PR_NUMBER#discussion_rCOMMENT_ID"
    echo "              or: https://github.com/owner/repo/pull/PR_NUMBER#issuecomment-COMMENT_ID"
    exit 1
  fi
fi

# If we have a PR number (from -pr flag or extracted from URL), fetch all comments
# Condition: PR is set AND (no URL provided OR URL is just a PR URL without comment anchor)
SHOULD_FETCH_PR=false
if [ -n "$PULL_REQUEST" ]; then
  if [ -z "$COMMENT_URL" ]; then
    SHOULD_FETCH_PR=true
  elif echo "$COMMENT_URL" | grep -q "/pull/" && ! echo "$COMMENT_URL" | grep -q "#"; then
    SHOULD_FETCH_PR=true
  fi
fi

if [ "$SHOULD_FETCH_PR" = "true" ]; then
  if [ -z "$JSON_OUTPUT" ]; then
    echo "Fetching comments for PR #${PULL_REQUEST} in ${REPO}"
  fi
  
  # Fetch comments based on type
  REVIEW_COMMENTS=""
  ISSUE_COMMENTS=""
  
  if [ "$COMMENT_TYPE" = "all" ] || [ "$COMMENT_TYPE" = "review" ]; then
    if [ -z "$JSON_OUTPUT" ]; then
      echo "Fetching review comments..."
    fi
    REVIEW_COMMENTS=$(gh api "repos/${REPO}/pulls/${PULL_REQUEST}/comments" 2>&1)
    API_EXIT_CODE=$?
    if [ $API_EXIT_CODE -ne 0 ] || [ -z "$REVIEW_COMMENTS" ]; then
      echo "Warning: Failed to fetch review comments (exit code: $API_EXIT_CODE)"
      if [ -n "$REVIEW_COMMENTS" ]; then
        echo "Error details: $REVIEW_COMMENTS" | head -3
      fi
      REVIEW_COMMENTS="[]"
    else
      # Validate it's valid JSON
      if ! echo "$REVIEW_COMMENTS" | jq empty 2>/dev/null; then
        echo "Warning: Invalid JSON received for review comments"
        REVIEW_COMMENTS="[]"
      else
        REVIEW_COUNT=$(echo "$REVIEW_COMMENTS" | jq 'length' 2>/dev/null || echo "0")
        if [ -z "$JSON_OUTPUT" ]; then
          echo "Found $REVIEW_COUNT review comment(s)"
        fi
      fi
    fi
  fi
  
  if [ "$COMMENT_TYPE" = "all" ] || [ "$COMMENT_TYPE" = "issue" ]; then
    if [ -z "$JSON_OUTPUT" ]; then
      echo "Fetching issue comments..."
    fi
    ISSUE_COMMENTS=$(gh api "repos/${REPO}/issues/${PULL_REQUEST}/comments" 2>&1)
    API_EXIT_CODE=$?
    if [ $API_EXIT_CODE -ne 0 ] || [ -z "$ISSUE_COMMENTS" ]; then
      echo "Warning: Failed to fetch issue comments (exit code: $API_EXIT_CODE)"
      if [ -n "$ISSUE_COMMENTS" ]; then
        echo "Error details: $ISSUE_COMMENTS" | head -3
      fi
      ISSUE_COMMENTS="[]"
    else
      # Validate it's valid JSON
      if ! echo "$ISSUE_COMMENTS" | jq empty 2>/dev/null; then
        echo "Warning: Invalid JSON received for issue comments"
        ISSUE_COMMENTS="[]"
      else
        ISSUE_COUNT=$(echo "$ISSUE_COMMENTS" | jq 'length' 2>/dev/null || echo "0")
        if [ -z "$JSON_OUTPUT" ]; then
          echo "Found $ISSUE_COUNT issue comment(s)"
        fi
      fi
    fi
  fi
  
  # Filter and combine comments
  ALL_COMMENTS="[]"
  
  if [ "$COMMENT_TYPE" = "all" ] || [ "$COMMENT_TYPE" = "review" ]; then
    if [ -n "$REVIEW_COMMENTS" ] && [ "$REVIEW_COMMENTS" != "[]" ]; then
      REVIEW_FILTERED=$(echo "$REVIEW_COMMENTS" | jq --arg filter "$BOT_FILTER" '
        [.[] | 
          if $filter == "bots" then select(.user.type == "Bot")
          elif $filter == "humans" then select(.user.type != "Bot")
          else .
          end | 
          . + {type: "review"}]
      ' 2>/dev/null)
      if [ $? -eq 0 ] && [ -n "$REVIEW_FILTERED" ]; then
        FILTERED_COUNT=$(echo "$REVIEW_FILTERED" | jq 'length' 2>/dev/null || echo "0")
        if [ "$FILTERED_COUNT" -gt 0 ]; then
          ALL_COMMENTS=$(echo "$ALL_COMMENTS" | jq --argjson reviews "$REVIEW_FILTERED" '. + $reviews' 2>/dev/null)
          if [ $? -ne 0 ] || [ -z "$ALL_COMMENTS" ]; then
            echo "Warning: Failed to merge review comments into result"
            ALL_COMMENTS="[]"
          fi
        fi
      else
        echo "Warning: Failed to filter review comments"
      fi
    fi
  fi
  
  if [ "$COMMENT_TYPE" = "all" ] || [ "$COMMENT_TYPE" = "issue" ]; then
    if [ -n "$ISSUE_COMMENTS" ] && [ "$ISSUE_COMMENTS" != "[]" ]; then
      ISSUE_FILTERED=$(echo "$ISSUE_COMMENTS" | jq --arg filter "$BOT_FILTER" '
        [.[] | 
          if $filter == "bots" then select(.user.type == "Bot")
          elif $filter == "humans" then select(.user.type != "Bot")
          else .
          end | 
          . + {type: "issue"}]
      ' 2>/dev/null)
      if [ $? -eq 0 ] && [ -n "$ISSUE_FILTERED" ]; then
        FILTERED_COUNT=$(echo "$ISSUE_FILTERED" | jq 'length' 2>/dev/null || echo "0")
        if [ "$FILTERED_COUNT" -gt 0 ]; then
          ALL_COMMENTS=$(echo "$ALL_COMMENTS" | jq --argjson issues "$ISSUE_FILTERED" '. + $issues' 2>/dev/null)
          if [ $? -ne 0 ] || [ -z "$ALL_COMMENTS" ]; then
            echo "Warning: Failed to merge issue comments into result"
            ALL_COMMENTS="[]"
          fi
        fi
      else
        echo "Warning: Failed to filter issue comments"
      fi
    fi
  fi
elif [ -z "$PULL_REQUEST" ] && [ -z "$COMMENT_URL" ]; then
  echo "Error: Either pull request number (-pr) or comment URL (-u) is required"
  exit 1
fi

# Calculate total, defaulting to 0 if jq fails or returns empty
TOTAL=$(echo "$ALL_COMMENTS" | jq -r 'length // 0' 2>/dev/null)
if [ -z "$TOTAL" ] || [ "$TOTAL" = "null" ]; then
  TOTAL=0
fi

# Output count only if --count flag is set
if [ -n "$COUNT_ONLY" ]; then
  if [ -n "$JSON_OUTPUT" ]; then
    echo "$ALL_COMMENTS" | jq '{total: length}'
  else
    echo "Total: $TOTAL"
  fi
elif [ -n "$JSON_OUTPUT" ]; then
  echo "$ALL_COMMENTS" | jq '.'
else
  echo ""
  echo "=== Comments Summary ==="
  case "$BOT_FILTER" in
    bots)
      echo "Total bot comments: $TOTAL"
      ;;
    humans)
      echo "Total human comments: $TOTAL"
      ;;
    all)
      echo "Total comments: $TOTAL"
      ;;
  esac
  echo ""

  if [ "$TOTAL" -gt 0 ]; then
    for i in $(seq 0 $((TOTAL - 1))); do
      COMMENT=$(echo "$ALL_COMMENTS" | jq ".[$i]")
      
      echo ""
      echo "Comment #$((i + 1))"
      echo "---"
      
      # Display comment details
      echo "$COMMENT" | jq -r '
        "Type:              \(.type // "N/A" | ascii_upcase)
Author:            \(.user.login // "N/A")
Author Type:       \(.user.type // "N/A")
Created:           \(.created_at // "N/A")
Updated:           \(.updated_at // "N/A")"
      '
      
      # For review comments, show file and line info
      if [ "$(echo "$COMMENT" | jq -r '.type')" = "review" ]; then
        echo "$COMMENT" | jq -r '
          "Path:              \(.path // "N/A")
Line:              \(.line // "N/A")
Diff Hunk:         \(.diff_hunk // "N/A" | split("\n") | .[0:3] | join(" | "))"
        '
      fi
      
      # Show comment body (truncate if very long)
      BODY=$(echo "$COMMENT" | jq -r '.body // ""')
      if [ ${#BODY} -gt 500 ]; then
        echo "Body:              ${BODY:0:500}..."
        echo "                   (truncated, full length: ${#BODY} characters)"
      else
        echo "Body:"
        echo "$BODY" | sed 's/^/                   /'
      fi
      
      # Show URL
      HTML_URL=$(echo "$COMMENT" | jq -r '.html_url // ""')
      if [ -n "$HTML_URL" ] && [ "$HTML_URL" != "null" ]; then
        echo "URL:               $HTML_URL"
      fi
      
      echo ""
    done
  else
    echo "No comments found."
    if [ -n "$COMMENT_URL" ]; then
      echo "The comment URL may be invalid or you may not have access to it."
    fi
  fi
fi
