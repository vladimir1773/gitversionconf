#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITVERSION_CONFIG="$ROOT_DIR/GitVersion.yml"
WORK_ROOT="${TMPDIR:-/tmp}/gitversion-config-tests.$$"

pass_count=0
fail_count=0

cleanup() {
  rm -rf "$WORK_ROOT"
}

trap cleanup EXIT

log() {
  printf '\n== %s ==\n' "$1"
}

pass() {
  pass_count=$((pass_count + 1))
  printf 'PASS %s\n' "$1"
}

fail() {
  fail_count=$((fail_count + 1))
  printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" == "$expected" ]]; then
    pass "$name -> $actual"
  else
    fail "$name" "$expected" "$actual"
    exit 1
  fi
}

gv() {
  gitversion /showvariable "$1"
}

init_repo() {
  local repo="$1"

  mkdir -p "$repo"
  cp "$GITVERSION_CONFIG" "$repo/GitVersion.yml"

  git -C "$repo" init -b main >/dev/null
  git -C "$repo" config user.name "GitVersion Test"
  git -C "$repo" config user.email "gitversion-test@example.local"

  touch "$repo/README.md"
  git -C "$repo" add README.md GitVersion.yml
  git -C "$repo" commit -m "initial" >/dev/null
  git -C "$repo" tag 0.1.0
}

make_commit() {
  local repo="$1"
  local file="$2"
  local message="$3"

  touch "$repo/$file"
  git -C "$repo" add "$file"
  git -C "$repo" commit -m "$message" >/dev/null
}

test_main_stable_tag() {
  log "main stable tag uses MajorMinorPatch"
  local repo="$WORK_ROOT/main-stable"
  init_repo "$repo"

  assert_eq "main MajorMinorPatch" "0.1.0" "$(cd "$repo" && gv MajorMinorPatch)"
  assert_eq "main FullSemVer" "0.1.0" "$(cd "$repo" && gv FullSemVer)"
}

test_hotfix_ignores_breaking_bump_while_open() {
  log "hotfix keeps source SemVer even with breaking-change commit"
  local repo="$WORK_ROOT/hotfix-breaking"
  init_repo "$repo"

  git -C "$repo" switch -c hotfix/urgent >/dev/null
  make_commit "$repo" "urgent.txt" "BREAKING CHANGE: test-only hotfix message"

  assert_eq "hotfix MajorMinorPatch" "0.1.0" "$(cd "$repo" && gv MajorMinorPatch)"
  assert_eq "hotfix FullSemVer" "0.1.0-hotfix-urgent.1" "$(cd "$repo" && gv FullSemVer)"

  make_commit "$repo" "urgent-2.txt" "fix: second urgent patch"
  assert_eq "hotfix second FullSemVer" "0.1.0-hotfix-urgent.2" "$(cd "$repo" && gv FullSemVer)"
}

test_parallel_hotfixes_are_unique() {
  log "parallel hotfix branches include branch name"
  local repo="$WORK_ROOT/parallel-hotfix"
  init_repo "$repo"

  git -C "$repo" switch -c hotfix/urgent >/dev/null
  make_commit "$repo" "urgent.txt" "fix: urgent patch"
  assert_eq "urgent hotfix FullSemVer" "0.1.0-hotfix-urgent.1" "$(cd "$repo" && gv FullSemVer)"

  git -C "$repo" switch main >/dev/null
  git -C "$repo" switch -c hotfix/login-fix >/dev/null
  make_commit "$repo" "login.txt" "fix: login patch"
  assert_eq "login hotfix FullSemVer" "0.1.0-hotfix-login-fix.1" "$(cd "$repo" && gv FullSemVer)"
}

test_hotfix_backmerge_updates_main_patch() {
  log "hotfix backmerge updates main stable version"
  local repo="$WORK_ROOT/hotfix-backmerge"
  init_repo "$repo"

  git -C "$repo" switch -c hotfix/urgent >/dev/null
  make_commit "$repo" "urgent.txt" "fix: urgent patch"

  git -C "$repo" switch main >/dev/null
  git -C "$repo" merge --no-ff hotfix/urgent -m "merge hotfix urgent" >/dev/null

  assert_eq "main MajorMinorPatch after hotfix merge" "0.1.1" "$(cd "$repo" && gv MajorMinorPatch)"
}

test_feature_tags_do_not_take_over() {
  log "feature tags do not become main version source"
  local repo="$WORK_ROOT/feature-tags"
  init_repo "$repo"

  git -C "$repo" switch -c feature/free-tag-test >/dev/null
  make_commit "$repo" "feature.txt" "feat: add free tag test feature"
  git -C "$repo" tag "whatever-devs-want"
  git -C "$repo" tag "9.9.9-random-feature-tag"

  git -C "$repo" switch main >/dev/null
  git -C "$repo" merge --no-ff feature/free-tag-test -m "merge feature free-tag-test" >/dev/null

  assert_eq "main MajorMinorPatch ignores feature tag" "0.2.0" "$(cd "$repo" && gv MajorMinorPatch)"
}

test_conventional_major_bump() {
  log "conventional breaking feature bumps main major"
  local repo="$WORK_ROOT/conventional-major"
  init_repo "$repo"

  git -C "$repo" switch -c feature/major-test >/dev/null
  make_commit "$repo" "breaking.txt" "feat!: change public contract"

  git -C "$repo" switch main >/dev/null
  git -C "$repo" merge --no-ff feature/major-test -m "merge feature major-test" >/dev/null

  assert_eq "main MajorMinorPatch after feat!" "1.0.0" "$(cd "$repo" && gv MajorMinorPatch)"
}

main() {
  if ! command -v gitversion >/dev/null 2>&1; then
    printf 'ERROR gitversion is not installed or not on PATH.\n' >&2
    exit 1
  fi

  mkdir -p "$WORK_ROOT"

  test_main_stable_tag
  test_hotfix_ignores_breaking_bump_while_open
  test_parallel_hotfixes_are_unique
  test_hotfix_backmerge_updates_main_patch
  test_feature_tags_do_not_take_over
  test_conventional_major_bump

  printf '\nAll tests passed: %d\n' "$pass_count"
}

main "$@"
