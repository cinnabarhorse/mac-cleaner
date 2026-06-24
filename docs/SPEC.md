# Mac Cleaner Specification

## Product Goal

Mac Cleaner is a Swift macOS app that helps a user understand and reclaim disk space from deep, hard-to-audit locations such as `~/Library`, `~/Documents`, developer caches, media libraries, and app-specific storage for tools like Codex, CapCut, and Final Cut Pro.

The app must answer three questions quickly:

1. What files and folders are consuming the most space?
2. Why does each item likely exist, and how risky is deletion?
3. Can the user safely move selected items to Trash from inside the app?

## Non-Goals

- The app does not permanently delete files. It moves selected items to Trash.
- The app does not bypass macOS privacy controls, SIP, TCC, file ownership, or sandbox restrictions.
- The app does not delete protected system locations by default.
- The app does not claim every app-support file is safe to remove. It classifies risk and requires confirmation.

## Permissions and Safety Model

macOS privacy permissions determine what can be scanned. Without Full Disk Access, locations like some app containers, Mail, Messages, Photos, and protected folders may return permission errors. The scanner records those errors and continues.

Deletion is intentionally constrained:

- Only move-to-Trash is supported.
- Destructive actions are gated by an explicit confirmation sheet.
- Protected system paths are not offered as deletion candidates.
- Root scan folders are not offered as deletion candidates.
- The UI labels each item with risk: Low, Medium, High, or Protected.
- After a successful Trash move, the item is removed from the visible results until the next scan.

## Scan Scopes

Default scan scopes focus on locations where large removable data commonly accumulates:

- `~/Documents`
- `~/Downloads`
- `~/Movies`
- `~/Library/Caches`
- `~/Library/Logs`
- `~/Library/Application Support`
- `~/Library/Developer`
- `~/.codex`
- CapCut support/cache/project locations
- Final Cut Pro cache, backup, and media support locations

Optional scopes include broader home-directory and system-library locations. System-library scopes are categorized as protected unless the item is clearly cache/log data and user permissions allow access.

## Known App Profiles

Known app profiles are small path catalogs that give the scanner better category and risk hints.

### Codex

- `~/.codex`
- `~/Library/Application Support/Codex`
- `~/Library/Caches/Codex`
- `~/Library/Logs/Codex`

Common heavy data: sessions, logs, model/tool caches, temporary work artifacts.

### CapCut

- `~/Movies/CapCut`
- `~/Library/Application Support/CapCut`
- `~/Library/Application Support/com.lemon.lvoverseas`
- `~/Library/Caches/CapCut`
- `~/Library/Caches/com.lemon.lvoverseas`
- `~/Library/Containers/com.lemon.lvoverseas`

Common heavy data: projects, rendered media, cache, proxies, downloads.

### Final Cut Pro

- `~/Movies/Final Cut Backups`
- `~/Movies/Motion Templates`
- `~/Library/Application Support/ProApps`
- `~/Library/Caches/com.apple.FinalCut`
- `~/Library/Caches/com.apple.FinalCutTrial`

Common heavy data: libraries, render files, backups, generated media, motion templates.

## Scanner Design

The scan engine runs off the main actor and uses `FileManager.enumerator` with resource keys for:

- file/folder/package/symlink type
- allocated size
- modification date
- access date
- hidden status

For every file, allocated bytes are accumulated into all ancestor directories for the active scan root. The final report contains large files and aggregate folders sorted by size descending.

Scanner behavior:

- Continues after per-path errors.
- Supports cancellation.
- Reports progress to the UI.
- Skips hidden files unless enabled.
- Includes package contents by default for granular app/media analysis.
- Caps returned rows to protect UI memory on very large scans.

## Classification

Items are classified by path and scan-root hints:

- Cache
- Logs
- Developer Data
- Application Support
- Media
- Documents
- Backups
- Codex
- CapCut
- Final Cut Pro
- Downloads
- Trash
- System
- Other

Risk rules:

- Low: caches, logs, derived data, disposable build outputs.
- Medium: app support, developer data, downloads, backups.
- High: documents, media, Final Cut/CapCut project data, user-created libraries.
- Protected: system paths, applications, root folders, and paths outside the user's home where removal would be unsafe.

## UI Specification

The app uses a three-column macOS layout:

- Sidebar: scan scopes, custom folders, and scan options.
- Results: searchable, filterable list of large items with size, category, risk, kind, and path.
- Detail: selected item metadata and actions.

Expected controls:

- Scan/Stop toolbar button.
- Scope toggles.
- Hidden-files toggle.
- Package-contents toggle.
- Minimum-size picker.
- Category and risk filters.
- Staleness filter for items untouched for 30, 90, 180, or 365 days.
- Safe Picks action that selects old low-risk cache, log, and Trash candidates.
- Multi-selection and batch Move to Trash with nested selections coalesced under selected parents.
- Markdown and CSV report export.
- Add folder button.
- Reveal in Finder button.
- Copy path button.
- Move to Trash button for eligible items.
- Full Disk Access notice with settings/install guidance when protected-folder permission issues are detected.

Empty, loading, error, and partial-permission states must be visible without blocking successful scan results.

## Test Strategy

Core behavior is covered with XCTest:

- Directory aggregation and largest-item ordering.
- Minimum-size filtering.
- Symlink skipping.
- Known app profile root generation.
- Classification and risk decisions.
- Trash flow through a fake trash manager.

Manual/E2E verification:

- Build the app.
- Run unit tests.
- Launch the app.
- Smoke-test the UI with a scan of controlled local paths where possible.
- Confirm deletion UI is guarded and only uses Trash.

## Implementation Stack

- Swift 6.3
- SwiftPM
- SwiftUI for macOS
- Observation (`@Observable`) for app state
- XCTest for core tests
- No third-party dependencies
