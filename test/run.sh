#!/usr/bin/env bash
# Each case builds a throwaway repo and runs the script in dry-run mode.
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

# check <name> <expected output>
check() {
  got=$(DRY_RUN=true bash "$script")
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

[ "$fails" -eq 0 ]
