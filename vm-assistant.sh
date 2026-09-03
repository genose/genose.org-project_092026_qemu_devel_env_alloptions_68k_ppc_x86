#!/bin/bash

# VM Assistant - Script Principal
# Ce script est le point d'entree pour la gestion des VMs
# Version: 2.0 - Avec support complet UTM.app, multi-architectures, GDB, etc.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_header() { 
    echo -e "\n${BLUE}============================${NC}"
    echo "$1"
    echo -e "${BLUE}============================${NC}"
}

detect_dependencies() {
    # Detection de UTM
    if [ -d "/Applications/UTM.app" ]; then
        UTM_INSTALLED=true
    else
        UTM_INSTALLED=false
    fi
    
    # Detection de XQuartz
    if [ -d "/Applications/Utilities/XQuartz.app" ]; then
        XQUARTZ_INSTALLED=true
    else
        XQUARTZ_INSTALLED=false
    fi
    
    # Detection de MacPorts
    if command -v port &>/dev/null; then
        MACPORTS_INSTALLED=true
    else
        MACPORTS_INSTALLED=false
    fi
    
    # Detection de Homebrew
    if command -v brew &>/dev/null; then
        HOMEBREW_INSTALLED=true
    else
        HOMEBREW_INSTALLED=false
    fi
    
    # Detection des binaires QEMU
    QEMU_ARCHS=()
    for arch in ppc x86_64 m68k arm sparc aarch64 i386; do
        if command -v "qemu-system-$arch" &>/dev/null; then
            QEMU_ARCHS+=("$arch")
        fi
    done
}

detect_dependencies

show_main_menu() {
    while true; do
        clear || echo ""
        log_header "VM Assistant - Menu Principal"
        echo ""
        echo "Gestion des Machines Virtuelles:"
        echo "  [1] Verification de l'installation"
        echo "  [2] Installer/Configurer les dependances"
        echo "  [3] Configurer XQuartz et le RAMDISK"
        echo "  [4] Configurer les partages reseau (Samba/Netatalk)"
        echo "  [5] Gestion des ISOs"
        echo "  [6] Gestion des disques virtuels"
        echo "  [7] Gestion des Machines Virtuelles (QEMU/UTM)"
        echo "  [8] Configuration du debugging (GDB)"
        echo "  [9] Configuration avancee"
        echo ""
        echo "  [Q] Quitter"
        echo ""
        
        # Status
        [ "$UTM_INSTALLED" = true ] && echo "  ${GREEN}✓${NC} UTM.app installe" || echo "  ${RED}✗${NC} UTM.app non installe"
        [ "$XQUARTZ_INSTALLED" = true ] && echo "  ${GREEN}✓${NC} XQuartz installe" || echo "  ${RED}✗${NC} XQuartz non installe"
        [ "$MACPORTS_INSTALLED" = true ] && echo "  ${GREEN}✓${NC} MacPorts installe" || echo "  ${RED}✗${NC} MacPorts non installe"
        [ "$HOMEBREW_INSTALLED" = true ] && echo "  ${GREEN}✓${NC} Homebrew installe" || echo "  ${RED}✗${NC} Homebrew non installe"
        if [ ${#QEMU_ARCHS[@]} -gt 0 ]; then
            echo "  ${GREEN}✓${NC} QEMU disponible pour: ${QEMU_ARCHS[*]}"
        else
            echo "  ${RED}✗${NC} Aucun QEMU installe"
        fi
        echo ""
        
        read -p "Selectionnez une option [Q]: " choice
        choice=${choice:-Q}
        
        case "$choice" in
            1)
                # Verification de l'installation via le menu VM
                "$SCRIPT_DIR/vm-assistant-vm.sh" menu
                ;;
            2)
                # Installer/Configurer les dependances
                if [ "$MACPORTS_INSTALLED" = true ]; then
                    "$SCRIPT_DIR/vm-assistant-macports.sh"
                elif [ "$HOMEBREW_INSTALLED" = true ]; then
                    log_info "Utilisez Homebrew: brew install qemu samba netatalk"
                    read -p "Appuyez sur Entree..." 
                else
                    log_error "Aucun gestionnaire de paquets detecte (MacPorts ou Homebrew)"
                    log_info "Installez MacPorts depuis: https://www.macports.org/"
                    log_info "Ou Homebrew depuis: https://brew.sh/"
                    read -p "Appuyez sur Entree..." 
                fi
                ;;
            3)
                # Configurer XQuartz et RAMDISK
                log_header "Configuration de XQuartz et du RAMDISK"
                
                if [ "$XQUARTZ_INSTALLED" = false ]; then
                    log_info "Installation de XQuartz..."
                    log_info "Telechargez depuis: https://www.xquartz.org"
                    read -p "XQuartz installe? [y/N]: " xquartz_done
                    if [ "$xquartz_done" = "y" ]; then
                        XQUARTZ_INSTALLED=true
                    fi
                fi
                
                if [ "$XQUARTZ_INSTALLED" = true ]; then
                    log_info "XQuartz est installe"
                    
                    # Verifier et configurer le RAMDISK
                    SHARE_DIR="${HOME}/vm_assistant/shares"
                    if [ -d "$SHARE_DIR" ]; then
                        log_info "RAMDISK $SHARE_DIR existe deja"
                    else
                        log_info "Creation du RAMDISK $SHARE_DIR"
                        mkdir -p "$SHARE_DIR"
                        chmod 1777 "$SHARE_DIR"
                        log_info "RAMDISK configure avec permissions 1777"
                    fi
                    
                    # Ajouter le partage pour QEMU
                    log_info "Le repertoire $SHARE_DIR sera utilise pour le partage avec les VMs"
                fi
                
                read -p "Appuyez sur Entree pour continuer..." 
                ;;
            4)
                # Configurer Samba et Netatalk
                "$SCRIPT_DIR/vm-assistant-network.sh"
                ;;
            5)
                # Gestion des ISOs
                log_header "Gestion des ISOs"
                echo ""
                echo "  [1] Lister les ISOs disponibles"
                echo "  [B] Retour"
                read -p "Selection: " iso_choice
                case "$iso_choice" in
                    1)
                        if [ -f "$SCRIPT_DIR/vm-assistant-vm.sh" ]; then
                            "$SCRIPT_DIR/vm-assistant-vm.sh" list
                        fi
                        ;;
                esac
                read -p "Appuyez sur Entree pour continuer..." 
                ;;
            6)
                # Gestion des disques
                log_header "Gestion des disques virtuels"
                echo ""
                echo "  [1] Creer un nouveau disque"
                echo "  [2] Lister les disques"
                echo "  [B] Retour"
                read -p "Selection: " disk_choice
                case "$disk_choice" in
                    1)
                        read -p "Nom de la VM pour le disque: " vm_name
                        read -p "Taille du disque [20G]: " disk_size
                        disk_size=${disk_size:-20G}
                        mkdir -p "$HOME/vm_assistant/vms"
                        qemu-img create -f qcow2 "$HOME/vm_assistant/vms/${vm_name:-new_vm}.qcow2" "$disk_size" || \
                            log_error "Echec de la creation du disque"
                        log_info "Disque cree: $HOME/vm_assistant/vms/${vm_name:-new_vm}.qcow2"
                        ;;
                    2)
                        echo "Disques dans $HOME/vm_assistant/vms/:"
                        ls -lh "$HOME/vm_assistant/vms/" 2>/dev/null || echo "  Aucun disque trouve"
                        echo ""
                        echo "Disques dans $SCRIPT_DIR/:"
                        ls -lh "$SCRIPT_DIR/*.qcow2" "$SCRIPT_DIR/*.img" "$SCRIPT_DIR/*.raw" 2>/dev/null || echo "  Aucun disque trouve"
                        ;;
                esac
                read -p "Appuyez sur Entree pour continuer..." 
                ;;
            7)
                # Gestion des VMs
                "$SCRIPT_DIR/vm-assistant-vm.sh" menu
                ;;
            8)
                # Configuration du debugging GDB
                log_header "Configuration du debugging GDB"
                echo ""
                echo "Pour debugger une application dans une VM:"
                echo ""
                echo "1. Demarrez la VM avec l'option -serial stdio ou -serial tcp::1234,server,nowait"
                echo "2. Dans la VM, installez GDB si necessaire"
                echo "3. Connectez-vous depuis l'hote avec:"
                echo "   gdb-multiarch /path/to/program"
                echo "   (gdb) target remote :1234"
                echo ""
                echo "Pour PowerPC avec QEMU:"
                echo "  qemu-system-ppc -gdb tcp::1234 -S ..."
                echo "  Puis: gdb-multiarch -ex 'target remote :1234' -ex 'continue'"
                echo ""
                
                # Verifier si gdb est installe
                if command -v gdb &>/dev/null; then
                    log_info "gdb est installe"
                else
                    log_info "Pour installer gdb avec MacPorts: sudo port install gdb"
                    log_info "Ou avec Homebrew: brew install gdb"
                fi
                
                if command -v gdb-multiarch &>/dev/null; then
                    log_info "gdb-multiarch est installe"
                else
                    log_info "Pour installer gdb-multiarch: sudo port install gdb-multiarch"
                fi
                
                read -p "Appuyez sur Entree pour continuer..." 
                ;;
            9)
                # Configuration avancee
                log_header "Configuration Avancee"
                echo ""
                echo "  [1] Sauvegarder les configurations"
                echo "  [2] Restaurer les configurations"
                echo "  [B] Retour"
                read -p "Selection: " adv_choice
                case "$adv_choice" in
                    1)
                        tar -czf "$SCRIPT_DIR/vm-assistant-backup-$(date +%Y%m%d).tar.gz" "$HOME/vm_assistant" 2>/dev/null || \
                            log_error "Echec de la sauvegarde"
                        log_info "Sauvegarde creee: $SCRIPT_DIR/vm-assistant-backup-$(date +%Y%m%d).tar.gz"
                        ;;
                    2)
                        ls "$SCRIPT_DIR/vm-assistant-backup-*.tar.gz" 2>/dev/null || \
                            echo "Aucune sauvegarde trouvee"
                        read -p "Nom de la sauvegarde a restaurer: " backup_file
                        if [ -f "$SCRIPT_DIR/$backup_file" ]; then
                            rm -rf "$HOME/vm_assistant"
                            tar -xzf "$SCRIPT_DIR/$backup_file" -C "$HOME" || \
                                log_error "Echec de la restauration"
                            log_info "Sauvegarde restauree"
                        else
                            log_error "Sauvegarde non trouvee: $backup_file"
                        fi
                        ;;
                esac
                read -p "Appuyez sur Entree pour continuer..." 
                ;;
            Q|q)
                log_info "Au revoir!"
                exit 0
                ;;
            *)
                echo "Option non valide"
                ;;
        esac
        
        echo ""
    done
}

# Menu principal
show_main_menu
