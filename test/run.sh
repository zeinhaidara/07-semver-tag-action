#!/usr/bin/env bash
# Each case builds a throwaway repo. Most run the script in dry-run mode.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/scripts/release.sh"
fails=0

# new_repo: empty repo in a temp folder, we cd into it
new_repo() {
  dir=$(mktemp -d)
  cd "$dir"
  git init -q
  git config user.name test
  git config user.email test@example.com
}

commit() { git commit -q --allow-empty -m "$1"; }

# check <name> <expected first line of output>
check() {
  got=$(DRY_RUN=true bash "$script")
  got=${got%%$'\n'*} # first line only
  if [ "$got" = "$2" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1: expected '$2', got '$got'"
    fails=$((fails + 1))
  fi
}

# tagged_repo: repo with one commit tagged v1.2.3
tagged_repo() {
  new_repo
  commit "chore: start"
  git tag v1.2.3
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
check "no release-worthy type" "no release"

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
bash "$script" >/dev/null 2>&1
if git -C "$origin" tag | grep -qx v0.1.0 &&
  [ "$(git rev-parse HEAD)" = "$head_before" ] &&
  [ "$(git rev-list --count HEAD)" = "$count_before" ]; then
  echo "ok   push tags HEAD, makes no commit"
else
  echo "FAIL push tags HEAD, makes no commit"
  fails=$((fails + 1))
fi

[ "$fails" -eq 0 ]
