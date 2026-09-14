#!/bin/bash
# Builds, zips and publishes a GitHub Release in one step.
# usage: tools/publish_release.sh <version>    e.g. tools/publish_release.sh 1.0.1
# Needs the GitHub CLI, signed in: brew install gh && gh auth login
set -e

VERSION="${1:?usage: tools/publish_release.sh <version, e.g. 1.0.1>}"
TAG="v$VERSION"
cd "$(dirname "$0")/.."

gh auth status >/dev/null 2>&1 || { echo "Not signed in to GitHub: run gh auth login"; exit 1; }

# The release must match committed, pushed code, or the download and the
# source on GitHub would disagree.
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "Uncommitted changes - commit them first."
    exit 1
fi
git fetch --quiet origin main
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    echo "Local main differs from origin/main - push (or pull) first."
    exit 1
fi
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Release $TAG already exists."
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    if [ "$(git rev-list -n1 "$TAG")" != "$(git rev-parse HEAD)" ]; then
        echo "Tag $TAG exists but points at a different commit than HEAD."
        exit 1
    fi
else
    git tag -a "$TAG" -m "Pokémon Champions Analyzer $VERSION"
    git push --quiet origin "$TAG"
fi

tools/make_release.sh "$VERSION"

ZIP="dist/PokemonChampionsAnalyzer-$VERSION.zip"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
NOTES=$(mktemp)
cat > "$NOTES" <<EOF
Download **PokemonChampionsAnalyzer-$VERSION.zip** below (not the "Source code" files), unzip it, and move **Pokémon Champions Analyzer.app** to Applications.

The app isn't signed with an Apple Developer ID, so macOS blocks it the first time you open it. Approve it once in **System Settings → Privacy & Security → Open Anyway**. The [README](https://github.com/sheeenie/pokemon-champions-anyalzer#download) has the details.

- macOS 13 or later, on Apple Silicon or Intel
- The sprites and Pokédex data are built into the app; nothing else to install

SHA-256: \`$SHA\`
EOF

gh release create "$TAG" "$ZIP" \
    --title "Pokémon Champions Analyzer $VERSION" \
    --notes-file "$NOTES" \
    --verify-tag
rm -f "$NOTES"

echo
gh release view "$TAG" --json url --jq .url
