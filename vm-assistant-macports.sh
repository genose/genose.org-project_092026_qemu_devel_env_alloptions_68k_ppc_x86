#!/bin/bash
# =============================================================================
# VM Assistant - Module MacPorts et Dépendances
# Vérification et installation des dépendances pour les VMs
# Utilise dirname $0 pour etre portable
# Version: 2.0.0
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="vm-assistant"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Liste des dépendances QEMU nécessaires
QEMU_DEPS=(
    "qemu"                    # QEMU principal
    "qemu-system-x86_64"      # x86_64
    "qemu-system-i386"       # i386
    "qemu-system-ppc"         # PowerPC
    "qemu-system-m68k"       # Motorola 68k
    "qemu-system-arm"        # ARM
    "qemu-system-sparc"       # SPARC
    "qemu-system-sparc64"     # SPARC64
)

# Autres dépendances
OTHER_DEPS=(
    "samba4"                  # Partage de fichiers Samba
    "netatalk"                # Partage AFP
    "XQuartz"                 # Affichage X11
)

# Vérifier si MacPorts est installé
check_macports() {
    if command -v port &> /dev/null; then
        return 0
    elif [ -d "/opt/local" ] && [ -f "/opt/local/bin/port" ]; then
        return 0
    else
        return 1
    fi
}

# Vérifier si Homebrew est installé
check_homebrew() {
    if command -v brew &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Vérifier l'installation complète
verify() {
    log_header "Vérification de l'installation"
    
    local missing_deps=()
    local found_deps=()
    
    # Vérifier MacPorts/Homebrew
    if check_macports; then
        log_info "MacPorts est installé"
        found_deps+=("MacPorts")
    else
        log_warn "MacPorts n'est pas installé"
        missing_deps+=("MacPorts")
    fi
    
    if check_homebrew; then
        log_info "Homebrew est installé"
        found_deps+=("Homebrew")
    else
        log_warn "Homebrew n'est pas installé"
        missing_deps+=("Homebrew")
    fi
    
    # Vérifier QEMU
    local qemu_installed=false
    for qemu_bin in "${QEMU_DEPS[@]}"; do
        if command -v "$qemu_bin" &> /dev/null; then
            log_info "Trouvé: $qemu_bin"
            qemu_installed=true
        fi
    done
    
    if ! $qemu_installed; then
        log_warn "Aucune version de QEMU trouvée"
        missing_deps+=("QEMU")
    fi
    
    # Vérifier les autres dépendances
    for dep in "${OTHER_DEPS[@]}"; do
        case $dep in
            "samba4")
                if command -v smbd &> /dev/null; then
                    log_info "Samba est installé"
                else
                    log_warn "Samba n'est pas installé"
                    missing_deps+=("Samba")
                fi
                ;;
            "netatalk")
                if command -v afpd &> /dev/null; then
                    log_info "Netatalk est installé"
                else
                    log_warn "Netatalk n'est pas installé"
                    missing_deps+=("Netatalk")
                fi
                ;;
            "XQuartz")
                if [ -d "/Applications/Utilities/XQuartz.app" ]; then
                    log_info "XQuartz est installé"
                else
                    log_warn "XQuartz n'est pas installé"
                    missing_deps+=("XQuartz")
                fi
                ;;
        esac
    done
    
    # Vérifier UTM.app
    if [ -d "/Applications/UTM.app" ]; then
        log_info "UTM.app est installé"
    else
        log_warn "UTM.app n'est pas installé"
        missing_deps+=("UTM.app")
    fi
    
    # Résumé
    echo ""
    if [ ${#missing_deps[@]} -eq 0 ]; then
        log_info "Toutes les dépendances sont installées!"
        return 0
    else
        log_warn "Dépendances manquantes: ${missing_deps[*]}"
        return 1
    fi
}

# Installer MacPorts
install_macports() {
    log_header "Installation de MacPorts"
    
    if check_macports; then
        log_info "MacPorts est déjà installé"
        return 0
    fi
    
    log_info "Téléchargement de MacPorts..."
    local macports_url="https://distfiles.macports.org/MacPorts/MacPorts-2.8.1.tar.gz"
    local macports_archive="/tmp/MacPorts.tar.gz"
    
    curl -L -o "$macports_archive" "$macports_url" -# || {
        log_error "Échec du téléchargement de MacPorts"
        return 1
    }
    
    log_info "Installation de MacPorts..."
    cd /tmp
    tar xzf "$macports_archive"
    cd MacPorts-*
    ./configure && make && sudo make install || {
        log_error "Échec de l'installation de MacPorts"
        return 1
    }
    
    # Initialiser MacPorts
    sudo /opt/local/bin/port selfupdate || {
        log_error "Échec de la mise à jour de MacPorts"
        return 1
    }
    
    log_info "MacPorts installé avec succès!"
    log_info "Pensez à ajouter au PATH: export PATH=/opt/local/bin:/opt/local/sbin:\$PATH"
    
    return 0
}

# Mettre à jour MacPorts
update_macports() {
    log_header "Mise à jour de MacPorts"
    
    if ! check_macports; then
        log_error "MacPorts n'est pas installé"
        return 1
    fi
    
    log_info "Mise à jour de MacPorts..."
    sudo port -v selfupdate || {
        log_error "Échec de la mise à jour"
        return 1
    }
    
    log_info "MacPorts mis à jour"
    return 0
}

# Installer toutes les dépendances
install_deps() {
    log_header "Installation des dépendances pour les VMs"
    
    if ! check_macports; then
        log_error "MacPorts n'est pas installé. Installez-le d'abord."
        read -p "Voulez-vous installer MacPorts maintenant? (y/N): " install_choice
        if [ "$install_choice" = "y" ]; then
            install_macports || return 1
        else
            return 1
        fi
    fi
    
    # Installer QEMU et tous les architectures
    local qemu_ports=(
        "qemu"
        "qemu-system-x86_64"
        "qemu-system-i386"
        "qemu-system-ppc"
        "qemu-system-m68k"
        "qemu-system-arm"
        "qemu-system-sparc"
        "qemu-system-sparc64"
    )
    
    log_info "Installation des dépendances QEMU..."
    sudo port install ${qemu_ports[*]} || {
        log_error "Échec de l'installation de QEMU"
        return 1
    }
    
    # Installer Samba
    log_info "Installation de Samba..."
    sudo port install samba4 || {
        log_error "Échec de l'installation de Samba"
        return 1
    }
    
    # Installer Netatalk
    log_info "Installation de Netatalk..."
    sudo port install netatalk || {
        log_error "Échec de l'installation de Netatalk"
        return 1
    }
    
    log_info "Toutes les dépendances MacPorts installées!"
    
    # Vérifier XQuartz
    if [ ! -d "/Applications/Utilities/XQuartz.app" ]; then
        log_warn "XQuartz n'est pas installé"
        log_info "Téléchargez depuis: https://www.xquartz.org"
    fi
    
    return 0
}

# Main
case "${1:-help}" in
    verify) verify ;;
    install) install_macports ;;
    update) update_macports ;;
    install-deps) install_deps ;;
    help|*)
        echo "Usage: $0 {verify|install|update|install-deps}"
        echo ""
        echo "Options:"
        echo "  verify       - Vérifier l'installation complète"
        echo "  install      - Installer MacPorts"
        echo "  update       - Mettre à jour MacPorts"
        echo "  install-deps - Installer toutes les dépendances pour les VMs"
        ;;
esac
