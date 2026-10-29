#!/usr/bin/env bash
# Each case builds a throwaway repo. Most run the script in dry-run mode.
set -euo pipefail

# CI sets these; the tests expect the script defaults
unset RUNNER_TEMP GITHUB_OUTPUT

script="$(cd "$(dirname "$0")/.." && pwd)/scripts/release.sh"

# new_repo: empty repo in a temp folder, we cd into it
new_repo() {
  cd "$(mktemp -d)"
  git init -q
  git config user.name test
  git config user.email test@example.com
}

commit() { git commit -q --allow-empty -m "$1"; }

# tagged_repo: repo with one commit tagged v1.2.3
tagged_repo() {
  new_repo
  commit "chore: start"
  git tag v1.2.3
}

# pass <name> / fail <name> <expected> <actual>
pass() { echo "ok   $1"; }
fail() {
  printf 'FAIL %s\n--- expected\n%s\n--- actual\n%s\n' "$1" "$2" "$3"
  exit 1
}

# check <name> <version>: the full dry-run output is the version, then the notes path
check() {
  want="$2"$'\n'"$PWD/release-notes.md"
  got=$(DRY_RUN=true bash "$script" 2>&1)
  if [ "$got" = "$want" ]; then pass "$1"; else fail "$1" "$want" "$got"; fi
}

tagged_repo
commit "fix: handle empty input"
check "fix gives patch" "v1.2.4"

tagged_repo
commit "feat: add export"
check "feat gives minor" "v1.3.0"

tagged_repo
commit "feat!: drop old api"
check "! gives major" "v2.0.0"

tagged_repo
commit "docs: update readme"
commit "chore: bump deps"
got=$(DRY_RUN=true bash "$script" 2>&1)
if [ "$got" = "no release" ]; then pass "no release-worthy type"; else fail "no release-worthy type" "no release" "$got"; fi

new_repo
commit "feat: first feature"
check "no tags gives v0.1.0" "v0.1.0"

tagged_repo
commit "fix: handle empty input"
git tag v1.3.0-rc1
check "pre-release tag is ignored" "v1.2.4"

# Push path: real run against a local bare origin
origin=$(mktemp -d)
git init -q --bare "$origin"
new_repo
git remote add origin "$origin"
commit "feat: first feature"
head_before=$(git rev-parse HEAD)
count_before=$(git rev-list --count HEAD)
# Drop git's "To <path>" line, the path differs per machine
got=$(bash "$script" 2>&1 | grep -v '^To ')
want="v0.1.0"$'\n'"$PWD/release-notes.md"$'\n'" * [new tag]         v0.1.0 -> v0.1.0"
[ "$got" = "$want" ] || fail "push tags HEAD, makes no commit" "$want" "$got"
tags=$(git -C "$origin" tag)
[ "$tags" = "v0.1.0" ] || fail "push tags HEAD, makes no commit" "tag v0.1.0 in origin" "origin tags: $tags"
[ "$(git rev-parse HEAD)" = "$head_before" ] || fail "push tags HEAD, makes no commit" "HEAD $head_before" "HEAD $(git rev-parse HEAD)"
[ "$(git rev-list --count HEAD)" = "$count_before" ] || fail "push tags HEAD, makes no commit" "$count_before commits" "$(git rev-list --count HEAD) commits"
pass "push tags HEAD, makes no commit"
