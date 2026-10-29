#!/usr/bin/env bash
# Works out the next version from conventional commits and tags HEAD.
set -euo pipefail

DRY_RUN="${DRY_RUN:-false}"

# 1. Latest stable tag. Only vX.Y.Z counts, so v1.2.3-rc1 is ignored
last=$(git tag --merged HEAD --list "v*" --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)
range="HEAD"
[ -n "$last" ] && range="$last..HEAD"

# 2. Read each commit, sort it into a changelog group, and track the bump
# Regexes sit in variables; bash will not parse the parentheses inline
re_break='^[a-z]+(\([^)]*\))?!:'
re_feat='^feat(\([^)]*\))?:'
re_fix='^(fix|perf)(\([^)]*\))?:'
bump=""
breaking="" features="" fixes=""
while read -r sha; do
  subject=$(git log -1 --format=%s "$sha")
  body=$(git log -1 --format=%b "$sha")
  text="- ${subject#*: }"

  if [[ "$subject" =~ $re_break ]] || grep -q '^BREAKING CHANGE:' <<<"$body"; then
    bump="major"
    breaking+="$text"$'\n'
  elif [[ "$subject" =~ $re_feat ]]; then
    [ "$bump" != major ] && bump="minor"
    features+="$text"$'\n'
  elif [[ "$subject" =~ $re_fix ]]; then
    [ -z "$bump" ] && bump="patch"
    fixes+="$text"$'\n'
  fi
done < <(git log --no-merges --format=%H "$range")

# 3. No release-worthy commits
if [ -z "$bump" ]; then
  echo "no release"
  exit 0
fi

# 4. New version
if [ -z "$last" ]; then
  version="v0.1.0"
else
  IFS=. read -r major minor patch <<<"${last#v}"
  case "$bump" in
    major) version="v$((major + 1)).0.0" ;;
    minor) version="v$major.$((minor + 1)).0" ;;
    patch) version="v$major.$minor.$((patch + 1))" ;;
  esac
fi
echo "$version"

# 5. Release notes go in a file, never in the repo history
notes="${RUNNER_TEMP:-$PWD}/release-notes.md"
section="## $version - $(date +%Y-%m-%d)"$'\n'
[ -n "$breaking" ] && section+=$'\n'"### Breaking changes"$'\n'"$breaking"
[ -n "$features" ] && section+=$'\n'"### Features"$'\n'"$features"
[ -n "$fixes" ] && section+=$'\n'"### Fixes"$'\n'"$fixes"
printf '%s' "$section" >"$notes"
echo "$notes"

# The action reads these to create the GitHub release
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "version=$version" >>"$GITHUB_OUTPUT"
  echo "notes=$notes" >>"$GITHUB_OUTPUT"
fi

[ "$DRY_RUN" = "true" ] && exit 0

# 6. Tag the current HEAD and push the tag only
git -c user.name="github-actions" -c user.email="actions@users.noreply.github.com" \
  tag -a "$version" -m "Release $version"
git push origin "$version"
