#!/usr/bin/env bash
# Regenerates altstore/apps.json from the GitLab release that
# github-release-sync just created, then commits it back to main with
# ci.skip. Runs inside the github-release-sync job (glab + deploy key
# already configured by before_script).
set -euo pipefail

RELEASE_TAG="${RELEASE_TAG:-}"
PROJECT_DIR="${CI_PROJECT_DIR:-$PWD}"
cd "$PROJECT_DIR"

if [ -z "$RELEASE_TAG" ]; then
  RELEASE_TAG=$(glab release list -R "$CI_PROJECT_PATH" --output json 2>/dev/null | jq -r '.[0].tag_name // empty' || true)
fi
if [ -z "$RELEASE_TAG" ]; then
  echo "No release tag found, skipping AltStore source update"
  exit 0
fi

# Find the iOS ipa asset in the package registry for this release.
PKG_BASE="packages/generic/release-assets/$RELEASE_TAG"
IPA_NAME=$(glab api "projects/$CI_PROJECT_ID/$PKG_BASE" 2>/dev/null | jq -r '.package_links[]? | select(.name | test("ipa$")) | .name' 2>/dev/null | head -n1 || true)
if [ -z "$IPA_NAME" ]; then
  IPA_NAME=$(glab api "projects/$CI_PROJECT_ID/packages?package_name=release-assets&package_version=$RELEASE_TAG" 2>/dev/null | jq -r '.[0].package_files[]? | select(.file_name | test("ipa$")) | .file_name' | head -n1 || true)
fi
if [ -z "$IPA_NAME" ]; then
  echo "No ipa asset found for $RELEASE_TAG, skipping AltStore source update"
  exit 0
fi

IPA_URL="https://gitlab.com/$CI_PROJECT_PATH/-/package_files/$(glab api "projects/$CI_PROJECT_ID/packages?package_name=release-assets&package_version=$RELEASE_TAG" | jq -r ".[0].package_files[] | select(.file_name == \"$IPA_NAME\") | .id" | head -n1)/download"
IPA_SIZE=$(glab api "projects/$CI_PROJECT_ID/packages?package_name=release-assets&package_version=$RELEASE_TAG" | jq -r ".[0].package_files[] | select(.file_name == \"$IPA_NAME\") | .size" | head -n1)
VERSION="${RELEASE_TAG#v}"
ICON_URL="https://$CI_PROJECT_NAMESPACE.gitlab.io/$CI_PROJECT_NAME/icon-1024.png"
TODAY=$(date +%Y-%m-%d)

mkdir -p altstore
cat > altstore/apps.json <<EOF
{
  "name": "toaster",
  "identifier": "com.toaster.toaster.source",
  "iconURL": "$ICON_URL",
  "apps": [
    {
      "name": "toaster",
      "bundleIdentifier": "com.toaster.toaster",
      "developerName": "HttpAnimations",
      "iconURL": "$ICON_URL",
      "tintedIconURL": "$ICON_URL",
      "versions": [
        {
          "version": "$VERSION",
          "date": "${TODAY}T00:00:00Z",
          "downloadURL": "$IPA_URL",
          "size": ${IPA_SIZE:-0},
          "minOSVersion": "14.0"
        }
      ],
      "news": [
        {
          "title": "$RELEASE_TAG",
          "identifier": "release-$RELEASE_TAG",
          "caption": "Release $RELEASE_TAG",
          "date": "${TODAY}T00:00:00Z",
          "notify": true
        }
      ]
    }
  ]
}
EOF

cp assets/icon-1024.png public/icon-1024.png 2>/dev/null || true

git add altstore/apps.json public/icon-1024.png 2>/dev/null || git add altstore/apps.json
if git diff --cached --quiet; then
  echo "AltStore source unchanged"
  exit 0
fi
git -c user.name="GitLab CI" -c user.email="ci@gitlab.com" \
  commit -m "chore: 更新 AltStore 源"
git remote add gitlab-ssh "git@gitlab.com:${CI_PROJECT_PATH}.git" 2>/dev/null || true
git push -o ci.skip gitlab-ssh HEAD:main
echo "AltStore source updated for $RELEASE_TAG"
