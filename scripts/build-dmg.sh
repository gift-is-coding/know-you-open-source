#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/release-common.sh"

require_command ditto
require_command hdiutil
require_command osascript
require_command SetFile
require_command swift

prepare_release_dir
ensure_file_exists "$app_path"

generator_dir="$(mktemp -d)"
rw_dmg_path="$release_dir/$(artifact_basename)-rw.dmg"
cleanup() {
  rm -rf "$generator_dir"
  rm -f "$rw_dmg_path"
}
trap cleanup EXIT

background_dir="$generator_dir/.background"
background_path="$background_dir/background.png"
mkdir -p "$background_dir"

generate_background() {
  local output_path="$1"
  local swift_path="$generator_dir/generate-dmg-background.swift"

  cat >"$swift_path" <<'SWIFT'
import AppKit

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let width: CGFloat = 560
let height: CGFloat = 300

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width),
    pixelsHigh: Int(height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to create DMG background bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let bounds = NSRect(x: 0, y: 0, width: width, height: height)
NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
bounds.fill()

let topWash = NSGradient(
    colors: [
        NSColor(calibratedWhite: 1.0, alpha: 1),
        NSColor(calibratedWhite: 0.93, alpha: 1)
    ]
)
topWash?.draw(in: bounds, angle: -90)

let title = "Drag KnowYou to Applications"
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.16, alpha: 1)
]
let titleSize = title.size(withAttributes: titleAttributes)
title.draw(
    at: NSPoint(x: (width - titleSize.width) / 2, y: 240),
    withAttributes: titleAttributes
)

let subtitle = "Move the app first, then grant Full Disk Access."
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1)
]
let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
subtitle.draw(
    at: NSPoint(x: (width - subtitleSize.width) / 2, y: 216),
    withAttributes: subtitleAttributes
)

let arrowColor = NSColor(calibratedRed: 0.33, green: 0.55, blue: 0.86, alpha: 1)
arrowColor.setStroke()
arrowColor.setFill()

let shaft = NSBezierPath()
shaft.lineWidth = 6
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 235, y: 148))
shaft.line(to: NSPoint(x: 325, y: 148))
shaft.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 325, y: 148))
head.line(to: NSPoint(x: 300, y: 168))
head.line(to: NSPoint(x: 300, y: 128))
head.close()
head.fill()

NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode DMG background PNG")
}
try data.write(to: outputURL)
SWIFT

  swift "$swift_path" "$output_path"
}

generate_background "$background_path"

rm -f "$(release_dmg_path)" "$rw_dmg_path"
hdiutil create \
  -size 64m \
  -fs HFS+ \
  -volname "KnowYou" \
  -ov \
  "$rw_dmg_path"

mount_output="$(hdiutil attach "$rw_dmg_path" -readwrite -noverify -noautoopen)"
device="$(printf '%s\n' "$mount_output" | awk 'index($0, "/Volumes/KnowYou") { print $1; exit }')"
mount_point="$(printf '%s\n' "$mount_output" | awk -F '\t' 'index($0, "/Volumes/KnowYou") { print $NF; exit }')"

if [[ -z "$device" || -z "$mount_point" ]]; then
  echo "Unable to mount DMG for layout customization." >&2
  printf '%s\n' "$mount_output" >&2
  exit 1
fi

ditto "$app_path" "$mount_point/KnowYou.app"
ln -s /Applications "$mount_point/Applications"
mkdir -p "$mount_point/.background"
ditto "$background_path" "$mount_point/.background/background.png"
SetFile -a V "$mount_point/.background"

if ! DMG_MOUNT_POINT="$mount_point" osascript <<'APPLESCRIPT'
set mountPoint to system attribute "DMG_MOUNT_POINT"
set backgroundPath to mountPoint & "/.background/background.png"

with timeout of 300 seconds
  tell application "Finder"
    set installerFolder to POSIX file mountPoint as alias
    open installerFolder
    delay 1
    set installerWindow to front Finder window
    tell installerWindow
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set bounds to {100, 100, 660, 400}
    end tell
    set theViewOptions to icon view options of installerWindow
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 96
    set background picture of theViewOptions to POSIX file backgroundPath
    set position of item "KnowYou.app" of installerFolder to {150, 148}
    set position of item "Applications" of installerFolder to {430, 148}
    delay 2
    close installerWindow
  end tell
end timeout
APPLESCRIPT
then
  hdiutil detach "$device" || true
  exit 1
fi

for _ in {1..30}; do
  if [[ -s "$mount_point/.DS_Store" ]]; then
    break
  fi
  osascript -e 'tell application "Finder" to update disk "KnowYou"' >/dev/null 2>&1 || true
  sleep 1
done

if [[ ! -s "$mount_point/.DS_Store" ]]; then
  echo "Finder did not persist DMG layout metadata: $mount_point/.DS_Store" >&2
  ls -la "$mount_point" >&2
  hdiutil detach "$device" || true
  exit 1
fi

sync
hdiutil detach "$device"
hdiutil convert "$rw_dmg_path" -format UDZO -o "$(release_dmg_path)" -ov

echo "DMG: $(release_dmg_path)"
