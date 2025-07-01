#!/bin/bash

# Load local project config
SPATCHRC_PATH="${SPATCHRC_PATH:-.spatchrc}"
if [[ -f "$SPATCHRC_PATH" ]]; then
  echo "📦 Loading config from $SPATCHRC_PATH"
  source "$SPATCHRC_PATH"
fi

COMBO_DIR="${COMBO_DIR:-.git/spatches}"
BASE_BRANCH="${BASE_BRANCH:-develop}"

set -e

mkdir -p "$COMBO_DIR"

sanitize_branch_name() {
  echo "$1" | sed 's|/|__|g'
}

usage() {
  echo "Usage:"
  echo "  spatch create <branch1> [branch2 ...]"
  echo "  spatch undo <branch>"
  echo "  spatch refresh"
  echo "  spatch list"
  echo "  spatch clean"
  exit 1
}

combo_create() {
  local combo_branch="stage/spatch-$(date +%Y%m%d%H%M%S)"
  echo "Creating combo branch: $combo_branch from $BASE_BRANCH"

  git checkout "$BASE_BRANCH"
  git pull origin-ssh "$BASE_BRANCH"
  local base_sha
  base_sha=$(git rev-parse HEAD)

  git checkout -b "$combo_branch"
  rm -f "$COMBO_DIR/applied.txt"

  for branch in "$@"; do
    echo "Bundling branch: $branch"
    local sanitized_branch
    sanitized_branch=$(sanitize_branch_name "$branch")
    local patch_file="$COMBO_DIR/${sanitized_branch}.patch"
    local merge_base
    merge_base=$(git merge-base "$base_sha" "$branch")
    echo "MERGE_BASE $merge_base"

    git diff --diff-filter=ACMRT --text "$merge_base".."$branch" |
      grep -av '^GIT binary patch' |
      LC_ALL=C perl -ne '
        if (/^diff --git a\/.*\.build(\s|$)/) { $skip = 1; next }
        $skip = 0 if /^diff --git /;
        print unless $skip;
      ' > "$patch_file"

    if git diff --quiet "$merge_base".."$branch"; then
      echo "⚠️  No diff found for $branch (possibly already in base) — skipping"
      continue
    fi

    git apply --index "$patch_file"
    git commit -m "Apply $branch as diff"
    echo "$branch $(git rev-parse HEAD)" >> "$COMBO_DIR/applied.txt"
    echo "✔ Applied $branch"
  done

  echo "✅ Combo branch ready: $combo_branch"
}

combo_undo() {
  local branch="$1"
  local sanitized_branch
  sanitized_branch=$(sanitize_branch_name "$branch")
  local patch_file="$COMBO_DIR/${sanitized_branch}.patch"

  if [[ ! -f "$patch_file" ]]; then
    echo "❌ No patch found for $branch"
    exit 1
  fi

  local sha
  sha=$(grep "^$branch " "$COMBO_DIR/applied.txt" | awk '{print $2}')

  if [[ -z "$sha" ]]; then
    echo "❌ No commit found for $branch in applied.txt"
    exit 1
  fi

  echo "Reverting commit $sha for $branch"
  git revert -n "$sha"
  git commit -m "Revert $branch diff"

  # Remove from applied.txt
  grep -v "^$branch " "$COMBO_DIR/applied.txt" > "$COMBO_DIR/.applied.tmp"
  mv "$COMBO_DIR/.applied.tmp" "$COMBO_DIR/applied.txt"

  echo "✅ Reverted and cleaned $branch"
}

combo_refresh() {
  if [[ ! -f "$COMBO_DIR/applied.txt" ]]; then
    echo "❌ No applied.txt found. Cannot refresh."
    exit 1
  fi

  local combo_branch="stage/spatch-$(date +%Y%m%d%H%M%S)"
  echo "Refreshing combo branch: $combo_branch from $BASE_BRANCH"

  git checkout "$BASE_BRANCH"
  git pull origin-ssh "$BASE_BRANCH"
  local base_sha
  base_sha=$(git rev-parse HEAD)

  git checkout -b "$combo_branch"

  while read -r branch sha; do
    echo "Reapplying $branch"
    local sanitized_branch
    sanitized_branch=$(sanitize_branch_name "$branch")
    local patch_file="$COMBO_DIR/${sanitized_branch}.patch"
    local merge_base
    merge_base=$(git merge-base "$base_sha" "$branch")

    git diff --diff-filter=ACMRT --text "$merge_base".."$branch" |
      grep -av '^GIT binary patch' |
      LC_ALL=C perl -ne '
        if (/^diff --git a\/.*\.build(\s|$)/) { $skip = 1; next }
        $skip = 0 if /^diff --git /;
        print unless $skip;
      ' > "$patch_file"

    git apply --index "$patch_file"
    git commit -m "Apply $branch as diff"
    echo "✔ Reapplied $branch"
  done < "$COMBO_DIR/applied.txt"

  echo "✅ Refreshed combo branch: $combo_branch"
}

combo_list() {
  echo "Available patches in $COMBO_DIR:"
  ls "$COMBO_DIR"/*.patch 2>/dev/null | sed 's/.*\///' | sed 's/\.patch//'

  echo ""
  if [[ -f "$COMBO_DIR/applied.txt" ]]; then
    echo "✅ Applied in current combo:"
    cut -d' ' -f1 "$COMBO_DIR/applied.txt"
  else
    echo "⚠️  No applied.txt found"
  fi
}

combo_clean() {
  echo "Cleaning up $COMBO_DIR"
  rm -f "$COMBO_DIR"/*.patch "$COMBO_DIR/applied.txt"
}

# Dispatch subcommands
case "$1" in
  create) shift; combo_create "$@" ;;
  undo) shift; combo_undo "$@" ;;
  refresh) combo_refresh ;;
  list) combo_list ;;
  clean) combo_clean ;;
  *) usage ;;
esac
