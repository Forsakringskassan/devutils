#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
ORG="Forsakringskassan"
QUERY="${1:-}"

if [[ -z "$QUERY" ]]; then
    echo "Usage: $0 <query>"
    echo "Example: $0 rimfrost"
    exit 1
fi

OUTPUT_DIR="./${QUERY}-repos"

# Create output directory
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# --- Authentication ---
if [[ -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_ACTOR:-}" ]]; then
    AUTH_HEADER="Authorization: Bearer ${GITHUB_TOKEN}"
    echo "Using authenticated GitHub API access as ${GITHUB_ACTOR}."
else
    AUTH_HEADER=""
    echo "No authentication found, using unauthenticated GitHub API (rate-limited)."
fi

# --- Fetch repositories ---
page=1
repos=()
while :; do
    echo "Fetching page $page..."
    response=$(curl -sSL \
        -H "Accept: application/vnd.github+json" \
        ${AUTH_HEADER:+-H "$AUTH_HEADER"} \
        "https://api.github.com/search/repositories?q=${QUERY}+org:${ORG}&per_page=100&page=${page}")

    # Check for API errors
    if echo "$response" | jq -e '.message' >/dev/null 2>&1; then
        echo "GitHub API error: $(echo "$response" | jq -r '.message')" >&2
        exit 1
    fi

    # Extract clone URLs
    page_repos=($(echo "$response" | jq -r '.items[]?.clone_url'))
    repos+=("${page_repos[@]}")

    # Stop if fewer than 100 results on this page
    if [[ ${#page_repos[@]} -lt 100 ]]; then
        break
    fi
    ((page++))
done

echo "Found ${#repos[@]} repositories matching '$QUERY'."

# --- Clone repositories ---
for repo_url in "${repos[@]}"; do
    repo_name=$(basename "$repo_url" .git)
    if [[ -d "$repo_name" ]]; then
        echo "Skipping $repo_name (already cloned)"
        continue
    fi
    echo "Cloning $repo_name..."
    git clone "$repo_url"
done

echo "✅ All repositories cloned into: $OUTPUT_DIR"
