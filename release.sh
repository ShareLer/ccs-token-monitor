#!/usr/bin/env bash
# Build, package, and publish ccMonitor to GitHub Releases.
set -euo pipefail

cd "$(dirname "$0")"

REPO="ShareLer/ccs-token-monitor"
APP_NAME="ccMonitor"
SCHEME="ccMonitor"
PROJECT="ccMonitor.xcodeproj"
CONFIG="Release"
DIST_DIR="./dist"
DRY_RUN=0
PRERELEASE=0
NOTES=""

usage() {
  cat <<'EOF'
Usage:
  ./release.sh v1.0.0 [--notes "Release notes"] [--prerelease] [--dry-run]

Creates a GitHub Release for the given tag:
  1. Verifies the working tree has no tracked changes.
  2. Builds the Release app.
  3. Packages ccMonitor.app as dist/ccMonitor-<tag>-macOS.zip.
  4. Writes a SHA-256 checksum file.
  5. Creates and pushes the git tag if needed.
  6. Uploads assets with gh release create.

This script does not Developer ID sign or notarize the app.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

TAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --notes)
      [[ $# -ge 2 ]] || die "--notes requires a value"
      NOTES="$2"
      shift 2
      ;;
    --prerelease)
      PRERELEASE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      [[ -z "$TAG" ]] || die "only one tag is allowed"
      TAG="$1"
      shift
      ;;
  esac
done

[[ -n "$TAG" ]] || { usage; die "missing release tag"; }
[[ "$TAG" =~ ^v[0-9]+(\.[0-9]+){2}([-+][0-9A-Za-z.-]+)?$ ]] || die "tag must look like v1.2.3"

command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found"
command -v ditto >/dev/null 2>&1 || die "ditto not found"
command -v shasum >/dev/null 2>&1 || die "shasum not found"
command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) not found"

if ! gh auth status >/dev/null 2>&1; then
  die "gh is not authenticated. Run: gh auth login"
fi

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  die "tracked working tree changes exist; commit or stash them before releasing"
fi

CURRENT_BRANCH="$(git branch --show-current)"
[[ -n "$CURRENT_BRANCH" ]] || die "detached HEAD is not supported for releases"

echo "==> Fetching tags"
git fetch --tags origin

TAG_EXISTS=0
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  TAG_EXISTS=1
  TAG_COMMIT="$(git rev-list -n 1 "$TAG")"
  HEAD_COMMIT="$(git rev-parse HEAD)"
  [[ "$TAG_COMMIT" == "$HEAD_COMMIT" ]] || die "tag $TAG already exists on a different commit"
fi

echo "==> Building $APP_NAME ($CONFIG)"
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -derivedDataPath ./build \
  build

APP_PATH="./build/Build/Products/$CONFIG/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || die "app not found: $APP_PATH"

mkdir -p "$DIST_DIR"
ZIP_PATH="$DIST_DIR/$APP_NAME-$TAG-macOS.zip"
SHA_PATH="$ZIP_PATH.sha256"
rm -f "$ZIP_PATH" "$SHA_PATH"

echo "==> Packaging $ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$SHA_PATH"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "==> Dry run complete"
  echo "Tag: $TAG"
  echo "Assets:"
  echo "  $ZIP_PATH"
  echo "  $SHA_PATH"
  exit 0
fi

if [[ "$TAG_EXISTS" -eq 0 ]]; then
  echo "==> Creating tag $TAG"
  git tag "$TAG"
fi

echo "==> Pushing tag $TAG"
git push origin "$TAG"

TITLE="$APP_NAME $TAG"
if [[ -z "$NOTES" ]]; then
  NOTES="Release $TAG"
fi

GH_ARGS=(
  release create "$TAG"
  "$ZIP_PATH"
  "$SHA_PATH"
  --repo "$REPO"
  --title "$TITLE"
  --notes "$NOTES"
)
if [[ "$PRERELEASE" -eq 1 ]]; then
  GH_ARGS+=(--prerelease)
fi

echo "==> Creating GitHub Release"
gh "${GH_ARGS[@]}"

echo "==> Release complete: https://github.com/$REPO/releases/tag/$TAG"
