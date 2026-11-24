#!/bin/bash
# Construit l'app iPhone « Groom Pix Piste » et son widget d'écran verrouillé, et l'installe sur l'iPhone branché.
#   ./scripts/construire-iphone.sh            → construit seulement
#   ./scripts/construire-iphone.sh installer  → construit puis installe sur l'iPhone branché (déverrouillé)
# Le projet Xcode est refait à chaque fois par XcodeGen (téléchargé une fois dans build/outils si absent).
set -euo pipefail
ICI="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ICI"
mkdir -p build/outils

XG="$(command -v xcodegen || true)"
if [ -z "$XG" ]; then
  XG="$ICI/build/outils/xcodegen/bin/xcodegen"
  if [ ! -x "$XG" ]; then
    echo "Téléchargement de XcodeGen…"
    for v in 2.42.0 2.41.0 2.40.1; do
      if curl -fsSL -o build/outils/xcodegen.zip "https://github.com/yonaskolb/XcodeGen/releases/download/$v/xcodegen.zip"; then break; fi
    done
    (cd build/outils && rm -rf xcodegen && unzip -q -o xcodegen.zip)
    xattr -cr build/outils/xcodegen 2>/dev/null || true
  fi
fi

# hors du Bureau : iCloud y remet des attributs Finder que la signature refuse
DD="$HOME/Library/Developer/Xcode/DerivedData/GroomPixPiste"
cd iPhone
"$XG" generate --quiet
xcodebuild -project GroomPixPiste.xcodeproj -scheme GroomPixPiste -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath "$DD" -allowProvisioningUpdates build \
  > "$ICI/build/iphone.log" 2>&1 || { grep -E "error:" "$ICI/build/iphone.log" | sort -u; echo "BUILD FAILED (journal : build/iphone.log)"; exit 1; }
echo "BUILD SUCCEEDED"

APP="$DD/Build/Products/Debug-iphoneos/Groom Pix Piste.app"
[ -d "$APP" ] || { echo "Construction ratée."; exit 1; }
echo "Prêt : $APP"

if [ "${1:-}" = "installer" ]; then
  ID="$(xcrun devicectl list devices 2>/dev/null | awk '/available|connected/ && /iPhone/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F-]{36}$/) print $i}' | head -1)"
  [ -n "$ID" ] || { echo "Aucun iPhone branché et déverrouillé."; exit 1; }
  xcrun devicectl device install app --device "$ID" "$APP"
fi
