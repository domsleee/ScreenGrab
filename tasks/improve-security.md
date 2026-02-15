# Improve Screen Recording Permission Flow

## Current Problem
App doesn't always appear in System Settings > Privacy & Security > Screen Recording automatically. After `tccutil reset` or TCC state corruption, the entry can disappear and not come back reliably.

## Current Implementation
1. `CGPreflightScreenCaptureAccess()` — check without dialog
2. `CGRequestScreenCaptureAccess()` — registers app in System Settings, shows system dialog on first call
3. `SCShareableContent.excludingDesktopWindows()` — secondary check, also triggers registration

This is the correct pattern — same as OBS, CleanShot X, etc.

## Root Cause of Current Issue
- Previous code called `tccutil reset ScreenCapture <bundleId>` on every permission denial
- This wiped the TCC entry entirely, removing the app from System Settings
- After enough resets, the TCC database state may become inconsistent
- Self-signed certs (used for dev builds) can also cause TCC to lose track if the cert changes

## Key Findings from Research

### Code Signing & TCC
- TCC stores both **bundle ID** and **code signing requirement (csreq)** per permission entry
- Ad-hoc signing (`codesign --sign -`) produces a different signature every build — breaks TCC
- Self-signed named cert (our "ScreenGrab Dev") is stable across rebuilds — correct approach
- Developer ID (Apple-issued) is most reliable for production
- **If the self-signed cert is recreated, all TCC permissions are invalidated**

### macOS Sequoia (15) Changes
- Monthly re-authorization prompts for screen recording (was weekly in early betas)
- Managed by `replayd` daemon, stores approvals in:
  `~/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist`
- `com.apple.developer.persistent-content-capture` entitlement bypasses this (requires Apple approval)
- `forceBypassScreenCaptureAlert` MDM key (15.1+) for enterprise

### SCContentSharingPicker (macOS 14+)
- System-provided picker that doesn't need Screen Recording permission
- Not suitable for ScreenGrab — designed for screen-sharing (Zoom, Meet), not capture tools
- User picks what to share via system UI, no programmatic region selection

### Silent Permission Check (no dialog)
```swift
func canRecordScreen() -> Bool {
    let pid = NSRunningApplication.current.processIdentifier
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        as? [[String: AnyObject]] else { return false }
    for window in windows {
        guard let wpid = (window[String(kCGWindowOwnerPID)] as? Int).flatMap(pid_t.init),
              wpid != pid else { continue }
        if window[String(kCGWindowName)] as? String != nil {
            return true
        }
    }
    return false
}
```
Checks if `kCGWindowName` is visible for other apps' windows — if yes, permission is granted. No dialog triggered.

## TODO

- [ ] **Get a Developer ID certificate** — most reliable way to ensure TCC stability
  - Requires Apple Developer Program ($99/year)
  - Enables notarization (no more quarantine xattr workaround in Homebrew)
  - TCC will reliably track the app across updates
- [ ] **Never call `tccutil reset` in app code** — already removed, but ensure it stays gone
- [ ] **Consider adding the silent `canRecordScreen()` check** as a fallback detection method
- [ ] **Add user guidance for manual addition** — if app doesn't appear, tell user to click "+" in Screen Recording settings and browse to `/Applications/ScreenGrab.app`
- [ ] **Investigate `com.apple.developer.persistent-content-capture` entitlement** for avoiding Sequoia monthly prompts (requires Apple approval form)
