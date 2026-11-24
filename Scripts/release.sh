#!/bin/zsh
# Builds a Release .app, signs it ad-hoc (no personal certificate in the artifact), and
# packages build/dist/CommandCenter-<version>-macOS.zip and .dmg.
set -e
cd "$(dirname "$0")/.."
CONFIG=Release ./build.sh build >/dev/null
APP="build/DD/Build/Products/Release/Command Center.app"
VERSION=$(defaults read "$PWD/$APP/Contents/Info.plist" CFBundleShortVersionString)
codesign --force --deep --sign - --entitlements CommandCenter/Resources/CommandCenter.entitlements "$APP"
codesign --verify --deep --strict "$APP"
rm -rf build/dist build/dmg && mkdir -p build/dist build/dmg
ditto -c -k --keepParent "$APP" "build/dist/CommandCenter-$VERSION-macOS.zip"
cp -R "$APP" build/dmg/ && ln -s /Applications build/dmg/Applications
hdiutil create -volname "Command Center" -srcfolder build/dmg -ov -format UDZO "build/dist/CommandCenter-$VERSION.dmg" >/dev/null
shasum -a 256 build/dist/*
