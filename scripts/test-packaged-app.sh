#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
scratch_root="$(mktemp -d "/tmp/mac-cleaner-packaged-e2e.XXXXXX")"

cleanup() {
    if command -v tmp-rmrf >/dev/null 2>&1; then
        tmp-rmrf "$scratch_root"
    else
        CLEANUP_PATH="$scratch_root" swift -e \
            'import Foundation; try? FileManager.default.removeItem(atPath: ProcessInfo.processInfo.environment["CLEANUP_PATH"]!)' \
            >/dev/null 2>&1
    fi
}
trap cleanup EXIT

home_dir="$scratch_root/home"
data_dir="$scratch_root/state"
mkdir -p "$home_dir" "$data_dir"

cd "$repo_root"
scripts/build-app.sh

HOME="$home_dir" \
CFFIXED_USER_HOME="$home_dir" \
MAC_CLEANER_HOME="$home_dir" \
MAC_CLEANER_DATA_DIR="$data_dir" \
MAC_CLEANER_E2E_APP="$repo_root/.build/MacCleaner.app" \
swift test --filter MacCleanerPackagedAppE2ETests.PackagedAppE2ETests
