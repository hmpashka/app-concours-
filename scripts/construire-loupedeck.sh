#!/bin/bash
# Fabrique et installe le module « Groom Pix » du logiciel Loupedeck (pour le Loupedeck CT).
#
#   ./scripts/construire-loupedeck.sh
#
# Il faut le logiciel Loupedeck (ou Logi Options+) installé : il contient le « Logi Plugin Service » qui fait
# tourner les modules. L'outil .NET de Microsoft est installé dans ~/.dotnet s'il manque (sans mot de passe).
# Le module est construit dans build/loupedeck à partir du gabarit officiel de Logitech (LogiPluginTool), puis
# nos fichiers (loupedeck/GroomPix/*.cs) remplacent l'exemple du gabarit.
set -euo pipefail

ICI="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"
export DOTNET_ROOT="$HOME/.dotnet"
export DOTNET_CLI_TELEMETRY_OPTOUT=1

# 1. Outil .NET (SDK 8 : compris par toutes les versions récentes du logiciel Loupedeck)
if ! dotnet --list-sdks 2>/dev/null | grep -q '^8\.'; then
    echo "→ Installation de .NET 8 dans ~/.dotnet…"
    curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    bash /tmp/dotnet-install.sh --channel 8.0 --install-dir "$HOME/.dotnet"
    unset DOTNET_ROOT_X64 || true
fi
# DOTNET_ROOT doit pointer sur l'installation trouvée (si .NET était déjà ailleurs)
if [ ! -x "$HOME/.dotnet/dotnet" ]; then export DOTNET_ROOT="$(dirname "$(readlink -f "$(command -v dotnet)")")"; fi
echo "→ .NET : $(dotnet --version)"

# 2. Outil de Logitech pour les modules
if ! command -v logiplugintool >/dev/null 2>&1; then
    echo "→ Installation de LogiPluginTool…"
    # 6.1.x : gabarit .NET 8 (les versions 6.4+ demandent .NET 10, refusé par le logiciel Loupedeck 6.2)
    dotnet tool install --global LogiPluginTool --version 6.1.4.22672
fi

# 3. Gabarit officiel + nos fichiers
CONSTR="$ICI/build/loupedeck"
rm -rf "$CONSTR"; mkdir -p "$CONSTR"
cd "$CONSTR"
logiplugintool generate GroomPix
PROJET="$(dirname "$(find "$CONSTR" -name 'GroomPixPlugin.csproj' | head -1)")"
[ -d "$PROJET" ] || { echo "Gabarit introuvable (GroomPixPlugin.csproj)"; exit 1; }
rm -rf "$PROJET/Actions"
cp "$ICI"/loupedeck/GroomPix/*.cs "$PROJET/"
# .NET 8 quelle que soit la version du gabarit
sed -i '' -E 's#<TargetFramework>net[0-9.]+</TargetFramework>#<TargetFramework>net8.0</TargetFramework>#' "$PROJET/GroomPixPlugin.csproj"
# nom affiché dans le logiciel Loupedeck
META="$(find "$PROJET" -name 'LoupedeckPackage.yaml' | head -1)"
if [ -n "$META" ]; then
    sed -i '' -E 's/^displayName:.*/displayName: Groom Pix/' "$META"
    sed -i '' -E 's/^description:.*/description: Pilote Groom Pix et affiche l etat du stand photo./' "$META"
    sed -i '' -E 's/^author:.*/author: HM Photographie/' "$META"
    grep -q 'LoupedeckCtFamily' "$META" || echo "ATTENTION : LoupedeckCtFamily absent de $META (appareils pris en charge)"
fi
# icône du module : celle de Groom Pix
ICONE="$(find "$PROJET" -name 'Icon256x256.png' | head -1)"
if [ -n "$ICONE" ] && [ -f "$ICI/Ressources/Icone-1024.png" ]; then
    sips -z 256 256 "$ICI/Ressources/Icone-1024.png" --out "$ICONE" >/dev/null
fi

mkdir -p "$HOME/Library/Application Support/Logi/LogiPluginService/Plugins"

# 4. Construction : le gabarit déclare lui-même le module au logiciel Loupedeck (fichier .link) et le recharge
cd "$PROJET"
dotnet build -c Release
echo
echo "✓ Module Groom Pix construit. Dans le logiciel Loupedeck : il apparaît dans la liste des actions"
echo "  (« Groom Pix · Écran tactile », « Groom Pix · Boutons », « Groom Pix · Molettes »)."
