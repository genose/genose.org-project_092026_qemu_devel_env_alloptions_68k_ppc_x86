#!/bin/bash
# =============================================================================
# VM Assistant - Script d'Installation
# =============================================================================

echo "=========================================="
echo "  Installation de VM Assistant"
echo "=========================================="
echo ""

# Vérifier que nous sommes dans le bon répertoire
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Répertoire: $SCRIPT_DIR"
echo ""

# Vérifier que les fichiers existent
echo "Vérification des fichiers..."
FILES=("vm-assistant.sh" "vm-assistant-vm.sh" "vm-assistant-network.sh" "vm-assistant-macports.sh" "README.md")

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
chmod +x vm-assistant*.sh

# Créer le répertoire de configuration
echo ""
echo "Création du répertoire de configuration..."
mkdir -p "$HOME/.vm-assistant/vms" "$HOME/.vm-assistant/isos" "$HOME/.vm-assistant/disks" "$HOME/.vm-assistant/logs"

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

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "  ⚠️  Dépendances manquantes: ${MISSING[*]}"
    echo "  Installez-les avant de continuer."
else
    echo "  ✓ Toutes les dépendances de base sont présentes"
fi

echo ""
echo "=========================================="
echo "  Installation terminée!"
echo "=========================================="
echo ""
echo "Pour démarrer VM Assistant, exécutez:"
echo "  $SCRIPT_DIR/vm-assistant.sh"
echo ""
echo "Ou depuis n'importe quel répertoire:"
echo "  cd /tmp/volatile_hd && ./vm-assistant.sh"
echo ""
echo "Pour copier dans /usr/local/bin (optionnel):"
echo "  sudo cp $SCRIPT_DIR/vm-assistant.sh /usr/local/bin/vm-assistant"
echo "  Puis executez: vm-assistant"
echo ""
