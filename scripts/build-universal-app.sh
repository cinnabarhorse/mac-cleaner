#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

version="${MAC_CLEANER_VERSION:-0.1.0}"
build_number="${MAC_CLEANER_BUILD_NUMBER:-1}"
signing_identity="${MAC_CLEANER_SIGNING_IDENTITY:--}"
output_dir="${MAC_CLEANER_OUTPUT_DIR:-$repo_root/.build/universal}"
scratch_dir="${MAC_CLEANER_ARCH_BUILD_DIR:-$repo_root/.build/release-architectures}"

[[ "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] || \
    fail "MAC_CLEANER_VERSION must use MAJOR.MINOR.PATCH numeric components"
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || \
    fail "MAC_CLEANER_BUILD_NUMBER must be a positive integer"

mkdir -p "$output_dir" "$scratch_dir"
output_dir="$(cd "$output_dir" && pwd)"
scratch_dir="$(cd "$scratch_dir" && pwd)"

sdk_path="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
declare -a binaries=()

for architecture in arm64 x86_64; do
    architecture_scratch="$scratch_dir/$architecture"
    triple="$architecture-apple-macosx14.0"

    echo "Building MacCleaner for $architecture"
    swift build \
        --configuration release \
        --product MacCleaner \
        --scratch-path "$architecture_scratch" \
        --sdk "$sdk_path" \
        --triple "$triple"

    binary_dir="$(swift build \
        --configuration release \
        --scratch-path "$architecture_scratch" \
        --sdk "$sdk_path" \
        --triple "$triple" \
        --show-bin-path)"
    binary="$binary_dir/MacCleaner"
    [[ -x "$binary" ]] || fail "build did not produce $binary"
    binaries+=("$binary")
done

app_path="$output_dir/MacCleaner.app"
staging_path="$output_dir/.MacCleaner.app.staging.$$"

cleanup() {
    if [[ -d "$staging_path" ]]; then
        /bin/rm -R "$staging_path"
    fi
}
trap cleanup EXIT

mkdir -p "$staging_path/Contents/MacOS" "$staging_path/Contents/Resources"
/usr/bin/ditto "$repo_root/Packaging/Info.plist" "$staging_path/Contents/Info.plist"
/usr/bin/ditto "$repo_root/Packaging/AppIcon.icns" "$staging_path/Contents/Resources/AppIcon.icns"

/usr/bin/lipo -create "${binaries[@]}" -output "$staging_path/Contents/MacOS/MacCleaner"
chmod +x "$staging_path/Contents/MacOS/MacCleaner"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$staging_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$staging_path/Contents/Info.plist"
/usr/bin/xattr -cr "$staging_path"

if [[ "$signing_identity" == "-" ]]; then
    /usr/bin/codesign --force --sign - "$staging_path"
else
    /usr/bin/codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$signing_identity" \
        "$staging_path"
fi

if [[ -e "$app_path" ]]; then
    /bin/rm -R "$app_path"
fi
/bin/mv "$staging_path" "$app_path"

"$repo_root/scripts/verify-app.sh" "$app_path"

if [[ "$signing_identity" == "-" ]]; then
    echo "Built $app_path (universal, ad-hoc signed for testing)"
else
    echo "Built $app_path (universal, Developer ID signed)"
fi
