#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

output_dir="${MAC_CLEANER_OUTPUT_DIR:-$repo_root/dist}"
app_path="${1:-$output_dir/MacCleaner.app}"

[[ -d "$app_path" ]] || fail "release bundle not found: $app_path"

plist="$app_path/Contents/Info.plist"
version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$plist")"
artifact_name="MacCleaner-$version.zip"
artifact_path="$output_dir/$artifact_name"
checksum_path="$artifact_path.sha256"

declare -a authentication=()
if [[ -n "${MAC_CLEANER_NOTARY_PROFILE:-}" ]]; then
    authentication=(--keychain-profile "$MAC_CLEANER_NOTARY_PROFILE")
elif [[ -n "${MAC_CLEANER_NOTARY_KEY:-}" && \
        -n "${MAC_CLEANER_NOTARY_KEY_ID:-}" && \
        -n "${MAC_CLEANER_NOTARY_ISSUER:-}" ]]; then
    [[ -f "$MAC_CLEANER_NOTARY_KEY" ]] || \
        fail "MAC_CLEANER_NOTARY_KEY does not point to an API key file"
    authentication=(
        --key "$MAC_CLEANER_NOTARY_KEY"
        --key-id "$MAC_CLEANER_NOTARY_KEY_ID"
        --issuer "$MAC_CLEANER_NOTARY_ISSUER"
    )
else
    fail "set MAC_CLEANER_NOTARY_PROFILE or all of MAC_CLEANER_NOTARY_KEY, MAC_CLEANER_NOTARY_KEY_ID, and MAC_CLEANER_NOTARY_ISSUER"
fi

"$repo_root/scripts/verify-app.sh" --require-developer-id "$app_path"

mkdir -p "$output_dir"
temporary_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/mac-cleaner-notary.XXXXXX")"
submission_zip="$temporary_dir/MacCleaner.zip"
submission_response="$temporary_dir/submission.json"

cleanup() {
    /bin/rm -R "$temporary_dir"
}
trap cleanup EXIT

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$submission_zip"

echo "Submitting Mac Cleaner $version for notarization"
if ! /usr/bin/xcrun notarytool submit \
    "$submission_zip" \
    "${authentication[@]}" \
    --wait \
    --output-format json >"$submission_response"; then
    cat "$submission_response" >&2
    fail "notarytool submission failed"
fi

submission_status="$(/usr/bin/plutil -extract status raw -o - "$submission_response")"
submission_id="$(/usr/bin/plutil -extract id raw -o - "$submission_response")"

if [[ "$submission_status" != "Accepted" ]]; then
    /usr/bin/xcrun notarytool log "$submission_id" "${authentication[@]}" >&2 || true
    fail "notarization $submission_id finished with status: $submission_status"
fi

/usr/bin/xcrun stapler staple "$app_path"
/usr/bin/xcrun stapler validate "$app_path"
"$repo_root/scripts/verify-app.sh" --require-notarized "$app_path"

if [[ -e "$artifact_path" ]]; then
    /bin/rm -f "$artifact_path"
fi
if [[ -e "$checksum_path" ]]; then
    /bin/rm -f "$checksum_path"
fi

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$artifact_path"
(
    cd "$output_dir"
    /usr/bin/shasum -a 256 "$artifact_name" >"$artifact_name.sha256"
)

echo "Notarized release artifacts:"
echo "  $artifact_path"
echo "  $checksum_path"
