#!/usr/bin/env bash
# Build the Docusaurus site and publish it to the gh-pages branch.
# Needed while the deploy workflow cannot be pushed (token without `workflow` scope).
set -euo pipefail
cd "$(dirname "$0")"
REPO="${REPO:-0x0ar/taurus}"
rev="$(git rev-parse --short HEAD)"
npm ci --no-audit --no-fund
npm run build
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
cp -a build/. "$dir/"
touch "$dir/.nojekyll"
cd "$dir"
git init -q -b gh-pages
git add -A
git -c user.name="$(git -C "$OLDPWD" config user.name)" -c user.email="$(git -C "$OLDPWD" config user.email)" \
    commit -q -m "Deploy site (built from main $rev)"
git -c credential.helper= -c credential.helper='!gh auth git-credential' \
    push -f "https://github.com/$REPO.git" gh-pages
echo "Published: https://${REPO%%/*}.github.io/${REPO##*/}/"
