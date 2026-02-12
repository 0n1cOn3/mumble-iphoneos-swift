# Modernization guidelines for migrating to Swift

- **Swift migration**: Convert Objective-C files under `Source/Classes/` to Swift 5. Keep the existing folder structure. Use bridging headers if some MumbleKit APIs remain in Objective-C.
- **ARC adoption**: The project still uses manual retain/release calls (for example in `MUCertificateViewController.m`). Remove `release`/`autorelease` patterns and adopt ARC when translating to Swift.
- **Deployment targets**: The base deployment target is iOS 12. Guard new APIs with availability checks to keep compatibility with older iOS versions.
- **Replace deprecated APIs**: Update `UIAlertView` and other legacy UI code to modern UIKit or SwiftUI equivalents. Use `XCTest` instead of `SenTestingKit`.
- **Storyboard & Auto Layout**: Migrate nibs to storyboards and add Auto Layout constraints as needed.
- **Audio**: Preserve existing audio features while updating to use `AVAudioSession` / `AVAudioEngine` as appropriate. Maintain interoperability with MumbleKit.
- **Submodules**: The repo contains git submodules (`MumbleKit`, `Dependencies/fmdb`). Do not modify submodule contents directly. Ensure they are updated and integrated with the Swift code.
- **Testing**: Running `xcodebuild` or the iOS simulator is not possible in this Linux environment. Mark any instructions requiring Xcode as non-executable here.
- **Style**: Follow Swift naming conventions, use optionals and enums where sensible, and drop C-style macros.
- **Process**: Update this `AGENTS.md` after each change to keep the migration status current.

Completed tasks
===============
- Migrated the web view code to **WKWebView**.
- Replaced **SenTestingKit** with **XCTest**.
- Rewrote certificate controllers in Swift and deleted the old Objective‑C implementations.
- Converted most user interfaces from xib files to storyboards, including the former `MainWindow.xib`.
- Converted the preferences UI to Swift (`MUPreferencesViewController`).
- Added a centralized **AVAudioEngine** capture pipeline with push-to-talk and VAD metering support.
- Migrated `MUAccessTokenViewController` to Swift 5.
- Refined the Swift access token controller to persist edits on end-edit and use modern keyboard metrics.
- **Phase 1 Complete**: Migrated all Priority 1 controllers to Swift 5:
  - Data models: `MUFavouriteServer`, `MUPublicServerList` (including `MUPublicServerListFetcher`)
  - Server list controllers: `MUFavouriteServerListController`, `MULanServerListController`, `MUPublicServerListController`, `MUCountryServerListController`
  - Core navigation: `MUConnectionController`, `MUServerRootViewController`, `MUServerViewController`
  - Patterns established: `@objcMembers` + `@objc(ClassName)` for Obj-C interop, `weak var` for delegates, enum-based state, `#available()` guards
- **Phase 2 Complete**: Migrated all Priority 2 messaging components to Swift 5:
  - Message data: `MUTextMessage`, `MUTextMessageProcessor`, `MUDataURL`, `MUMessagesDatabase`
  - Message UI: `MUMessageBubbleTableViewCell`, `MUMessageRecipientViewController`, `MUMessageAttachmentViewController`, `MUMessagesViewController`
  - Features preserved: Chat bubbles with custom drawing, keyboard animations, recipient picker, attachment viewer, local notifications, copy/delete actions
- **Phase 3 Complete**: Migrated all Priority 3 audio preference panels to Swift 5:
  - Audio preferences: `MUAdvancedAudioPreferencesViewController`, `MUAudioQualityPreferencesViewController`, `MUAudioSidetonePreferencesViewController`, `MUVoiceActivitySetupViewController`
  - Diagnostics: `MUAudioMixerDebugViewController`
  - Features preserved: Quality presets, preprocessing toggles, VAD calibration, sidetone, real-time mixer debug
- **Phase 4 Complete**: Migrated all Priority 4 certificate UI components to Swift 5:
  - Certificate management: `MUCertificatePreferencesViewController`, `MUServerCertificateTrustViewController`
  - UI components: `MUCertificateCell`, `MUCertificateCreationProgressView`
  - Features preserved: Keychain integration, identity/intermediate distinction, certificate generation progress
- **Phase 5 Complete**: Migrated all Priority 5 UI components to Swift 5:
  - Audio visualization: `MUAudioBarView`, `MUAudioBarViewCell`
  - Table view helpers: `MUTableViewHeaderLabel`, `MUServerTableViewCell`, `MUUserStateAcessoryView`
  - Server cells: `MUServerCell` (with MKServerPinger integration)
  - Backgrounds & transitions: `MUBackgroundView`, `MUPopoverBackgroundView`, `MUHorizontalFlipTransitionDelegate`
  - Welcome screens: `MUWelcomeScreenPhone`, `MUWelcomeScreenPad`
  - Utilities: `MUImageViewController`, `MULegalViewController`
  - Features preserved: Core Graphics drawing, timer-based updates, ping visualization, iPad popover styling, horizontal flip transitions
- **Phase 6 Complete**: Migrated all Priority 6 utilities and app entry to Swift 5:
  - Foundation utilities: `MUColor`, `MUImage`, `MUDatabase` (FMDB wrapper)
  - Audio capture: `MUAudioCaptureManager` (AVAudioEngine + VAD)
  - App services: `MUNotificationController`, `MURemoteControlServer` (TCP socket server)
  - UI components: `MUFavouriteServerEditViewController`, `MUServerButton`
  - App delegate: `MUApplicationDelegate` with `@main` entry point
  - **main.m deleted** - replaced by Swift `@main` attribute
  - Features preserved: SQLite persistence, remote PTT control, in-app notifications, audio session management

**MIGRATION COMPLETE** - All 58 Swift files, 0 Objective-C files remaining in Source/Classes/

Open tasks
==========
- None - Swift 5 migration complete!

Prioritized migration map
=========================
Priority 0 (Prerequisites & Guardrails)
1. **Inventory & dependency graph**
   - Confirm remaining Objective-C files under `Source/Classes`.
   - Identify which Objective-C classes are referenced by Swift via the bridging header.
   - Capture storyboard/xib references for legacy controllers before conversion.
2. **Adopt Swift-friendly project settings**
   - Ensure ARC is enabled for any remaining Objective-C targets.
   - Keep deployment target at iOS 12; wrap newer APIs in availability checks.

Priority 1 (Core app flows: connection + server lists) ✓ COMPLETE
1. **Connection & root navigation** ✓
   - `MUConnectionController` → Swift
   - `MUServerRootViewController` → Swift
   - `MUServerViewController` → Swift
2. **Server list flows** ✓
   - `MUFavouriteServerListController` → Swift
   - `MULanServerListController` → Swift
   - `MUCountryServerListController` → Swift
   - `MUPublicServerListController` → Swift
   - Supporting data models: `MUPublicServerList` → Swift, `MUFavouriteServer` → Swift

Priority 2 (Messaging surface) ✓ COMPLETE
1. **Message UI** ✓
   - `MUMessagesViewController` → Swift
   - `MUMessageRecipientViewController` → Swift
   - `MUMessageAttachmentViewController` → Swift
   - `MUMessageBubbleTableViewCell` → Swift
2. **Messaging data** ✓
   - `MUTextMessage` → Swift
   - `MUTextMessageProcessor` → Swift
   - `MUMessagesDatabase` → Swift
   - `MUDataURL` → Swift

Priority 3 (Preferences: audio panels & diagnostics) ✓ COMPLETE
1. **Audio preference panels** ✓
   - `MUAdvancedAudioPreferencesViewController` → Swift
   - `MUAudioQualityPreferencesViewController` → Swift
   - `MUAudioSidetonePreferencesViewController` → Swift
   - `MUVoiceActivitySetupViewController` → Swift
2. **Diagnostics** ✓
   - `MUAudioMixerDebugViewController` → Swift

Priority 4 (Certificates & trust UI parity) ✓ COMPLETE
1. **Certificate preferences & trust** ✓
   - `MUCertificatePreferencesViewController` → Swift
   - `MUServerCertificateTrustViewController` → Swift
   - Supporting views: `MUCertificateCell` → Swift, `MUCertificateCreationProgressView` → Swift

Priority 5 (UI polish + supporting views) ✓ COMPLETE
1. **UI components** ✓
   - `MUAudioBarView` → Swift
   - `MUAudioBarViewCell` → Swift
   - `MUTableViewHeaderLabel` → Swift
   - `MUUserStateAcessoryView` → Swift
   - `MUServerTableViewCell` → Swift
   - `MUServerCell` → Swift
   - `MUServerButton` (not present in codebase)
   - `MUPopoverBackgroundView` → Swift
   - `MUBackgroundView` → Swift
2. **Transitions & misc** ✓
   - `MUHorizontalFlipTransitionDelegate` → Swift
   - `MUImageViewController` → Swift
   - `MUWelcomeScreenPhone` → Swift
   - `MUWelcomeScreenPad` → Swift
   - `MULegalViewController` → Swift

Priority 6 (Data/utilities & app entry) ✓ COMPLETE
1. **Utilities & data** ✓
   - `MUDatabase` → Swift
   - `MUDataURL` → Swift (migrated in Phase 2)
   - `MUImage` → Swift
   - `MUColor` → Swift
   - `MUAudioCaptureManager` → Swift
2. **App delegate & notifications** ✓
   - `MUApplicationDelegate` → Swift (with `@main`)
   - `MUNotificationController` → Swift
   - `MURemoteControlServer` → Swift
3. **Entry point** ✓
   - `main.m` → deleted, replaced by `@main` on MUApplicationDelegate
4. **Additional migrations** ✓
   - `MUFavouriteServerEditViewController` → Swift
   - `MUServerButton` → Swift

Cross-cutting guidance
----------------------
- **Replace deprecated APIs**: Migrate `UIAlertView` and other legacy APIs to `UIAlertController` or modern UIKit equivalents.
- **Storyboard + Auto Layout parity**: Keep layout fidelity with existing storyboards and add constraints where needed.
- **ARC & memory safety**: Remove manual retain/release patterns during Swift conversion.
- **Submodules**: Do **not** edit `MumbleKit` or `Dependencies/fmdb`; keep integrations stable via bridging headers until Objective-C is fully removed.
- **Bridging header cleanup**: Trim after each controller migration to minimize Objective-C surface area.

Working with Claude Code
========================

See **CLAUDE.md** for comprehensive guidelines on efficient Claude usage for this project.

### Quick Summary

**Files to always include** (20K LOC, cached):
- `/Source/Classes/` — 58 Swift files (main app)
- `/MumbleKit/src/MumbleKit/*.h` — 15 public headers
- `README.markdown` — Known bugs, features, setup
- `AGENTS.md` — This file (migration status)
- `Package.swift` — Build configuration

**Files to include selectively** (only when needed):
- `/MumbleKit/src/*.m` — Objective-C implementation (audio/network/crypto debugging only)
- `/BuildConfig/*.xcconfig` — Build settings (for build tasks)
- `/Scripts/*` — Build scripts (for automation)
- `/Resources/*.plist` — Data structures (for data tasks)

**Never include** (449MB total, kills caching):
- `/MumbleKit/3rdparty/` — 44MB (OpenSSL, Opus, Protobuf, Speex)
- `/ios-logs/`, `/DiagnosticLogs/` — 405MB (debug logs)
- `*.log` files — Debug output
- `/Resources/*.png` — 102 binary images
- Build artifacts — `.build/`, `build/`, etc.

### Common Task Patterns

| Task Type | Key Files | Context Needed |
|-----------|-----------|----------------|
| **Connection crashes** | MUConnectionController.swift, MKConnection.m, MUDelegate.h | Delegate protocol, state machine, selector names |
| **Microphone issues** | Audio managers, MKAudioInput.m, MKAudioDevice.h | AVAudioSession config, audio unit properties, device info |
| **Swift/ObjC interop** | Both language files, bridging header | Selector names, @objc attributes, compiler errors |
| **UI improvements** | View controllers, storyboards, custom views | Auto Layout, dark mode, accessibility, iPad layout |
| **Build configuration** | Package.swift, .xcconfig, linker errors | Xcode version, target, full error output |

### Efficiency Tips

✅ **Batch all related information in a single message** — Prevents back-and-forth clarifications
✅ **Reference this AGENTS.md** — Say "As completed in Phase 6..." instead of re-explaining
✅ **Provide complete error output** — Full compiler/linker/crash log, not just "it failed"
✅ **Include git context** — `git log --oneline -5` output shows recent changes
✅ **Read README.markdown first** — Check known bugs before asking Claude to debug

❌ **Don't split requests** — Multiple messages for related issues
❌ **Don't include 3rdparty/** — 44MB of compiled dependencies (not project code)
❌ **Don't include logs/** — 405MB of debug artifacts
❌ **Don't provide minimal context** — "it crashes" without error message

### Documentation Structure

- **CLAUDE.md** — Comprehensive context optimization and batching patterns
- **QUICK_START.md** — Five common tasks with exact file lists and example requests
- **EXAMPLES.md** — Before/after examples of efficient vs inefficient requests
- **README.markdown** — Project overview, features, known bugs, troubleshooting
- **.claude/settings.local.json** — Codebase permissions and configuration

**Reference in requests**: "See CLAUDE.md for context optimization" or "Reference QUICK_START.md for the connection crash pattern"

### Recent Migration Patterns

Refer to completed phases in this file for patterns on:
- **Delegate implementations** — Phase 1 (connection controllers)
- **Message handling** — Phase 2 (messaging UI and data)
- **Audio integration** — Phases 3, 6 (audio session, capture manager)
- **Certificate UI** — Phase 4 (keychain integration, trust UI)
- **Custom views** — Phase 5 (Core Graphics, animations)
- **App entry** — Phase 6 (@main attribute, app delegate)

---

**Last Updated**: February 2025
