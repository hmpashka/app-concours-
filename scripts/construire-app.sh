#!/bin/bash
# Fabrique « Tri-photo.app » dans build/ (Mac seulement, avec Xcode ou les outils en ligne de commande).
#
#   ./scripts/construire-app.sh            app pour ce Mac
#   ./scripts/construire-app.sh universel  app pour Mac Intel ET Mac à puce Apple (demande Xcode complet)
#
# L'app est signée « ad hoc » (sans compte développeur) : au premier lancement, clic droit > Ouvrir.
set -euo pipefail

ICI="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ICI"

VERSION="0.0.1"
NOM="Tri-photo"
APP="build/$NOM.app"

if [ "${1:-}" = "universel" ]; then
    swift build -c release --arch arm64 --arch x86_64
    BINAIRE=".build/apple/Products/Release/TriPhotoMac"
else
    swift build -c release
    BINAIRE="$(swift build -c release --show-bin-path)/TriPhotoMac"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINAIRE" "$APP/Contents/MacOS/$NOM"

# Icône : Ressources/Icone-1024.png -> Tri-photo.icns
ICONSET="build/Icone.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for t in 16 32 128 256 512; do
    sips -z $t $t Ressources/Icone-1024.png --out "$ICONSET/icon_${t}x${t}.png" >/dev/null
    d=$((t * 2))
    sips -z $d $d Ressources/Icone-1024.png --out "$ICONSET/icon_${t}x${t}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/$NOM.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$NOM</string>
    <key>CFBundleDisplayName</key><string>$NOM</string>
    <key>CFBundleIdentifier</key><string>fr.hmtimings.triphoto</string>
    <key>CFBundleExecutable</key><string>$NOM</string>
    <key>CFBundleIconFile</key><string>$NOM</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleDevelopmentRegion</key><string>fr</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>HUGO</string>
</dict>
</plist>
PLIST

# Bureau synchronisé par iCloud : il ajoute des attributs Finder que codesign refuse (« detritus not allowed »).
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
echo "Prêt : $ICI/$APP"
