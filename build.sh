#!/bin/zsh
# Builds Command Center into build/DD/Build/Products/<config>/Command Center.app
# Signs with your local "Apple Development" identity when one exists (stable signature, so
# Keychain items stay readable across rebuilds); otherwise falls back to ad-hoc signing.
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SIGN="${CC_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')}"
# Local, git-ignored signing config applied to the app target only.
if [[ -n "$SIGN" ]]; then
  TEAM=$(security find-certificate -Z -a -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p' | head -1)
  printf 'CODE_SIGN_IDENTITY = %s\nDEVELOPMENT_TEAM = %s\n' "$SIGN" "$TEAM" > Local.xcconfig
else
  : > Local.xcconfig
fi
xcodegen generate -q
SIGN_ARGS=()
xcodebuild -project CommandCenter.xcodeproj -scheme CommandCenter -configuration "${CONFIG:-Debug}" \
  -derivedDataPath build/DD -clonedSourcePackagesDirPath build/SourcePackages \
  -skipPackagePluginValidation -skipMacroValidation "${SIGN_ARGS[@]}" "${@:-build}"
