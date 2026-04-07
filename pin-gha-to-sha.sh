#!/usr/bin/env bash
set -euo pipefail

# Pin GitHub Actions to commit SHAs.
#
# Requirements: bash, git, gh, awk, jq
# Usage: ./pin-gha-to-sha.sh OWNER/REPO [--base-branch BRANCH] [--pr-branch BRANCH] [--cache-file PATH]

usage() {
  cat <<EOF
Usage: $0 OWNER/REPO [options]

Pin GitHub Actions uses: references to immutable commit SHAs.

Arguments:
  OWNER/REPO              Required. The GitHub repository to process (e.g. myorg/myrepo).

Options:
  --base-branch BRANCH    Branch to clone and base the PR on.
                          Default: the repository's default branch.
  --pr-branch BRANCH      Name of the branch to create for the changes.
                          Default: pin-actions-to-sha
  --cache-file PATH       Path to a JSON file that caches resolved SHAs across runs.
                          Default: /tmp/gha-pin-cache.json
  --dry-run               Show proposed changes only. No commit/push/PR.
  --use-fork              Push changes to your fork and open PR to upstream.
                          Useful when you do not have direct push permission.
  -h, --help              Show this help message and exit.

Behavior:
  - Clones the repo via SSH, checking out the base branch.
  - Scans all YAML files recursively for uses: references (excluding .git/).
  - For each uses: reference not already pinned to a 40-char SHA:
      * If the ref is a tag: resolves the tag to its commit SHA.
      * If the ref is a branch: looks up the latest release tag via
        gh release list; if found, pins to that tag's SHA; otherwise
        pins to the branch HEAD SHA.
  - Adds a trailing comment (# tag-or-branch) to each pinned line.
  - In --dry-run mode, prints diff and exits without commit/push/PR.
  - Shows a diff and prompts for approval before committing.
  - If approved: commits, pushes, and opens a PR against the base branch.
    With --use-fork, the branch is pushed to <your-user>/<repo> and PR is opened to upstream.
  - If declined: preserves the working copy for manual editing.
  - Inaccessible/private actions are logged (not committed).
  - Resolved SHAs are cached in the cache file for faster follow-up runs.

Hardcoded overrides:
  - aquasecurity/trivy-action  => 57a97c7e7821a5776cebc9bb87c984fa69cba8f1 # v0.35.0
  - aquasecurity/setup-trivy   => 3fb12ec12f41e471780db15c232d5dd185dcb514 # v0.2.6

Examples:
  $0 myorg/myrepo
  $0 myorg/myrepo --base-branch release/v2.10
  $0 myorg/myrepo --base-branch main --pr-branch fix/pin-actions
  $0 myorg/myrepo --pr-branch pin-actions --cache-file /tmp/gha-pin-cache.json
  $0 myorg/myrepo --dry-run
  $0 myorg/myrepo --use-fork
EOF
  exit 0
}

# ─── Parse arguments ─────────────────────────────────────────────────
REPO=""
BASE_BRANCH=""
PR_BRANCH="pin-actions-to-sha"
CACHE_FILE="/tmp/gha-pin-cache.json"
USE_FORK=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    --base-branch)
      [[ -z "${2:-}" ]] && { echo "Error: --base-branch requires a value" >&2; exit 1; }
      BASE_BRANCH="$2"
      shift 2
      ;;
    --pr-branch)
      [[ -z "${2:-}" ]] && { echo "Error: --pr-branch requires a value" >&2; exit 1; }
      PR_BRANCH="$2"
      shift 2
      ;;
    --cache-file)
      [[ -z "${2:-}" ]] && { echo "Error: --cache-file requires a value" >&2; exit 1; }
      CACHE_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --use-fork)
      USE_FORK=true
      shift
      ;;
    -*)
      echo "Error: unknown option: $1" >&2
      echo "Run '$0 --help' for usage information." >&2
      exit 1
      ;;
    *)
      if [[ -z "$REPO" ]]; then
        REPO="$1"
      else
        echo "Error: unexpected argument: $1" >&2
        echo "Run '$0 --help' for usage information." >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$REPO" || "$REPO" != */* ]]; then
  echo "Error: OWNER/REPO is required." >&2
  echo "Run '$0 --help' for usage information." >&2
  exit 1
fi

for cmd in gh git awk jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is required but not found" >&2
    exit 1
  fi
done

if ! gh auth status >/dev/null 2>&1; then
  echo "Error: gh is not authenticated. Run: gh auth login" >&2
  exit 1
fi

OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

WORKDIR="$(mktemp -d)"
SHOULD_CLEANUP=true

cleanup() {
  if [[ "$SHOULD_CLEANUP" == true ]]; then
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

PRIVATE_LOG="${WORKDIR}/private-action-uses.log"
: > "$PRIVATE_LOG"

# ─── Hardcoded overrides ─────────────────────────────────────────────
declare -A HARDCODED_PINS=(
  ["aquasecurity/trivy-action"]="57a97c7e7821a5776cebc9bb87c984fa69cba8f1:v0.35.0"
  ["aquasecurity/setup-trivy"]="3fb12ec12f41e471780db15c232d5dd185dcb514:v0.2.6"
)

hardcoded_lookup() {
  local key="$1"
  echo "${HARDCODED_PINS[$key]:-}"
}

# ─── Cache file handling ─────────────────────────────────────────────
if [[ ! -f "$CACHE_FILE" ]]; then
  echo '{}' > "$CACHE_FILE"
fi

cache_get_sha() {
  local key="$1"
  jq -r --arg k "$key" '.[$k].sha // empty' "$CACHE_FILE"
}

cache_get_comment() {
  local key="$1"
  jq -r --arg k "$key" '.[$k].comment // empty' "$CACHE_FILE"
}

cache_set() {
  local key="$1" sha="$2" comment="$3"
  local tmp="${CACHE_FILE}.tmp.$$"
  jq --arg k "$key" --arg s "$sha" --arg c "$comment" \
    '.[$k] = {"sha": $s, "comment": $c}' "$CACHE_FILE" > "$tmp" \
    && mv "$tmp" "$CACHE_FILE"
}

# ─── Clone ───────────────────────────────────────────────────────────
echo "==> Cache file: $CACHE_FILE"

if [[ -n "$BASE_BRANCH" ]]; then
  echo "==> Cloning $REPO via SSH (branch: $BASE_BRANCH) ..."
  git clone --branch "$BASE_BRANCH" "git@github.com:${OWNER}/${NAME}.git" "${WORKDIR}/${NAME}"
else
  echo "==> Cloning $REPO via SSH (default branch) ..."
  git clone "git@github.com:${OWNER}/${NAME}.git" "${WORKDIR}/${NAME}"
fi

cd "${WORKDIR}/${NAME}"

# Detect the actual base branch we ended up on
if [[ -n "$BASE_BRANCH" ]]; then
  ACTUAL_BASE="$BASE_BRANCH"
else
  ACTUAL_BASE="$(git remote show origin | awk '/HEAD branch/ {print $NF}')"
  ACTUAL_BASE="${ACTUAL_BASE:-main}"
fi

echo "==> Base branch: $ACTUAL_BASE"
echo "==> Creating PR branch: $PR_BRANCH"
git checkout -b "$PR_BRANCH" "origin/${ACTUAL_BASE}"

PUSH_REMOTE="origin"
PR_HEAD="$PR_BRANCH"
if [[ "$USE_FORK" == true ]]; then
  GH_USER="$(gh api user --jq '.login')"
  if [[ -z "$GH_USER" || "$GH_USER" == "null" ]]; then
    echo "Error: could not resolve authenticated GitHub user" >&2
    exit 1
  fi

  echo "==> Ensuring fork exists: ${GH_USER}/${NAME} ..."
  if ! gh repo view "${GH_USER}/${NAME}" >/dev/null 2>&1; then
    gh repo fork "$REPO" --clone=false --remote=false >/dev/null
  fi

  if git remote get-url fork >/dev/null 2>&1; then
    git remote set-url fork "git@github.com:${GH_USER}/${NAME}.git"
  else
    git remote add fork "git@github.com:${GH_USER}/${NAME}.git"
  fi

  PUSH_REMOTE="fork"
  PR_HEAD="${GH_USER}:${PR_BRANCH}"
fi

# ─── Collect YAML files ───────────────────────────────────────────────
mapfile -t FILES < <(
  find . -type f \( -name '*.yml' -o -name '*.yaml' \) -not -path './.git/*' 2>/dev/null | sort -u
)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No YAML files found."
  exit 0
fi

echo "==> Found ${#FILES[@]} file(s) to scan"

# ─── Extract every uses: value with file + line number ───────────────
# Outputs: FILE:LINENO:ORIGINAL_USES_VALUE
extract_all_uses() {
  local f
  for f in "${FILES[@]}"; do
    awk -v file="$f" '
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /^[[:space:]]*(-[[:space:]]+)?uses[[:space:]]*:/) {
        val = line
        sub(/^[[:space:]]*(-[[:space:]]+)?uses[[:space:]]*:[[:space:]]*/, "", val)
        gsub(/^["'\''"]|["'\''"]$/, "", val)
        sub(/[[:space:]]+#.*$/, "", val)
        sub(/[[:space:]]+$/, "", val)
        if (val != "") {
          printf "%s:%d:%s\n", file, NR, val
        }
      }
    }
    ' "$f"
  done
}

is_sha() { [[ "$1" =~ ^[0-9a-fA-F]{40}$ ]]; }

resolve_tag_sha() {
  local owner="$1" repo="$2" tag="$3"
  local json sha obj_type inner
  local rc=0

  json="$(gh api "repos/${owner}/${repo}/git/ref/tags/${tag}" 2>/dev/null)" || rc=$?
  if (( rc != 0 )); then return 1; fi

  sha="$(echo "$json" | jq -r '.object.sha // empty')"
  obj_type="$(echo "$json" | jq -r '.object.type // empty')"
  [[ -z "$sha" ]] && return 1

  if [[ "$obj_type" == "tag" ]]; then
    inner="$(gh api "repos/${owner}/${repo}/git/tags/${sha}" 2>/dev/null | jq -r '.object.sha // empty')" || true
    [[ -n "$inner" ]] && sha="$inner"
  fi

  echo "$sha"
}

resolve_branch_sha() {
  local owner="$1" repo="$2" branch="$3"
  local json sha
  local rc=0

  json="$(gh api "repos/${owner}/${repo}/git/ref/heads/${branch}" 2>/dev/null)" || rc=$?
  if (( rc != 0 )); then return 1; fi

  sha="$(echo "$json" | jq -r '.object.sha // empty')"
  [[ -z "$sha" ]] && return 1
  echo "$sha"
}

ref_is_tag() {
  local owner="$1" repo="$2" ref="$3"
  gh api "repos/${owner}/${repo}/git/ref/tags/${ref}" >/dev/null 2>&1
}

latest_release_tag() {
  local owner="$1" repo="$2"
  local tag
  tag="$(gh release list -R "${owner}/${repo}" --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null)" || true
  [[ -n "$tag" && "$tag" != "null" ]] && { echo "$tag"; return 0; }
  return 1
}

# ─── Main processing loop ───────────────────────────────────────────
total=0
pinned=0
skipped=0
failed=0
private=0
cache_hits=0
hardcoded_hits=0

echo "==> Processing uses: references ..."

while IFS=: read -r file lineno uses_val; do
  ((total++)) || true

  [[ "$uses_val" == ./* || "$uses_val" == ../* || "$uses_val" == docker://* ]] && continue
  [[ "$uses_val" != *@* ]] && continue

  left="${uses_val%@*}"
  ref="${uses_val##*@}"

  # shellcheck disable=SC2034
  IFS='/' read -r gha_owner gha_repo _ <<< "$left"
  [[ -z "${gha_owner:-}" || -z "${gha_repo:-}" ]] && continue

  gha_path=""
  if [[ "$left" != "${gha_owner}/${gha_repo}" ]]; then
    gha_path="${left#"${gha_owner}/${gha_repo}"}"
  fi

  if is_sha "$ref"; then
    ((skipped++)) || true
    continue
  fi

  echo "  Processing: ${gha_owner}/${gha_repo}${gha_path}@${ref} (${file}:${lineno})"

  sha=""
  comment=""

  # ── Check hardcoded overrides first ──
  hc_key="${gha_owner}/${gha_repo}"
  hc_val="$(hardcoded_lookup "$hc_key")"

  if [[ -n "$hc_val" ]]; then
    sha="${hc_val%%:*}"
    comment="${hc_val#*:}"
    echo "    Hardcoded override: @${sha} # ${comment}"
    ((hardcoded_hits++)) || true
  else
    # ── Check cache ──
    cache_key="${gha_owner}/${gha_repo}@${ref}"
    cached_sha="$(cache_get_sha "$cache_key")"
    cached_comment="$(cache_get_comment "$cache_key")"

    if [[ -n "$cached_sha" ]] && is_sha "$cached_sha"; then
      sha="$cached_sha"
      comment="$cached_comment"
      echo "    Cache hit: @${sha} # ${comment}"
      ((cache_hits++)) || true
    else
      if ref_is_tag "$gha_owner" "$gha_repo" "$ref"; then
        sha="$(resolve_tag_sha "$gha_owner" "$gha_repo" "$ref" || true)"
        comment="$ref"
      else
        latest="$(latest_release_tag "$gha_owner" "$gha_repo" || true)"
        if [[ -n "$latest" ]]; then
          sha="$(resolve_tag_sha "$gha_owner" "$gha_repo" "$latest" || true)"
          comment="$latest"
        fi

        if [[ -z "$sha" ]] || ! is_sha "$sha"; then
          sha="$(resolve_branch_sha "$gha_owner" "$gha_repo" "$ref" || true)"
          comment="$ref"
        fi
      fi

      if [[ -z "$sha" ]] || ! is_sha "$sha"; then
        echo "    WARN: could not resolve to SHA, logging as inaccessible"
        printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$file" "$uses_val" "inaccessible/private" >> "$PRIVATE_LOG"
        ((private++)) || true
        continue
      fi

      cache_set "$cache_key" "$sha" "$comment"
    fi
  fi

  new_uses_base="${gha_owner}/${gha_repo}${gha_path}@${sha}"

  if [[ "$new_uses_base" == "$uses_val" ]]; then
    continue
  fi

  awk -v ln="$lineno" -v newbase="$new_uses_base" -v newcomment="$comment" '
    BEGIN { squote = sprintf("%c", 39) }
    NR == ln {
      if (match($0, /^[[:space:]]*(-[[:space:]]+)?uses[[:space:]]*:[[:space:]]*/)) {
        prefix = substr($0, 1, RLENGTH)
        rest = substr($0, RLENGTH + 1)
        quote = substr(rest, 1, 1)

        if (quote == "\"" || quote == squote) {
          value = quote newbase quote
        } else {
          value = newbase
        }

        $0 = prefix value " # " newcomment
      }
    }
    { print }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  echo "    Pinned: @${sha} # ${comment}"
  ((pinned++)) || true

done < <(extract_all_uses)

echo
echo "==> Summary"
echo "    Total uses: references found : $total"
echo "    Already pinned (SHA)         : $skipped"
echo "    Pinned in this run           : $pinned"
echo "    Resolved from cache          : $cache_hits"
echo "    Hardcoded overrides applied  : $hardcoded_hits"
echo "    Private/inaccessible (logged): $private"
echo "    Failed to resolve            : $failed"

if (( private > 0 )); then
  echo "    Log file: $PRIVATE_LOG"
fi

# ─── Show diff and ask for approval ─────────────────────────────────
git add -A

if git diff --cached --quiet; then
  echo
  echo "==> No changes to commit."
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  echo
  echo "==> Dry-run mode: proposed changes (no commit/push/PR)"
  echo "────────────────────────────────────────────────────────────────"
  git diff --cached
  echo "────────────────────────────────────────────────────────────────"
  exit 0
fi

echo
echo "==> Changes to be committed:"
echo "────────────────────────────────────────────────────────────────"
git diff --cached
echo "────────────────────────────────────────────────────────────────"
echo

while true; do
  read -rp "Do you approve these changes? [y]es / [n]o / [d]iff again: " answer
  case "$answer" in
    [yY]|[yY][eE][sS])
      break
      ;;
    [nN]|[nN][oO])
      echo
      echo "==> Aborted. The working copy is preserved at:"
      echo "    ${WORKDIR}/${NAME}"
      echo
      echo "    You can cd into it, make manual edits, then:"
      echo "      git add -A && git commit -m 'Pin GH Actions to commit sha'"
      echo "      git push -u origin ${PR_BRANCH}"
      echo "      gh pr create --base ${ACTUAL_BASE} --head ${PR_BRANCH} --title 'Pin GH Actions to commit sha' --body 'Pin GH Actions to commit sha'"
      echo
      SHOULD_CLEANUP=false
      exit 0
      ;;
    [dD]|[dD][iI][fF][fF])
      git diff --cached
      ;;
    *)
      echo "Please answer y, n, or d."
      ;;
  esac
done

# ─── Commit, push, open PR ──────────────────────────────────────────
git commit -m "Pin GH Actions to commit sha"

echo
echo "==> Pushing branch '$PR_BRANCH' ..."
if ! git push -u "$PUSH_REMOTE" "$PR_BRANCH"; then
  echo
  echo "==> Push failed to remote '$PUSH_REMOTE'."
  echo "    This usually means missing write permission to the target repository."
  echo "    Try rerunning with --use-fork so the branch is pushed to your fork."
  echo "    Working copy preserved at: ${WORKDIR}/${NAME}"
  SHOULD_CLEANUP=false
  exit 1
fi

echo
echo "==> Opening PR against '$ACTUAL_BASE' ..."
gh pr create \
  --base "$ACTUAL_BASE" \
  --head "$PR_HEAD" \
  --title "Pin GH Actions to commit sha" \
  --body "Pin GH Actions to commit sha"

echo
echo "==> Done."