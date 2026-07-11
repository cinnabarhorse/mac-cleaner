#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "error: $*" >&2
    exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_path="${1:-$repo_root/.build/universal/MacCleaner.app}"
executable="$app_path/Contents/MacOS/MacCleaner"

[[ -x "$executable" ]] || fail "packaged executable not found: $executable"

temporary_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/mac-cleaner-smoke.XXXXXX")"
smoke_home="$temporary_dir/home"
smoke_data="$temporary_dir/data"
log_path="$temporary_dir/MacCleaner.log"
pid_path="$temporary_dir/MacCleaner.pid"
app_pid=""

mkdir -p "$smoke_home" "$smoke_data"

cleanup() {
    if [[ -n "$app_pid" ]] && /bin/kill -0 "$app_pid" 2>/dev/null; then
        /bin/kill "$app_pid" 2>/dev/null || true
        for _ in 1 2 3 4 5; do
            if ! /bin/kill -0 "$app_pid" 2>/dev/null; then
                break
            fi
            /bin/sleep 1
        done
        if /bin/kill -0 "$app_pid" 2>/dev/null; then
            /bin/kill -KILL "$app_pid" 2>/dev/null || true
        fi
        wait "$app_pid" 2>/dev/null || true
    fi
    /bin/rm -R "$temporary_dir"
}
trap cleanup EXIT

HOME="$smoke_home" \
CFFIXED_USER_HOME="$smoke_home" \
MAC_CLEANER_HOME="$smoke_home" \
MAC_CLEANER_DATA_DIR="$smoke_data" \
"$executable" >"$log_path" 2>&1 &
app_pid=$!
echo "$app_pid" >"$pid_path"

started=false
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if /usr/bin/pgrep -F "$pid_path" -x MacCleaner >/dev/null; then
        started=true
        break
    fi
    if ! /bin/kill -0 "$app_pid" 2>/dev/null; then
        cat "$log_path" >&2
        fail "packaged app exited during launch"
    fi
    /bin/sleep 1
done

if [[ "$started" != true ]]; then
    cat "$log_path" >&2
    fail "packaged app did not become observable within 10 seconds"
fi

/bin/sleep 2
if ! /usr/bin/pgrep -F "$pid_path" -x MacCleaner >/dev/null; then
    cat "$log_path" >&2
    fail "packaged app did not remain running"
fi

[[ -d "$smoke_home" && -d "$smoke_data" ]] || \
    fail "isolated smoke-test directories disappeared unexpectedly"

echo "Packaged app launched successfully with isolated home and data directories"
