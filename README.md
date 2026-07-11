# Mac Cleaner

Mac Cleaner is a native SwiftUI macOS utility for scanning user-accessible storage, finding large files and folders, classifying known app footprints, and moving selected items to Trash after confirmation.

## Build

```sh
swift build
```

## Test

```sh
swift test
```

Run the packaged-app safety and persistence flow with disposable home and data
directories:

```sh
scripts/test-packaged-app.sh
```

The harness never scans your real home. It launches the built app with isolated
`HOME`, `CFFIXED_USER_HOME`, `MAC_CLEANER_HOME`, and `MAC_CLEANER_DATA_DIR`, then
tests hidden/package/symlink accounting, replacement blocking, real reversible
Trash operations on disposable fixtures, and persistence refresh after restart.

## Run

```sh
swift run MacCleaner
```

For controlled UI testing, isolate both the scanned home directory and persisted
scan state. Using only `MAC_CLEANER_HOME` can still load a real saved report:

```sh
MAC_CLEANER_HOME=/tmp/mac-cleaner-e2e-home \
MAC_CLEANER_DATA_DIR=/tmp/mac-cleaner-e2e-state \
swift run MacCleaner
```

## Package a local app bundle

```sh
scripts/build-app.sh
```

The generated bundle is placed at `.build/MacCleaner.app`.
