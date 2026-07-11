#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

: "${MAC_CLEANER_VERSION:?Set MAC_CLEANER_VERSION (for example, 1.0.0)}"
: "${MAC_CLEANER_BUILD_NUMBER:?Set MAC_CLEANER_BUILD_NUMBER to a positive integer}"
: "${MAC_CLEANER_SIGNING_IDENTITY:?Set MAC_CLEANER_SIGNING_IDENTITY to a Developer ID Application identity}"

[[ "$MAC_CLEANER_SIGNING_IDENTITY" != "-" ]] || \
    fail "release builds cannot use an ad-hoc signing identity"

identity_line="$(/usr/bin/security find-identity -p codesigning -v | \
    /usr/bin/grep -F "$MAC_CLEANER_SIGNING_IDENTITY" | /usr/bin/head -n 1 || true)"
[[ -n "$identity_line" ]] || \
    fail "signing identity was not found in the keychain: $MAC_CLEANER_SIGNING_IDENTITY"
[[ "$identity_line" == *"Developer ID Application:"* ]] || \
    fail "MAC_CLEANER_SIGNING_IDENTITY must resolve to a Developer ID Application certificate"

export MAC_CLEANER_OUTPUT_DIR="${MAC_CLEANER_OUTPUT_DIR:-$repo_root/dist}"

"$repo_root/scripts/build-universal-app.sh"

app_path="$MAC_CLEANER_OUTPUT_DIR/MacCleaner.app"
"$repo_root/scripts/verify-app.sh" --require-developer-id "$app_path"

echo "Release bundle ready for notarization: $app_path"
