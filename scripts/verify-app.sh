#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/verify-app.sh [--require-developer-id] [--require-notarized] APP_PATH

Validates the Mac Cleaner bundle, universal executable, signature, and safety
properties. --require-notarized also performs stapler and Gatekeeper checks.
EOF
}

fail() {
    echo "error: $*" >&2
    exit 1
}

require_developer_id=false
require_notarized=false
app_path=""

while (($# > 0)); do
    case "$1" in
        --require-developer-id)
            require_developer_id=true
            ;;
        --require-notarized)
            require_developer_id=true
            require_notarized=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -* )
            fail "unknown option: $1"
            ;;
        *)
            [[ -z "$app_path" ]] || fail "only one app path may be supplied"
            app_path="$1"
            ;;
    esac
    shift
done

[[ -n "$app_path" ]] || {
    usage >&2
    exit 2
}

[[ -d "$app_path" ]] || fail "app bundle not found: $app_path"

plist="$app_path/Contents/Info.plist"
executable="$app_path/Contents/MacOS/MacCleaner"
icon="$app_path/Contents/Resources/AppIcon.icns"

[[ -f "$plist" ]] || fail "missing Info.plist"
[[ -x "$executable" ]] || fail "missing executable: $executable"
[[ -f "$icon" ]] || fail "missing app icon"

/usr/bin/plutil -lint "$plist" >/dev/null

bundle_identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$plist")"
[[ "$bundle_identifier" == "com.cinnabarhorse.MacCleaner" ]] || \
    fail "unexpected bundle identifier: $bundle_identifier"

minimum_system="$(/usr/bin/plutil -extract LSMinimumSystemVersion raw -o - "$plist")"
[[ "$minimum_system" == "14.0" ]] || fail "unexpected minimum macOS version: $minimum_system"

/usr/bin/lipo "$executable" -verify_arch arm64 x86_64 || \
    fail "executable is not universal arm64/x86_64"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"

entitlements_file="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/mac-cleaner-entitlements.XXXXXX")"
trap '/bin/rm -f "$entitlements_file"' EXIT
if ! /usr/bin/codesign --display --entitlements - "$app_path" >"$entitlements_file" 2>/dev/null; then
    fail "could not inspect bundle entitlements"
fi
if /usr/bin/grep -q "com.apple.security.app-sandbox" "$entitlements_file"; then
    fail "App Sandbox entitlement must not be enabled"
fi

signing_details="$(/usr/bin/codesign --display --verbose=4 "$app_path" 2>&1)"

if [[ "$require_developer_id" == true ]]; then
    /usr/bin/grep -q "Authority=Developer ID Application:" <<<"$signing_details" || \
        fail "bundle is not signed with a Developer ID Application certificate"
    /usr/bin/grep -Eq "flags=.*runtime" <<<"$signing_details" || \
        fail "hardened runtime is not enabled"
    /usr/bin/grep -q "Timestamp=" <<<"$signing_details" || \
        fail "signature does not contain a secure timestamp"
fi

if [[ "$require_notarized" == true ]]; then
    /usr/bin/xcrun stapler validate "$app_path"
    /usr/sbin/spctl --assess --type execute --verbose=4 "$app_path"
fi

architectures="$(/usr/bin/lipo -archs "$executable")"
version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$plist")"
build_number="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$plist")"
echo "Verified $app_path"
echo "  Bundle: $bundle_identifier"
echo "  Version: $version ($build_number)"
echo "  Architectures: $architectures"
