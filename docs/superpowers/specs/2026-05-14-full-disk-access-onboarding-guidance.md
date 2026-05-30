# Full Disk Access Onboarding Guidance

## Problem

New users can reach the onboarding permission step, click the Full Disk Access action, and then fail to find KnowYou in System Settings. The current UI implies that KnowYou should already be visible in the Full Disk Access list, but macOS Full Disk Access is a manual System Settings grant. If the app is not already listed, the user must add the app bundle themselves.

## Evidence

- `OnboardingView.openFullDiskAccess()` only opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`.
- The permission step copy says to turn on Full Disk Access but does not explain the manual add flow.
- Apple documents Full Disk Access as a setting users explicitly add in System Settings.
- Apple Developer Forums explain that TCC behavior depends on stable signing and responsible code. The project already signs Debug and Release builds with stable identities, so this issue is not primarily a signing regression.

## Goal

Make the onboarding permission step self-contained when KnowYou is not already present in Full Disk Access: users should know to add the app manually, have a way to reveal the exact app bundle in Finder, and still be able to re-check permission after granting access.

## Non-Goals

- Do not try to grant Full Disk Access programmatically.
- Do not change the hard gate: Full Disk Access remains required before onboarding advances.
- Do not change notification authorization behavior.

## Design

Add explicit Full Disk Access guidance to the onboarding content model, then render that guidance in the permission card. The permission actions become:

1. Open Full Disk Access.
2. Show KnowYou in Finder.
3. Check Again.

The Finder action uses `NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])`, which gives the user a concrete app bundle to select or drag into the System Settings list.

## Testing

Add focused `OnboardingContentTests` coverage that ensures the permission guidance tells users what to do when KnowYou is not listed and exposes the expected button titles.
