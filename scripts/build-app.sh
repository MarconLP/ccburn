#!/usr/bin/env bash
# Builds build/ccburn.app: the Swift menu bar shell plus the ccburn script it runs.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/ccburn.app"

swift build -c release --package-path "$root/app"
bin="$(swift build -c release --package-path "$root/app" --show-bin-path)/CCBurnBar"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/ccburn"
cp "$root/ccburn" "$app/Contents/Resources/ccburn"
build="$(git -C "$root" rev-list --count HEAD 2>/dev/null || echo 1)"
sed "s/__BUILD__/$build/" "$root/app/Info.plist" > "$app/Contents/Info.plist"

# Ad-hoc signature: enough to run locally and register as a login item.
codesign --force --sign - "$app"
echo "$app"
