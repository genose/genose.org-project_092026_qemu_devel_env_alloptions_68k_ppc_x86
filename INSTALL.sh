#!/bin/bash
# =============================================================================
# VM Manager - Script d'Installation
# Unified VM Management Tool for QEMU/UTM.app
# =============================================================================

echo "=========================================="
echo "  Installation de VM Manager"
echo "=========================================="
echo ""

# Vérifier que nous sommes dans le bon répertoire
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Répertoire: $SCRIPT_DIR"
echo ""

# Vérifier que les fichiers existent
# Note: VM Manager a consolidé tous les scripts en vm-manager.sh
# Les anciens scripts sont toujours supportés pour la compatibilité mais vm-manager.sh est le script principal

echo "Vérification des fichiers..."
FILES=("vm-manager.sh" "build_qemu.sh" "INSTALL.sh" "README.md")

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file"
    else
        echo "  ✗ $file - MANQUANT!"
        exit 1
    fi
done

# Rendre tous les scripts exécutables
echo ""
echo "Configuration des permissions..."
chmod +x vm-manager.sh build_qemu.sh INSTALL.sh

# Créer le répertoire de configuration
echo ""
echo "Création du répertoire de configuration..."
mkdir -p "$HOME/vm_assistant/vms" "$HOME/vm_assistant/isos" "$HOME/vm_assistant/images" "$HOME/vm_assistant/logs" "$HOME/vm_assistant/shares" "$HOME/vm_assistant/roms"

# Vérifier les dépendances de base
echo ""
echo "Vérification des dépendances de base..."

MISSING=()

# Vérifier bash
if ! command -v bash &> /dev/null; then
    MISSING+=("bash")
fi

# Vérifier sudo
if ! command -v sudo &> /dev/null; then
    MISSING+=("sudo")
fi

# Vérifier curl ou wget
if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
    MISSING+=("curl ou wget")
fi

# Vérifier qemu-img
if ! command -v qemu-img &> /dev/null; then
    MISSING+=("qemu-img")
fi

# Vérifier les dépendances de build pour vm-manager build
if ! command -v make &> /dev/null; then
    MISSING+=("make")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "  ⚠️  Dépendances manquantes: ${MISSING[*]}"
    echo "  Installez-les avant de continuer."
    echo ""
    echo "  Sur macOS (Homebrew):"
    echo "    brew install ninja pkg-config glib pixman sdl2 gtk+3 libslirp spice-protocol spice-gtk"
    echo ""
    echo "  Sur Debian/Ubuntu:"
    echo "    sudo apt-get install build-essential git ninja-build pkg-config python3-pip \\"
    echo "      libglib2.0-dev libpixman-1-dev libsdl2-dev libgtk-3-dev libvte-2.91-dev \\"
    echo "      libslirp-dev libbz2-dev liblzo2-dev libsnappy-dev libssh-dev \\"
    echo "      libusbredirhost-dev libcacard-dev libepoxy-dev libspice-server-dev libspice-protocol-dev"
    echo ""
else
    echo "  ✓ Toutes les dépendances de base sont présentes"
fi

echo ""
echo "=========================================="
echo "  Installation terminée!"
echo "=========================================="
echo ""
echo "VM Manager est maintenant installé et prêt à l'emploi."
echo ""
echo "Pour démarrer VM Manager, exécutez:"
echo "  $SCRIPT_DIR/vm-manager.sh"
echo ""
echo "Ou depuis n'importe quel répertoire (après installation):"
echo "  vm-manager"
echo ""
echo "Pour installer vm-manager dans /usr/local/bin (optionnel):"
echo "  sudo cp $SCRIPT_DIR/vm-manager.sh /usr/local/bin/vm-manager"
echo "  Puis exécutez: vm-manager"
echo ""
echo "Pour construire QEMU avec tous les cibles rétro:"
echo "  $SCRIPT_DIR/vm-manager.sh build all"
echo ""
echo "Pour démarrer le menu interactif:"
echo "  $SCRIPT_DIR/vm-manager.sh"
echo ""
echo "=== Documentation ==="
echo "Consultez README.md pour la documentation complète en anglais."
echo "Consultez NOTES.md pour les notes techniques et le dépannage."
echo "Consultez NOTES_OptionC.md pour le guide de débogage GDB/SSH/Netatalk."
echo ""

# Vérifier si on peut mettre à jour les scripts hérités
if [ -f "vm-assistant.sh" ]; then
    echo "Note: Les anciens scripts (vm-assistant.sh, etc.) sont toujours présents."
    echo "VM Manager (vm-manager.sh) est le script unifié qui combine toutes les fonctionnalités."
fi