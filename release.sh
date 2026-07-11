#!/usr/bin/env bash
# Prepare and publish the ad-hoc community build of ccMonitor.
set -euo pipefail

cd "$(dirname "$0")"

REPO="ShareLer/ccs-token-monitor"
APP_NAME="ccMonitor"
CONFIG="Release"
DIST_DIR="$(pwd)/dist"
BUILD_DIR="$(pwd)/build"
WORK_DIR=""
SMOKE_PID=""

usage() {
  cat <<'EOF'
Usage:
  ./release.sh prepare v1.2.3
  ./release.sh publish v1.2.3 --notes-file dist/RELEASE_NOTES-v1.2.3.md [--prerelease]
  ./release.sh publish v1.2.3 --notes "Version changes" [--prerelease]

prepare:
  Requires a completely clean worktree. Builds and explicitly ad-hoc signs the
  Release app, verifies its entitlements, packages it, verifies the final zip,
  performs a local launch smoke test, and writes a commit/hash manifest.

publish:
  Revalidates the prepared bytes and manifest, requires HEAD to match the
  pushed origin branch, then creates a draft GitHub Release. The release is
  made public only after every uploaded asset digest matches locally.

This community release is not Developer ID signed or notarized. Users must
remove quarantine after verifying that the download came from this project.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$SMOKE_PID" ]]; then
    kill "$SMOKE_PID" 2>/dev/null || true
    wait "$SMOKE_PID" 2>/dev/null || true
    SMOKE_PID=""
  fi
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 not found"
}

require_clean_worktree() {
  [[ -z "$(git status --porcelain)" ]] || die "worktree must be completely clean, including untracked files"
}

is_release_repo_url() {
  case "$1" in
    "git@github.com:$REPO.git"|"ssh://git@github.com/$REPO.git"|"https://github.com/$REPO"|"https://github.com/$REPO.git") return 0 ;;
    *) return 1 ;;
  esac
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

manifest_value() {
  plutil -extract "$1" raw -o - "$2" 2>/dev/null || die "invalid release manifest field: $1"
}

verify_app() {
  local app_path="$1"
  local signature_details entitlements_file get_task_allow

  codesign --verify --deep --strict --verbose=2 "$app_path"
  signature_details="$(codesign -dv --verbose=4 "$app_path" 2>&1)"
  grep -q 'Signature=adhoc' <<<"$signature_details" || die "app is not ad-hoc signed: $app_path"
  grep -q 'TeamIdentifier=not set' <<<"$signature_details" || die "app unexpectedly has a TeamIdentifier: $app_path"

  entitlements_file="$(mktemp "${TMPDIR:-/tmp}/ccmonitor-entitlements.XXXXXX")"
  if ! codesign -d --entitlements :- "$app_path" >"$entitlements_file" 2>/dev/null; then
    rm -f "$entitlements_file"
    die "could not read app entitlements: $app_path"
  fi
  get_task_allow="false"
  if [[ -s "$entitlements_file" ]]; then
    plutil -lint "$entitlements_file" >/dev/null || {
      rm -f "$entitlements_file"
      die "app entitlements are not a valid plist: $app_path"
    }
    get_task_allow="$(plutil -extract 'com\.apple\.security\.get-task-allow' raw -o - "$entitlements_file" 2>/dev/null || true)"
  fi
  rm -f "$entitlements_file"
  if [[ "$get_task_allow" == "true" ]]; then
    die "Release app contains get-task-allow=true"
  fi
}

extract_archive() {
  local zip_path="$1"

  cleanup
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ccmonitor-release.XXXXXX")"
  ditto -x -k "$zip_path" "$WORK_DIR"
  EXTRACTED_APP="$WORK_DIR/$APP_NAME.app"
  [[ -d "$EXTRACTED_APP" ]] || die "archive does not contain $APP_NAME.app at its root"
}

smoke_test_app() {
  local app_path="$1"
  local executable="$app_path/Contents/MacOS/$APP_NAME"
  local pid

  [[ -x "$executable" ]] || die "app executable is missing: $executable"
  mkdir -p "$WORK_DIR/home"
  HOME="$WORK_DIR/home" CFFIXED_USER_HOME="$WORK_DIR/home" \
    "$executable" >"$WORK_DIR/smoke-test.log" 2>&1 &
  SMOKE_PID=$!
  pid="$SMOKE_PID"
  sleep 3

  if ! kill -0 "$pid" 2>/dev/null; then
    wait "$pid" || true
    sed -n '1,80p' "$WORK_DIR/smoke-test.log" >&2
    die "app exited during local launch smoke test"
  fi

  kill "$pid" 2>/dev/null || true
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
  SMOKE_PID=""
}

verify_checksum_file() {
  local zip_path="$1"
  local sha_path="$2"
  local zip_name expected_hash expected_line actual_line

  zip_name="$(basename "$zip_path")"
  expected_hash="$(sha256_file "$zip_path")"
  expected_line="$expected_hash  $zip_name"
  actual_line="$(sed -n '1p' "$sha_path")"
  [[ "$actual_line" == "$expected_line" ]] || die "checksum file must contain only the zip filename and its current hash"
  [[ "$(wc -l < "$sha_path" | tr -d ' ')" == "1" ]] || die "checksum file must contain exactly one line"

  (
    cd "$DIST_DIR"
    shasum -a 256 -c "$(basename "$sha_path")"
  )
}

create_manifest() {
  local manifest_path="$1"
  local tag="$2"
  local commit="$3"
  local zip_name="$4"
  local zip_hash="$5"
  local bundle_version="$6"
  local bundle_build="$7"

  rm -f "$manifest_path"
  plutil -create xml1 "$manifest_path"
  plutil -insert schemaVersion -integer 1 "$manifest_path"
  plutil -insert appName -string "$APP_NAME" "$manifest_path"
  plutil -insert tag -string "$tag" "$manifest_path"
  plutil -insert commit -string "$commit" "$manifest_path"
  plutil -insert zipName -string "$zip_name" "$manifest_path"
  plutil -insert sha256 -string "$zip_hash" "$manifest_path"
  plutil -insert bundleVersion -string "$bundle_version" "$manifest_path"
  plutil -insert bundleBuild -string "$bundle_build" "$manifest_path"
  plutil -insert launchValidated -bool YES "$manifest_path"
  plutil -insert createdAt -string "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$manifest_path"
}

prepare_release() {
  local tag="$1"
  local app_path zip_name zip_path sha_path manifest_path
  local bundle_version bundle_build commit zip_hash

  require_command git
  require_command xcodebuild
  require_command xcodegen
  require_command codesign
  require_command ditto
  require_command unzip
  require_command shasum
  require_command plutil
  require_clean_worktree

  commit="$(git rev-parse HEAD)"
  echo "==> Building $APP_NAME ($CONFIG) from $commit"
  ./build.sh "$CONFIG"

  app_path="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"
  [[ -d "$app_path" ]] || die "app not found: $app_path"
  verify_app "$app_path"

  bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
  bundle_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")"
  [[ "v$bundle_version" == "$tag" ]] || die "bundle version $bundle_version does not match tag $tag"
  [[ -n "$bundle_build" ]] || die "bundle build number is empty"

  mkdir -p "$DIST_DIR"
  zip_name="$APP_NAME-$tag-macOS.zip"
  zip_path="$DIST_DIR/$zip_name"
  sha_path="$zip_path.sha256"
  manifest_path="$DIST_DIR/$APP_NAME-$tag-manifest.plist"
  rm -f "$zip_path" "$sha_path" "$manifest_path"

  echo "==> Packaging $zip_name"
  ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
  unzip -tq "$zip_path"
  (
    cd "$DIST_DIR"
    shasum -a 256 "$zip_name" > "$zip_name.sha256"
  )
  verify_checksum_file "$zip_path" "$sha_path"

  echo "==> Verifying the app extracted from the final zip"
  extract_archive "$zip_path"
  verify_app "$EXTRACTED_APP"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXTRACTED_APP/Contents/Info.plist")" == "$bundle_version" ]] || die "archive bundle version changed"
  smoke_test_app "$EXTRACTED_APP"

  zip_hash="$(sha256_file "$zip_path")"
  create_manifest "$manifest_path" "$tag" "$commit" "$zip_name" "$zip_hash" "$bundle_version" "$bundle_build"
  require_clean_worktree

  echo "==> Prepared and locally validated $tag"
  echo "Assets:"
  echo "  $zip_path"
  echo "  $sha_path"
  echo "  $manifest_path"
  echo "Next: ./release.sh publish $tag --notes-file dist/RELEASE_NOTES-$tag.md"
}

verify_prepared_release() {
  local tag="$1"
  local zip_name="$APP_NAME-$tag-macOS.zip"
  local zip_path="$DIST_DIR/$zip_name"
  local sha_path="$zip_path.sha256"
  local manifest_path="$DIST_DIR/$APP_NAME-$tag-manifest.plist"
  local head_commit bundle_version bundle_build

  [[ -f "$zip_path" ]] || die "prepared zip not found: $zip_path"
  [[ -f "$sha_path" ]] || die "prepared checksum not found: $sha_path"
  [[ -f "$manifest_path" ]] || die "release manifest not found: $manifest_path"
  plutil -lint "$manifest_path" >/dev/null || die "release manifest is invalid"

  head_commit="$(git rev-parse HEAD)"
  [[ "$(manifest_value schemaVersion "$manifest_path")" == "1" ]] || die "unsupported release manifest schema"
  [[ "$(manifest_value appName "$manifest_path")" == "$APP_NAME" ]] || die "manifest app name mismatch"
  [[ "$(manifest_value tag "$manifest_path")" == "$tag" ]] || die "manifest tag mismatch"
  [[ "$(manifest_value commit "$manifest_path")" == "$head_commit" ]] || die "manifest commit does not match HEAD"
  [[ "$(manifest_value zipName "$manifest_path")" == "$zip_name" ]] || die "manifest zip name mismatch"
  [[ "$(manifest_value sha256 "$manifest_path")" == "$(sha256_file "$zip_path")" ]] || die "prepared zip hash changed"
  [[ "$(manifest_value launchValidated "$manifest_path")" == "true" ]] || die "prepared app was not locally launch-validated"

  unzip -tq "$zip_path"
  verify_checksum_file "$zip_path" "$sha_path"
  extract_archive "$zip_path"
  verify_app "$EXTRACTED_APP"
  bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXTRACTED_APP/Contents/Info.plist")"
  bundle_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXTRACTED_APP/Contents/Info.plist")"
  [[ "v$bundle_version" == "$tag" ]] || die "archive bundle version does not match tag"
  [[ "$(manifest_value bundleVersion "$manifest_path")" == "$bundle_version" ]] || die "manifest bundle version mismatch"
  [[ "$(manifest_value bundleBuild "$manifest_path")" == "$bundle_build" ]] || die "manifest bundle build mismatch"

  RELEASE_ZIP_PATH="$zip_path"
  RELEASE_SHA_PATH="$sha_path"
  RELEASE_MANIFEST_PATH="$manifest_path"
}

remote_asset_digest() {
  local tag="$1"
  local asset_name="$2"
  gh api "repos/$REPO/releases/tags/$tag" \
    --jq ".assets[] | select(.name == \"$asset_name\") | .digest"
}

verify_uploaded_asset() {
  local tag="$1"
  local asset_path="$2"
  local asset_name local_digest remote_digest attempt

  asset_name="$(basename "$asset_path")"
  local_digest="sha256:$(sha256_file "$asset_path")"
  remote_digest=""
  for attempt in 1 2 3 4 5; do
    if remote_digest="$(remote_asset_digest "$tag" "$asset_name" 2>/dev/null)"; then
      [[ "$remote_digest" == "$local_digest" ]] && break
    fi
    sleep 2
  done
  [[ "$remote_digest" == "$local_digest" ]] || die "uploaded digest mismatch for $asset_name (release remains a draft)"
}

publish_release() {
  local tag="$1"
  local notes="$2"
  local prerelease="$3"
  local branch head_commit origin_url push_url remote_branch_line remote_commit
  local local_tag_exists remote_tag_exists remote_tag remote_check_ref existing_release release_draft
  local expected_asset_names remote_asset_names
  local title="$APP_NAME $tag"
  local -a assets create_args edit_args

  require_command git
  require_command gh
  require_command ditto
  require_command unzip
  require_command shasum
  require_command codesign
  require_command plutil
  require_clean_worktree
  [[ -n "$notes" ]] || die "publish requires --notes or --notes-file containing version changes"
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run: gh auth login"

  verify_prepared_release "$tag"

  head_commit="$(git rev-parse HEAD)"
  branch="$(git branch --show-current)"
  [[ -n "$branch" ]] || die "detached HEAD is not supported for releases"
  origin_url="$(git remote get-url origin)"
  push_url="$(git remote get-url --push origin)"
  is_release_repo_url "$origin_url" || die "origin fetch URL must be the release repository: https://github.com/$REPO"
  is_release_repo_url "$push_url" || die "origin push URL must be the release repository: https://github.com/$REPO"
  remote_branch_line="$(git ls-remote origin "refs/heads/$branch")"
  [[ -n "$remote_branch_line" ]] || die "origin/$branch does not exist"
  remote_commit="${remote_branch_line%%[[:space:]]*}"
  [[ "$remote_commit" == "$head_commit" ]] || die "HEAD must exactly match pushed origin/$branch"

  local_tag_exists=0
  if git show-ref --verify --quiet "refs/tags/$tag"; then
    local_tag_exists=1
    [[ "$(git rev-list -n 1 "$tag")" == "$head_commit" ]] || die "local tag $tag points to a different commit"
  fi
  remote_tag="$(git ls-remote --tags --refs origin "refs/tags/$tag")"
  remote_tag_exists=0
  if [[ -n "$remote_tag" ]]; then
    remote_tag_exists=1
    remote_check_ref="refs/ccmonitor-release-check/$tag"
    git update-ref -d "$remote_check_ref" 2>/dev/null || true
    git fetch --quiet --force origin "refs/tags/$tag:$remote_check_ref"
    [[ "$(git rev-list -n 1 "$remote_check_ref")" == "$head_commit" ]] || {
      git update-ref -d "$remote_check_ref" 2>/dev/null || true
      die "remote tag $tag points to a different commit"
    }
    git update-ref -d "$remote_check_ref"
    if [[ "$local_tag_exists" -eq 0 ]]; then
      git fetch --quiet origin "refs/tags/$tag:refs/tags/$tag"
      local_tag_exists=1
    fi
  fi

  existing_release="$(gh api --paginate "repos/$REPO/releases?per_page=100" \
    --jq ".[] | select(.tag_name == \"$tag\") | .draft")"
  if [[ -n "$existing_release" ]]; then
    release_draft="$existing_release"
    [[ "$release_draft" == "true" ]] || die "GitHub Release is already public: $tag"
    echo "==> Resuming existing draft GitHub Release"
  fi

  assets=("$RELEASE_MANIFEST_PATH" "$RELEASE_SHA_PATH" "$RELEASE_ZIP_PATH")

  if [[ "$local_tag_exists" -eq 0 ]]; then
    echo "==> Creating annotated tag $tag after local validation"
    git tag -a "$tag" -m "$title"
    local_tag_exists=1
  fi
  if [[ "$remote_tag_exists" -eq 0 ]]; then
    echo "==> Pushing validated tag $tag"
    git push origin "refs/tags/$tag"
    remote_tag_exists=1
  fi

  if [[ -z "$existing_release" ]]; then
    create_args=(
      release create "$tag"
      "${assets[@]}"
      --repo "$REPO"
      --verify-tag
      --draft
      --title "$title"
      --notes "$notes"
    )
    if [[ "$prerelease" -eq 1 ]]; then
      create_args+=(--prerelease)
    fi
    echo "==> Creating draft GitHub Release"
    gh "${create_args[@]}"
  else
    [[ "$(remote_asset_digest "$tag" "$(basename "$RELEASE_MANIFEST_PATH")")" == \
      "sha256:$(sha256_file "$RELEASE_MANIFEST_PATH")" ]] || \
      die "existing draft does not contain this prepared manifest; inspect or delete it manually"
    gh release upload "$tag" "${assets[@]}" --repo "$REPO" --clobber
  fi

  echo "==> Verifying uploaded asset digests"
  verify_uploaded_asset "$tag" "$RELEASE_ZIP_PATH"
  verify_uploaded_asset "$tag" "$RELEASE_SHA_PATH"
  verify_uploaded_asset "$tag" "$RELEASE_MANIFEST_PATH"
  expected_asset_names="$(printf '%s\n' \
    "$(basename "$RELEASE_ZIP_PATH")" \
    "$(basename "$RELEASE_SHA_PATH")" \
    "$(basename "$RELEASE_MANIFEST_PATH")" | LC_ALL=C sort)"
  remote_asset_names="$(gh api "repos/$REPO/releases/tags/$tag" --jq '.assets[].name' | LC_ALL=C sort)"
  [[ "$remote_asset_names" == "$expected_asset_names" ]] || die "draft Release contains unexpected or missing assets"

  edit_args=(
    release edit "$tag"
    --repo "$REPO"
    --draft=false
    --title "$title"
    --notes "$notes"
  )
  if [[ "$prerelease" -eq 1 ]]; then
    edit_args+=(--prerelease)
  else
    edit_args+=(--prerelease=false)
  fi
  echo "==> Publishing verified GitHub Release"
  gh "${edit_args[@]}"
  [[ "$(gh release view "$tag" --repo "$REPO" --json isDraft --jq '.isDraft')" == "false" ]] || die "release is still a draft"
  echo "==> Release complete: https://github.com/$REPO/releases/tag/$tag"
}

[[ $# -gt 0 ]] || { usage; exit 1; }
COMMAND="$1"
shift

case "$COMMAND" in
  -h|--help)
    usage
    exit 0
    ;;
  prepare)
    [[ $# -eq 1 ]] || { usage; die "prepare requires exactly one tag"; }
    TAG="$1"
    [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "tag must look like v1.2.3"
    prepare_release "$TAG"
    ;;
  publish)
    [[ $# -gt 0 ]] || { usage; die "publish requires a tag"; }
    TAG="$1"
    shift
    NOTES=""
    NOTES_FILE=""
    PRERELEASE=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --notes)
          [[ $# -ge 2 ]] || die "--notes requires a value"
          [[ -z "$NOTES_FILE" ]] || die "use only one of --notes or --notes-file"
          NOTES="$2"
          shift 2
          ;;
        --notes-file)
          [[ $# -ge 2 ]] || die "--notes-file requires a value"
          [[ -z "$NOTES" ]] || die "use only one of --notes or --notes-file"
          NOTES_FILE="$2"
          shift 2
          ;;
        --prerelease)
          PRERELEASE=1
          shift
          ;;
        *)
          die "unknown publish option: $1"
          ;;
      esac
    done
    [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "tag must look like v1.2.3"
    if [[ -n "$NOTES_FILE" ]]; then
      [[ -f "$NOTES_FILE" ]] || die "notes file not found: $NOTES_FILE"
      NOTES="$(<"$NOTES_FILE")"
    fi
    publish_release "$TAG" "$NOTES" "$PRERELEASE"
    ;;
  *)
    usage
    die "unknown command: $COMMAND"
    ;;
esac
