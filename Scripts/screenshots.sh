#!/bin/zsh
# Regenerates docs/screenshots from sample data only (demo mode, isolated test database).
set -e
cd "$(dirname "$0")/.."
mkdir -p /tmp/cc-screenshots && touch /tmp/cc-screenshots/.enable
./build.sh test -only-testing:CommandCenterTests/ScreenshotGenerator >/dev/null || true
rm -f /tmp/cc-screenshots/.enable
mkdir -p docs/screenshots
for f in /tmp/cc-screenshots/*.png; do sips -Z 2000 "$f" --out "docs/screenshots/$(basename "$f")" >/dev/null; done
ls docs/screenshots
