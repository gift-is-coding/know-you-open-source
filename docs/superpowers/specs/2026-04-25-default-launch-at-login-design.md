# Default Launch At Login Design

## Goal

KnowYou should register itself to open at macOS login by default after the user opens the app, so capture and launch-time automation are available without requiring the user to discover a setting.

## Product Behavior

- First normal interactive launch attempts to register the main app as a login item.
- Settings exposes a simple `Launch at Login` toggle so the user can turn the behavior off or back on.
- If the user turns it off in KnowYou, later launches do not automatically re-enable it.
- macOS remains the final authority: the user can still disable KnowYou in System Settings.
- This feature does not add a hidden background-only mode and does not change Sync Memory's existing LaunchAgent.

## Implementation

- Add a small login item manager abstraction around `SMAppService.mainApp`.
- Store a `launchAtLoginDefaultRegistrationAttempted` flag in `UserDefaults`.
- `AppState.ensureDefaultLaunchAtLogin()` performs the first-launch default registration once.
- `AppState.setLaunchAtLoginEnabled(_:)` powers the Settings toggle.
- `KnowYouApp` calls the default registration only for normal interactive launches, not `--sync-memory-now`.

## Testing

- Unit tests cover one-time default registration, user opt-out persistence, explicit toggle enable/disable, and failure rollback.
- Existing Sync Memory LaunchAgent behavior remains unchanged.

