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

preview_apk='^ProMax-.+-preview-[^/]+\.apk$'
signed_apk='^ProMax-.+-promax-[^/]+\.apk$'

uploads_matching() {
  local file
  for file in "$@"; do
    if [[ "$(basename "$file")" =~ $pattern ]]; then
      return 0
    fi
  done
  return 1
}

release_assets() {
  gh release view "$tag" --json assets --jq '.assets[].name'
}

pattern="$preview_apk"
if uploads_matching "$@"; then
  if gh release view "$tag" >/dev/null 2>&1 && release_assets | grep -Eq "$signed_apk"; then
    echo "$tag already has signed APKs: refusing to add debug-signed preview APKs" >&2
    exit 1
  fi
fi

drop_preview_apks() {
  pattern="$signed_apk"
  uploads_matching "$@" || return 0
  local name
  release_assets | { grep -E "$preview_apk" || true; } | while IFS= read -r name; do
    echo "Removing preview APK $name from $tag"
    gh release delete-asset "$tag" "$name" --yes
  done
}

release_flags=()
if [[ "$tag" =~ -(alpha|beta|rc|preview)[.-] ]]; then
  release_flags=(--prerelease --latest=false)
fi

published=false
for attempt in 1 2 3 4 5; do
  if gh release view "$tag" >/dev/null 2>&1; then
    gh release upload "$tag" "$@" --clobber
    published=true
    break
  fi
  if gh release create "$tag" "$@" --target "$GITHUB_SHA" --title "$title" "${notes_args[@]}" "${release_flags[@]}"; then
    published=true
    break
  fi
  sleep $((attempt * 5))
done

if [ "$published" = true ]; then
  drop_preview_apks "$@"
  exit 0
fi

echo "Could not publish $* to $tag" >&2
exit 1
