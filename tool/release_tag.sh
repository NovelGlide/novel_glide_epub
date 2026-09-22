#!/usr/bin/env bash
# release_tag.sh — plan or create the git tag for pubspec.yaml's version when
# it has none yet.
#
# The tag is `v<version>` — the NovelGlide app pins this package by that ref
# (`ref: v0.1.0` in its pubspec.yaml), so the name is part of the consumer
# contract, not a style choice.
#
# WHY THE TAG IS CREATED BY A WORKFLOW: this repo's commits land on `main`
# directly, and a tag cut by hand is the step that gets forgotten — the app
# then keeps resolving the previous release with nothing to say it is stale.
# The release-tag workflow runs this on every push to `main`; a push that
# bumps `version:` produces the tag, and any other push is a no-op.
#
# It only ever ADDS a tag, never moves one — a moved tag would let one version
# number mean two different trees, and every consumer pinned to it would
# silently change parser. A pubspec.yaml at or behind the newest existing tag
# is refused rather than guessed at: that means a reverted bump, not a new
# release.
#
# Usage: tool/release_tag.sh [--create]
#   (default)  print the plan, change nothing
#   --create   create the annotated tag at HEAD — does NOT push
# Writes `tag=<tag or empty>` to $GITHUB_OUTPUT when that is set.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

create=false
[ "${1:-}" = "--create" ] && create=true

# $1 <= $2, comparing dotted x.y.z numerically field by field.
ver_le() {
  [ "$1" = "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" ]
}

emit() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "tag=$1" >>"$GITHUB_OUTPUT"
  fi
}

version=$(grep -m1 '^version:' pubspec.yaml | sed 's/^version:[[:space:]]*//')

# Only plain x.y.z. A pre-release would have to answer "does 1.0.0-rc.2
# outrank 1.0.0?" and this package has never had one — refusing is honest,
# guessing an order silently is not.
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "✘ pubspec.yaml version \"$version\" is not x.y.z — refusing to guess how it orders" >&2
  emit ""
  exit 1
fi

tag="v${version}"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "✔ $version — already tagged"
  emit ""
  exit 0
fi

newest=$(git tag -l 'v*' | sed 's/^v//' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)

if [ -n "$newest" ] && ver_le "$version" "$newest"; then
  echo "✘ pubspec.yaml is at $version, but v$newest is already tagged" >&2
  echo "  → bump pubspec.yaml's version above the newest tag" >&2
  emit ""
  exit 1
fi

echo "→ $version — ${newest:+newer than $newest, }will tag $tag"

if [ "$create" = true ]; then
  if ! git tag -a "$tag" -m "novel_glide_epub $version

Created automatically by the release-tag workflow from pubspec.yaml."; then
    echo "✘ could not create $tag" >&2
    emit ""
    exit 1
  fi
  echo "  tagged $tag at $(git rev-parse --short HEAD)"
fi

emit "$tag"
