#!/usr/bin/env bash
# Works out the next version from conventional commits, then tags it.
set -euo pipefail

DRY_RUN="${DRY_RUN:-false}"

# 1. Latest version tag (empty if there is none)
last=$(git describe --tags --abbrev=0 --match "v[0-9]*.[0-9]*.[0-9]*" 2>/dev/null || true)
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

[ "$DRY_RUN" = "true" ] && exit 0

# 5. Changelog, commit, tag, push the tag only
section="## $version - $(date +%Y-%m-%d)"$'\n'
[ -n "$breaking" ] && section+=$'\n'"### Breaking changes"$'\n'"$breaking"
[ -n "$features" ] && section+=$'\n'"### Features"$'\n'"$features"
[ -n "$fixes" ] && section+=$'\n'"### Fixes"$'\n'"$fixes"

old=""
[ -f CHANGELOG.md ] && old=$(tail -n +3 CHANGELOG.md)
printf '# Changelog\n\n%s\n%s\n' "$section" "$old" >CHANGELOG.md

git add CHANGELOG.md
git -c user.name="github-actions" -c user.email="actions@users.noreply.github.com" \
  commit -m "Release $version"
git -c user.name="github-actions" -c user.email="actions@users.noreply.github.com" \
  tag -a "$version" -m "Release $version"
git push origin "$version"
