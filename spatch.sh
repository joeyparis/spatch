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

usage() {
  echo "Usage:"
  echo "  spatch create <branch1> [branch2 ...]"
  echo "  spatch undo <branch>"
  echo "  spatch list"
  echo "  spatch clean"
  exit 1
}

combo_create() {
  local combo_branch="stage/spatch-$(date +%Y%m%d%H%M%S)"
  echo "Creating combo branch: $combo_branch from $BASE_BRANCH"

  git checkout "$BASE_BRANCH"
  # git pull origin-ssh "$BASE_BRANCH"
  git checkout -b "$combo_branch"

  for branch in "$@"; do
    echo "Bundling branch: $branch"
    local patch_file="$COMBO_DIR/$branch.patch"
    local merge_base
    merge_base=$(git merge-base "$BASE_BRANCH" "$branch")
    echo "MERGE_BASE $merge_base"

    git diff --diff-filter=ACMRT --text "$merge_base".."$branch" |
      grep -av '^GIT binary patch' |
      perl -ne '
        if (/^diff --git a\/.*\.build\s/) { $skip = 1; next }
        $skip = 0 if /^diff --git /;
        print unless $skip;
      ' > "$patch_file"
    
    git apply --index "$patch_file"
    git commit -m "Apply $branch as diff"
  done

  echo "✅ Combo branch ready: $combo_branch"
}

combo_undo() {
  local branch="$1"
  local patch_file="$COMBO_DIR/$branch.patch"

  if [[ ! -f "$patch_file" ]]; then
    echo "❌ No patch found for $branch"
    exit 1
  fi

  echo "Reversing patch from $branch"
  git apply --reverse --index "$patch_file"
  git commit -m "Revert $branch diff"

  echo "✅ Patch '$branch' reverted and committed."
}

combo_refresh() {
  if [[ ! -f "$COMBO_DIR/applied.txt" ]]; then
    echo "❌ No applied.txt found. Cannot refresh."
    exit 1
  fi

  local combo_branch="stage/combo-$(date +%Y%m%d%H%M%S)"
  echo "Refreshing combo branch: $combo_branch from $BASE_BRANCH"

  git checkout "$BASE_BRANCH"
  git checkout -b "$combo_branch"

  while read -r branch; do
    echo "Reapplying $branch"
    local patch_file="$COMBO_DIR/$branch.patch"
    local merge_base
    merge_base=$(git merge-base "$BASE_BRANCH" "$branch")
    git diff "$merge_base".."$branch" > "$patch_file"
    git apply --index "$patch_file"
    git commit -m "Apply $branch as diff"
  done < "$COMBO_DIR/applied.txt"

  echo "✅ Refreshed combo: $combo_branch"
}

combo_list() {
  echo "Available patches in $COMBO_DIR:"
  ls "$COMBO_DIR"/*.patch 2>/dev/null | sed 's/.*\///' | sed 's/\.patch//'
}

combo_clean() {
  echo "Cleaning up $COMBO_DIR"
  rm -f "$COMBO_DIR"/*.patch
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

