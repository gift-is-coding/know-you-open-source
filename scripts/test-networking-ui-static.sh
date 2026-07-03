#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NETWORKING_VIEW="$ROOT/KnowYou/UI/Networking/NetworkingCockpitView.swift"
APP_FILE="$ROOT/KnowYou/KnowYouApp.swift"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq "$needle" "$file" || fail "$file missing: $needle"
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq "$needle" "$file"; then
    fail "$file should not contain: $needle"
  fi
}

assert_order() {
  local file="$1"
  local first="$2"
  local second="$3"
  perl -0e '
    my ($file, $first, $second) = @ARGV;
    open my $fh, "<:encoding(UTF-8)", $file or die $!;
    local $/;
    my $source = <$fh>;
    my $a = index($source, $first);
    my $b = index($source, $second);
    exit(($a >= 0 && $b >= 0 && $a < $b) ? 0 : 1);
  ' "$file" "$first" "$second" || fail "$file order check failed: $first before $second"
}

assert_no_chinese() {
  local file="$1"
  perl -CS -0e '
    my ($file) = @ARGV;
    open my $fh, "<:encoding(UTF-8)", $file or die $!;
    local $/;
    my $source = <$fh>;
    exit($source =~ /[\x{4E00}-\x{9FFF}]/ ? 1 : 0);
  ' "$file" || fail "$file contains Chinese characters in visible Networking copy"
}

assert_not_contains "$NETWORKING_VIEW" "import WebKit"
assert_not_contains "$NETWORKING_VIEW" "WKWebView"
assert_not_contains "$NETWORKING_VIEW" "NSViewRepresentable"
assert_not_contains "$NETWORKING_VIEW" "loadHTMLString"
assert_contains "$NETWORKING_VIEW" "ScrollView"
assert_contains "$NETWORKING_VIEW" "Generate profiles"

assert_contains "$APP_FILE" "showMainWindowAfterPresenterConfigurationIfNeeded"
assert_contains "$APP_FILE" "KnowYouMainWindowPresenter.shared.configure"
assert_contains "$APP_FILE" "DispatchQueue.main.asyncAfter(deadline: .now() + 1.0)"

assert_contains "$NETWORKING_VIEW" "Privacy and redaction"
assert_contains "$NETWORKING_VIEW" "Choose a default scenario or create a custom one."
assert_contains "$NETWORKING_VIEW" "Generated result preview"
assert_contains "$NETWORKING_VIEW" "Custom profile"
assert_not_contains "$NETWORKING_VIEW" "Custom scenario"
assert_contains "$NETWORKING_VIEW" "Communities and messages"
assert_not_contains "$NETWORKING_VIEW" "Connect communities"
assert_not_contains "$NETWORKING_VIEW" "Review messages and leads"
assert_contains "$NETWORKING_VIEW" "Know You Careers"
assert_contains "$NETWORKING_VIEW" "Find Your Friends"
assert_not_contains "$NETWORKING_VIEW" "Know You Friends"
assert_not_contains "$NETWORKING_VIEW" 'Text("Prompt")'
assert_not_contains "$NETWORKING_VIEW" "selectedProfile.prompt"

assert_contains "$NETWORKING_VIEW" "let projectRoot: URL?"
assert_contains "$NETWORKING_VIEW" "let summarizer: (any SummaryGenerating)?"
assert_contains "$NETWORKING_VIEW" "ensureActivationState"
assert_contains "$NETWORKING_VIEW" "Agent ready locally"
assert_not_contains "$NETWORKING_VIEW" "Enable Networking"
assert_not_contains "$NETWORKING_VIEW" "Networking enabled"
assert_not_contains "$NETWORKING_VIEW" "enableNetworking()"

assert_contains "$NETWORKING_VIEW" "generateSelectedProfile"
assert_contains "$NETWORKING_VIEW" "NetworkingProfileGenerationService"
assert_contains "$NETWORKING_VIEW" "Update profile"
assert_contains "$NETWORKING_VIEW" "Approve profile"
assert_not_contains "$NETWORKING_VIEW" "Regenerate"
assert_contains "$NETWORKING_VIEW" "Approved"
assert_contains "$NETWORKING_VIEW" "Draft not generated"
assert_contains "$NETWORKING_VIEW" "Could not finish profile generation"
assert_contains "$NETWORKING_VIEW" "Generation timed out. Try again after checking your Diary Engine."
assert_order "$NETWORKING_VIEW" 'Button("Approve profile"' 'Text("Full profile draft")'

assert_contains "$NETWORKING_VIEW" "Full profile draft"
assert_contains "$NETWORKING_VIEW" "FullProfileDraftBody(text: draft.body)"
assert_contains "$NETWORKING_VIEW" "Generated draft"
assert_contains "$NETWORKING_VIEW" "private struct FullProfileDraftBody"
assert_contains "$NETWORKING_VIEW" "collapsedHeight: CGFloat = 360"
assert_contains "$NETWORKING_VIEW" "Show full profile"
assert_contains "$NETWORKING_VIEW" "Hide profile"
assert_contains "$NETWORKING_VIEW" "shouldCollapse && !isExpanded"

assert_contains "$NETWORKING_VIEW" "Use case"
assert_contains "$NETWORKING_VIEW" "Profile image direction"
assert_contains "$NETWORKING_VIEW" "Public tone"
assert_contains "$NETWORKING_VIEW" "Redaction notes"
assert_contains "$NETWORKING_VIEW" "Generate custom profile"
assert_contains "$NETWORKING_VIEW" "Add custom profile"
assert_contains "$NETWORKING_VIEW" "customProfileConfigurations"
assert_contains "$NETWORKING_VIEW" "contact info"
assert_contains "$NETWORKING_VIEW" "account handles"
assert_contains "$NETWORKING_VIEW" "exact locations"
assert_contains "$NETWORKING_VIEW" "private relationships"
assert_contains "$NETWORKING_VIEW" "health/finance"
assert_contains "$NETWORKING_VIEW" "raw diary/notifications"
assert_contains "$NETWORKING_VIEW" "tokens/account details"
assert_contains "$NETWORKING_VIEW" "deep matching reasons"
assert_contains "$NETWORKING_VIEW" "unconfirmed claims"

assert_contains "$NETWORKING_VIEW" "safeAreaInset(edge: .top)"
assert_contains "$NETWORKING_VIEW" "GenerationStatusCard"
assert_contains "$NETWORKING_VIEW" "frame(maxWidth: 420"
assert_contains "$NETWORKING_VIEW" "fixedSize(horizontal: false, vertical: true)"

assert_contains "$NETWORKING_VIEW" "GeneratedFaceAvatar"
assert_contains "$NETWORKING_VIEW" "avatarSeed"
assert_not_contains "$NETWORKING_VIEW" "Text(profile.avatar.displayLetter)"
assert_not_contains "$NETWORKING_VIEW" "Text(profile.avatar.fallbackLetter)"
assert_not_contains "$NETWORKING_VIEW" "Text(profile.personName)"

assert_contains "$NETWORKING_VIEW" "loadDraftState()"
assert_contains "$NETWORKING_VIEW" "NetworkingProfileDraftStateStore"
assert_contains "$NETWORKING_VIEW" ".load(projectRoot: projectRoot)"
assert_contains "$NETWORKING_VIEW" ".save(nextState, projectRoot: projectRoot)"
assert_no_chinese "$NETWORKING_VIEW"

printf 'Networking UI static checks passed.\n'
