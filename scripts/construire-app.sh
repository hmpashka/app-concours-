#!/bin/bash
# Fabrique « Groom Pix.app » dans build/ (Mac seulement, avec Xcode ou les outils en ligne de commande).
#
#   ./scripts/construire-app.sh            app pour ce Mac
#   ./scripts/construire-app.sh universel  app pour Mac Intel ET Mac à puce Apple (demande Xcode complet)
#
# L'app est signée « ad hoc » (sans compte développeur) : au premier lancement, clic droit > Ouvrir.
set -euo pipefail

ICI="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ICI"

VERSION="0.0.1"
NOM="Groom Pix"
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

# Icône : Ressources/Icone-1024.png -> Groom Pix.icns
ICONSET="build/Icone.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for t in 16 32 128 256 512; do
    sips -z $t $t Ressources/Icone-1024.png --out "$ICONSET/icon_${t}x${t}.png" >/dev/null
    d=$((t * 2))
    sips -z $d $d Ressources/Icone-1024.png --out "$ICONSET/icon_${t}x${t}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/$NOM.icns"
rm -rf "$ICONSET"
# icônes des deux thèmes (le Dock prend celle du thème choisi)
cp Ressources/Icone-bleuOr.png Ressources/Icone-graphite.png "$APP/Contents/Resources/"
# sons du Mac dans l'app : les bulles de notification ne savent jouer que les sons rangés dans l'app
cp /System/Library/Sounds/*.aiff "$APP/Contents/Resources/" 2>/dev/null || true

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
    <key>NSHumanReadableCopyright</key><string>© HM Photographie · photographie des sports équestres</string>
    <!-- HM Timing (http sur le réseau du concours) et la page d'incrustation Horses & Competitions -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key><true/>
        <key>NSAllowsLocalNetworking</key><true/>
    </dict>
    <key>NSLocalNetworkUsageDescription</key><string>Groom Pix lit le chrono HM Timing et parle aux iPhone des pistes sur le réseau du concours.</string>
    <!-- les iPhone de l'app Piste trouvent le Mac tout seuls -->
    <key>NSBonjourServices</key>
    <array><string>_triphoto._tcp</string></array>
</dict>
</plist>
PLIST

# Bureau synchronisé par iCloud : il ajoute des attributs Finder que codesign refuse (« detritus not allowed »).
xattr -cr "$APP"
# Signée avec le certificat « Apple Development » de HUGO s'il est sur le Mac : macOS accepte alors les
# notifications et le trousseau ne redemande pas l'accès à chaque nouvelle version. Sinon signature locale.
IDENT="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/' || true)"
codesign --force --deep --sign "${IDENT:--}" "$APP"
echo "Signée avec : ${IDENT:-signature locale}"
echo "Prêt : $ICI/$APP"
