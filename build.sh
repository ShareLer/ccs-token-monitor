#!/usr/bin/env bash
# Build ccMonitor.app into ./build.
set -euo pipefail
cd "$(dirname "$0")"

SCHEME="ccMonitor"
PROJECT="ccMonitor.xcodeproj"
CONFIG="${1:-Release}"

case "$CONFIG" in
  Debug|Release) ;;
  *)
    echo "error: configuration must be Debug or Release" >&2
    exit 1
    ;;
esac

command -v xcodegen >/dev/null 2>&1 || {
  echo "error: xcodegen is required because project.yml is the project source" >&2
  exit 1
}

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building $SCHEME ($CONFIG)"
XCODEBUILD_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIG"
  -destination 'platform=macOS'
  -derivedDataPath ./build
)
if [[ "$CONFIG" == "Release" ]]; then
  xcodebuild "${XCODEBUILD_ARGS[@]}" \
    "CODE_SIGN_STYLE=Manual" \
    "CODE_SIGN_IDENTITY=-" \
    "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO" \
    "DEVELOPMENT_TEAM=" \
    build
else
  xcodebuild "${XCODEBUILD_ARGS[@]}" build
fi

APP="./build/Build/Products/$CONFIG/ccMonitor.app"
[[ -d "$APP" ]] || {
  echo "error: app not found: $APP" >&2
  exit 1
}

if [[ "$CONFIG" == "Release" ]]; then
  echo "==> Applying deterministic ad-hoc signature"
  codesign --force --deep --sign - --options runtime "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"

  SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP" 2>&1)"
  grep -q 'Signature=adhoc' <<<"$SIGNATURE_DETAILS" || {
    echo "error: Release app is not ad-hoc signed" >&2
    exit 1
  }
  grep -q 'TeamIdentifier=not set' <<<"$SIGNATURE_DETAILS" || {
    echo "error: Release app unexpectedly has a TeamIdentifier" >&2
    exit 1
  }

  ENTITLEMENTS_FILE="$(mktemp "${TMPDIR:-/tmp}/ccmonitor-entitlements.XXXXXX")"
  if ! codesign -d --entitlements :- "$APP" >"$ENTITLEMENTS_FILE" 2>/dev/null; then
    rm -f "$ENTITLEMENTS_FILE"
    echo "error: could not read Release entitlements" >&2
    exit 1
  fi
  GET_TASK_ALLOW="false"
  if [[ -s "$ENTITLEMENTS_FILE" ]]; then
    plutil -lint "$ENTITLEMENTS_FILE" >/dev/null || {
      rm -f "$ENTITLEMENTS_FILE"
      echo "error: Release entitlements are not a valid plist" >&2
      exit 1
    }
    GET_TASK_ALLOW="$(plutil -extract 'com\.apple\.security\.get-task-allow' raw -o - "$ENTITLEMENTS_FILE" 2>/dev/null || true)"
  fi
  rm -f "$ENTITLEMENTS_FILE"
  if [[ "$GET_TASK_ALLOW" == "true" ]]; then
    echo "error: Release app contains get-task-allow=true" >&2
    exit 1
  fi
fi

echo "==> Complete: $APP"
echo "Run: open \"$APP\""
