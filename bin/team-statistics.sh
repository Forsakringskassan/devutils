#!/usr/bin/env bash
# contrib-stats.sh
# Usage:
#   GITHUB_TOKEN=... ./contrib-stats.sh -t TEAM [-o ORG] [-r repo-name] [-p prefix] [-s YYYY-MM-DD] [-u YYYY-MM-DD]
# If -o is not provided, the organization defaults to "Forsakringskassan".
# -p PREFIX : only look in repositories whose names start with PREFIX
# Output: CSV to stdout: repo,member,commits,additions,deletions
set -euo pipefail

API_BASE="${GITHUB_API_URL:-https://api.github.com}"
TOKEN="${GITHUB_TOKEN:-}"

if [[ -z "$TOKEN" ]]; then
  echo "ERROR: set GITHUB_TOKEN env var with appropriate scopes (repo, read:org)" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required" >&2
  exit 1
fi

# Default organization
ORG="Forsakringskassan"
TEAM=""
REPO=""
PREFIX=""
SINCE=""
UNTIL=""

while getopts "o:t:r:p:s:u:" opt; do
  case "$opt" in
    o) ORG="$OPTARG" ;;
    t) TEAM="$OPTARG" ;;
    r) REPO="$OPTARG" ;;
    p) PREFIX="$OPTARG" ;;
    s) SINCE="$OPTARG" ;;
    u) UNTIL="$OPTARG" ;;
    *) echo "Usage: $0 -t TEAM [-o ORG] [-r repo] [-p prefix] [-s since] [-u until]" >&2; exit 1 ;;
  esac
done

if [[ -z "$TEAM" ]]; then
  echo "Usage: $0 -t TEAM [-o ORG] [-r repo] [-p prefix] [-s since] [-u until]" >&2
  echo "Note: ORG defaults to \"$ORG\" if -o is not provided." >&2
  exit 1
fi

AUTH_HDR="Authorization: token $TOKEN"
ACCEPT_HDR="Accept: application/vnd.github+json"
PER_PAGE=100

# Helper: paginate GET and output concatenated JSON array of results
paginate_get() {
  local url="$1"
  local page=1
  local results=()
  while :; do
    # choose separator
    sep="&"
    if [[ "$url" != *"?"* ]]; then sep="?"; fi
    resp=$(curl -sS -H "$AUTH_HDR" -H "$ACCEPT_HDR" "${url}${sep}per_page=${PER_PAGE}&page=${page}")
    # break if empty array or null
    len=$(echo "$resp" | jq 'if type=="array" then length elif .==null then 0 else 1 end' 2>/dev/null || echo "0")
    if [[ "$len" == "0" ]]; then
      break
    fi
    results+=("$resp")
    count=$(echo "$resp" | jq 'if type=="array" then length else 1 end' 2>/dev/null || echo "1")
    if [[ "$count" -lt "$PER_PAGE" ]]; then
      break
    fi
    page=$((page+1))
  done

  if [[ "${#results[@]}" -eq 0 ]]; then
    echo "[]"
    return
  fi
  jq -s 'add' <<<"${results[@]}"
}

# Resolve team slug robustly
resolve_team_slug() {
  local given="$1"
  local org="$2"
  local members_json
  local is_array

  # 1) Try given as slug
  members_json=$(paginate_get "$API_BASE/orgs/$org/teams/$given/members?role=all" || echo "")
  is_array=$(echo "$members_json" | jq -r 'if type=="array" then "yes" else "no" end' 2>/dev/null || echo "no")
  if [[ "$is_array" == "yes" ]]; then
    echo "$given"
    return 0
  fi

  # 2) Try to match display name -> slug
  teams_json=$(paginate_get "$API_BASE/orgs/$org/teams")
  slug=$(echo "$teams_json" | jq -r --arg name "$given" '.[] | select(.name==$name) | .slug' 2>/dev/null | head -n1 || true)
  if [[ -n "$slug" && "$slug" != "null" ]]; then
    echo "$slug"
    return 0
  fi

  # 3) Slugify given and try
  candidate=$(echo "$given" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/-\+/-/g; s/^-//; s/-$//')
  members_json=$(paginate_get "$API_BASE/orgs/$org/teams/$candidate/members?role=all" || echo "")
  is_array=$(echo "$members_json" | jq -r 'if type=="array" then "yes" else "no" end' 2>/dev/null || echo "no")
  if [[ "$is_array" == "yes" ]]; then
    echo "$candidate"
    return 0
  fi

  # Diagnostic output
  echo ""
  echo "ERROR: Could not resolve team \"$given\" in organization \"$org\"." >&2
  echo "Here are the teams in $org (name -> slug):" >&2
  if [[ "$(echo "$teams_json" | jq 'if type=="array" then 1 else 0 end')" -eq 1 ]]; then
    echo "$teams_json" | jq -r '.[] | "\(.name) -> \(.slug)"' >&2
  else
    echo "  (could not list teams — check token permissions or org name)" >&2
  fi
  return 1
}

TEAM_SLUG=$(resolve_team_slug "$TEAM" "$ORG") || exit 1

# Get team members using slug
members_json=$(paginate_get "$API_BASE/orgs/$ORG/teams/$TEAM_SLUG/members?role=all")
members_type=$(echo "$members_json" | jq -r 'if type=="array" then "array" elif .message then "message" else "other" end' 2>/dev/null || echo "other")
if [[ "$members_type" != "array" ]]; then
  echo "ERROR fetching members for team slug '$TEAM_SLUG' in org '$ORG'." >&2
  echo "API response:" >&2
  echo "$members_json" | jq . >&2 || echo "$members_json" >&2
  exit 1
fi

team_members=($(echo "$members_json" | jq -r '.[].login'))

if [[ "${#team_members[@]}" -eq 0 ]]; then
  echo "No team members found for $ORG/$TEAM_SLUG" >&2
  exit 1
fi

# Get repos (and filter by prefix if provided)
repos=()
if [[ -n "$REPO" ]]; then
  repos+=("$REPO")
else
  repos_json=$(paginate_get "$API_BASE/orgs/$ORG/repos?type=all")
  all_repos=($(echo "$repos_json" | jq -r '.[].name'))
  if [[ -n "$PREFIX" ]]; then
    for r in "${all_repos[@]}"; do
      if [[ "$r" == "$PREFIX"* ]]; then
        repos+=("$r")
      fi
    done
  else
    repos=("${all_repos[@]}")
  fi
fi

if [[ "${#repos[@]}" -eq 0 ]]; then
  echo "No repositories found matching the criteria" >&2
  exit 1
fi

# helper: count commits for a user in a repo (paginated)
count_commits_by_author() {
  local owner="$1"
  local repo="$2"
  local author="$3"
  local since_param=""
  local until_param=""
  local page=1
  local total=0
  if [[ -n "$SINCE" ]]; then since_param="&since=${SINCE}T00:00:00Z"; fi
  if [[ -n "$UNTIL" ]]; then until_param="&until=${UNTIL}T23:59:59Z"; fi
  while :; do
    url="$API_BASE/repos/$owner/$repo/commits?author=$author${since_param}${until_param}&per_page=${PER_PAGE}&page=${page}"
    resp=$(curl -sS -H "$AUTH_HDR" -H "$ACCEPT_HDR" "$url")
    n=$(echo "$resp" | jq 'if type=="array" then length else 0 end' 2>/dev/null || echo "0")
    total=$((total + n))
    if [[ "$n" -lt "$PER_PAGE" ]]; then
      break
    fi
    page=$((page+1))
  done
  echo "$total"
}

# Prepare totals (overall and per-member)
declare -A commits_by_member
declare -A adds_by_member
declare -A dels_by_member
for member in "${team_members[@]}"; do
  commits_by_member["$member"]=0
  adds_by_member["$member"]=0
  dels_by_member["$member"]=0
done

total_commits=0
total_adds=0
total_dels=0

# Output header
echo "repo,member,commits,additions,deletions"

# For each repo process
for repo in "${repos[@]}"; do
  # try stats/contributors
  stats_url="$API_BASE/repos/$ORG/$repo/stats/contributors"
  stats_resp=$(curl -sS -H "$AUTH_HDR" -H "$ACCEPT_HDR" "$stats_url")
  stats_type=$(echo "$stats_resp" | jq -r 'if type=="array" then "array" elif .message then "message" else "other" end' 2>/dev/null || echo "other")
  if [[ "$stats_type" == "array" ]]; then
    for member in "${team_members[@]}"; do
      entry=$(jq --arg m "$member" -r '.[] | select(.author != null and .author.login == $m) | {total:.total, additions:(.weeks|map(.a)|add), deletions:(.weeks|map(.d)|add)}' <<<"$stats_resp" || true)
      if [[ -n "$entry" && "$entry" != "null" ]]; then
        total=$(jq -r '.total // 0' <<<"$entry")
        adds=$(jq -r '.additions // 0' <<<"$entry")
        dels=$(jq -r '.deletions // 0' <<<"$entry")
        echo "$repo,$member,$total,$adds,$dels"
        # accumulate
        commits_by_member["$member"]=$((commits_by_member["$member"] + total))
        adds_by_member["$member"]=$((adds_by_member["$member"] + adds))
        dels_by_member["$member"]=$((dels_by_member["$member"] + dels))
        total_commits=$((total_commits + total))
        total_adds=$((total_adds + adds))
        total_dels=$((total_dels + dels))
      else
        # fallback to counting commits only
        total=$(count_commits_by_author "$ORG" "$repo" "$member")
        echo "$repo,$member,$total,,"
        commits_by_member["$member"]=$((commits_by_member["$member"] + total))
        total_commits=$((total_commits + total))
      fi
    done
  else
    # stats not available, fallback commit counts
    for member in "${team_members[@]}"; do
      total=$(count_commits_by_author "$ORG" "$repo" "$member")
      echo "$repo,$member,$total,,"
      commits_by_member["$member"]=$((commits_by_member["$member"] + total))
      total_commits=$((total_commits + total))
    done
  fi
done

# Summary
echo ""
echo "SUMMARY"
echo "Organization: $ORG"
echo "Team: $TEAM (slug: $TEAM_SLUG)"
if [[ -n "$PREFIX" ]]; then
  echo "Repository prefix filter: $PREFIX"
fi
echo "Repositories scanned: ${#repos[@]}"
echo "Total commits (team across repos): $total_commits"
echo "Total additions (where available): $total_adds"
echo "Total deletions (where available): $total_dels"
echo ""
echo "Per-member totals:"
for member in "${team_members[@]}"; do
  c=${commits_by_member["$member"]:-0}
  a=${adds_by_member["$member"]:-0}
  d=${dels_by_member["$member"]:-0}
  echo "- $member: commits=$c additions=$a deletions=$d"
done

exit 0