#!/usr/bin/env bash
set -euo pipefail

tag="$1"
shift

notes_file=".github/release-notes/${tag}.md"
title="ProMax $tag"
notes_args=(--generate-notes)
if [ -f "$notes_file" ]; then
  heading=$(head -n 1 "$notes_file")
  if [[ "$heading" == "# "* ]]; then
    title="${heading#\# }"
  fi
  tail -n +2 "$notes_file" > "$RUNNER_TEMP/release-notes.md"
  notes_args=(--notes-file "$RUNNER_TEMP/release-notes.md")
fi

for attempt in 1 2 3 4 5; do
  if gh release view "$tag" >/dev/null 2>&1; then
    gh release upload "$tag" "$@" --clobber
    exit 0
  fi
  if gh release create "$tag" "$@" --target "$GITHUB_SHA" --title "$title" "${notes_args[@]}"; then
    exit 0
  fi
  sleep $((attempt * 5))
done

echo "Could not publish $* to $tag" >&2
exit 1
