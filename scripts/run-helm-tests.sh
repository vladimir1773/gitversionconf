#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITVERSION_CONFIG="$ROOT_DIR/GitVersion.helm.yml"
WORK_ROOT="${TMPDIR:-/tmp}/gitversion-helm-tests.$$"

pass_count=0

cleanup() {
  rm -rf "$WORK_ROOT"
}

trap cleanup EXIT

log() {
  printf '\n== %s ==\n' "$1"
}

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' \
      "$name" "$expected" "$actual" >&2
    exit 1
  fi

  pass_count=$((pass_count + 1))
  printf 'PASS %s -> %s\n' "$name" "$actual"
}

gv() {
  gitversion /showvariable "$1"
}

init_repo() {
  local repo="$1"
  local default_branch="${2:-main}"

  mkdir -p "$repo"
  cp "$GITVERSION_CONFIG" "$repo/GitVersion.yml"

  git -C "$repo" init -b "$default_branch" >/dev/null
  git -C "$repo" config user.name "GitVersion Helm Test"
  git -C "$repo" config user.email "gitversion-helm-test@example.local"

  touch "$repo/Chart.yaml"
  git -C "$repo" add Chart.yaml GitVersion.yml
  git -C "$repo" commit -m "initial chart" >/dev/null
}

make_commit() {
  local repo="$1"
  local file="$2"
  local message="$3"

  touch "$repo/$file"
  git -C "$repo" add "$file"
  git -C "$repo" commit -m "$message" >/dev/null
}

merge_to_default() {
  local repo="$1"
  local default_branch="$2"
  local source_branch="$3"

  git -C "$repo" switch "$default_branch" >/dev/null
  git -C "$repo" merge --no-ff "$source_branch" \
    -m "merge $source_branch" >/dev/null
}

test_initial_version() {
  log "untagged main starts at 0.0.1"
  local repo="$WORK_ROOT/initial"
  init_repo "$repo"

  assert_eq "initial MajorMinorPatch" "0.0.1" "$(cd "$repo" && gv MajorMinorPatch)"
}

test_feature_tag_and_minor_bump() {
  log "arbitrary feature tags are ignored and feat bumps minor"
  local repo="$WORK_ROOT/feature-tags"
  init_repo "$repo"
  git -C "$repo" tag 0.1.0

  git -C "$repo" switch -c feature/chart-change >/dev/null
  make_commit "$repo" values.yaml "feat: add chart values"
  git -C "$repo" tag preview-chart-change
  git -C "$repo" tag 9.9.9-feature-preview.7

  merge_to_default "$repo" main feature/chart-change

  assert_eq "minor bump after feature merge" "0.2.0" "$(cd "$repo" && gv MajorMinorPatch)"
}

test_conventional_commit_bumps() {
  local bump_type="$1"
  local message="$2"
  local expected="$3"
  local repo="$WORK_ROOT/conventional-$bump_type"

  log "Conventional Commit $bump_type bump"
  init_repo "$repo"
  git -C "$repo" tag 0.1.0

  git -C "$repo" switch -c "feature/$bump_type-change" >/dev/null
  make_commit "$repo" "$bump_type.txt" "$message"
  merge_to_default "$repo" main "feature/$bump_type-change"

  assert_eq "$bump_type bump" "$expected" "$(cd "$repo" && gv MajorMinorPatch)"
}

test_semver_marker_bump() {
  log "+semver marker is read from merged feature history"
  local repo="$WORK_ROOT/semver-marker"
  init_repo "$repo"
  git -C "$repo" tag 0.1.0

  git -C "$repo" switch -c feature/explicit-minor >/dev/null
  make_commit "$repo" marker.txt "chart adjustment +semver: minor"
  merge_to_default "$repo" main feature/explicit-minor

  assert_eq "+semver minor bump" "0.2.0" "$(cd "$repo" && gv MajorMinorPatch)"
}

test_master_branch() {
  log "master is supported as the default branch"
  local repo="$WORK_ROOT/master"
  init_repo "$repo" master
  git -C "$repo" tag 0.1.0

  git -C "$repo" switch -c feature/master-patch >/dev/null
  make_commit "$repo" patch.txt "fix: patch chart on master"
  merge_to_default "$repo" master feature/master-patch

  assert_eq "master patch bump" "0.1.1" "$(cd "$repo" && gv MajorMinorPatch)"
}

main() {
  if ! command -v gitversion >/dev/null 2>&1; then
    printf 'ERROR gitversion is not installed or not on PATH.\n' >&2
    exit 1
  fi

  if [[ ! -f "$GITVERSION_CONFIG" ]]; then
    printf 'ERROR missing configuration: %s\n' "$GITVERSION_CONFIG" >&2
    exit 1
  fi

  mkdir -p "$WORK_ROOT"

  test_initial_version
  test_feature_tag_and_minor_bump
  test_conventional_commit_bumps patch "fix: correct chart template" 0.1.1
  test_conventional_commit_bumps minor "feat: add chart capability" 0.2.0
  test_conventional_commit_bumps major "feat!: change chart contract" 1.0.0
  test_semver_marker_bump
  test_master_branch

  printf '\nAll Helm tests passed: %d\n' "$pass_count"
}

main "$@"
