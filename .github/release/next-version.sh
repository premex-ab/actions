#!/usr/bin/env bash
# Prints the next release version for HEAD, or nothing when HEAD has nothing to release.
#   - Only changes outside the actions (tests, docs, .github, test projects): no release.
#   - A new action (a new */action.yml): minor. Any other action change: patch.
#   - LABELS (newline-separated labels of the PRs merged since the last release) can raise it:
#     'major' or 'minor'.
set -euo pipefail

last="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n 1)"
if [[ -z "$last" ]]; then
  echo "v1.0.0"
  exit 0
fi

released="$(git diff --name-only "$last" HEAD -- . \
  ':(exclude).github' ':(exclude)*.md' ':(exclude)LICENSE' ':(exclude).gitignore' \
  ':(exclude)test-gradle-project-*')"
[[ -z "$released" ]] && exit 0

bump="patch"
[[ -n "$(git diff --name-only --diff-filter=A "$last" HEAD -- '*/action.yml')" ]] && bump=minor
labels="${LABELS:-}"
grep -qx minor <<< "$labels" && bump=minor
grep -qx major <<< "$labels" && bump=major

IFS=. read -r major minor patch <<< "${last#v}"
case "$bump" in
  major) echo "v$((major + 1)).0.0" ;;
  minor) echo "v$major.$((minor + 1)).0" ;;
  patch) echo "v$major.$minor.$((patch + 1))" ;;
esac
