#!/usr/bin/env bash
set -euo pipefail

tag="$1"
shift

for attempt in 1 2 3 4 5; do
  if gh release view "$tag" >/dev/null 2>&1; then
    gh release upload "$tag" "$@" --clobber
    exit 0
  fi
  if gh release create "$tag" "$@" --title "ProMax $tag" --generate-notes; then
    exit 0
  fi
  sleep $((attempt * 5))
done

echo "Could not publish $* to $tag" >&2
exit 1
