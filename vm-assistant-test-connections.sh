#!/bin/bash

# VM Assistant - Testeur de connexions aux partages
# Version: 1.0
# Teste les connexions Samba, Netatalk et SSH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-assistant-vm.sh" 2>/dev/null || source "$SCRIPT_DIR/vm-assistant-config.sh" 2>/dev/null

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_header() { echo -e "\n${BLUE}============================${NC}"; echo "$1"; echo -e "${BLUE}============================${NC}"; }

test_samba_connection() {
    local host="$1"
    local share="$2"
    local username="$3"
    local password="$4"
    
    log_info "Test de connexion Samba: smb://$host/$share"
    
    if ! command -v smbutil &>/dev/null; then
        log_error "smbutil non trouve. Installez samba client."
        return 1
    fi
    
    # Tester la connection
    if smbutil statshares -a "$username" -p "$password" "//$host" 2>/dev/null | grep -q "$share"; then
        log_info "  ✓ Connexion Samba reussie"
        
        # Tester le montage
        local mount_point="/tmp/vm_test_samba_$$"
        mkdir -p "$mount_point"
        if mount_smbfs -N -d 777 "//${username}@${host}/${share}" "$mount_point" 2>/dev/null; then
            log_info "  ✓ Montage Samba reussi"
            ls -la "$mount_point" | head -5
            umount "$mount_point" 2>/dev/null || true
            rmdir "$mount_point" 2>/dev/null || true
            return 0
        else
            log_warn "  ✗ Montage Samba echoue (mais connexion OK)"
            rmdir "$mount_point" 2>/dev/null || true
            return 1
        fi
    else
        log_error "  ✗ Connexion Samba echouee"
        return 1
    fi
}

test_netatalk_connection() {
    local host="$1"
    local share="$2"
    
    log_info "Test de connexion Netatalk (AppleShare): afp://$host/$share"
    
    if ! command -v afp &>/dev/null; then
        log_error "Client AFP non trouve. Utilisez: open afp://$host/$share"
        return 1
    fi
    
    # Tester avec mount_afp
    if command -v mount_afp &>/dev/null; then
        local mount_point="/tmp/vm_test_afp_$$"
        mkdir -p "$mount_point"
        if mount_afp "afp://$host/$share" "$mount_point" 2>/dev/null; then
            log_info "  ✓ Connexion Netatalk reussie"
            ls -la "$mount_point" | head -5
            umount "$mount_point" 2>/dev/null || true
            rmdir "$mount_point" 2>/dev/null || true
            return 0
        else
            log_warn "  ✗ Montage Netatalk echoue"
            rmdir "$mount_point" 2>/dev/null || true
            return 1
        fi
    else
        log_info "  Essayez: open afp://$host/$share"
        return 0
    fi
}

test_ssh_connection() {
    local host="$1"
    local port="$2"
    
    log_info "Test de connexion SSH: $host:$port"
    
    if ! command -v ssh &>/dev/null; then
        log_error "SSH client non trouve"
        return 1
    fi
    
    # Tester la connexion
    if ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no -p "$port" "test@$host" echo "SSH OK" 2>/dev/null; then
        log_info "  ✓ Connexion SSH reussie"
        return 0
    else
        log_warn "  ✗ Connexion SSH echouee (ou authentification requise)"
        log_info "  Essayez: ssh -p $port user@$host"
        return 1
    fi
}

test_gdb_connection() {
    local host="$1"
    local port="$2"
    
    log_info "Test de connexion GDB: localhost:$port"
    
    if ! command -v gdb &>/dev/null && ! command -v ggdb &>/dev/null; then
        log_error "GDB non trouve"
        return 1
    fi
    
    # Vérifier si le port est en écoute
    if nc -z localhost "$port" 2>/dev/null; then
        log_info "  ✓ Port GDB $port est ouvert"
        log_info "  Connectez-vous avec: gdb-multiarch -ex 'target remote localhost:$port'"
        return 0
    else
        log_warn "  ✗ Port GDB $port n'est pas ouvert"
        return 1
    fi
}

test_local_share() {
    local share_path="$1"
    
    log_info "Test du partage local: $share_path"
    
    if [ -d "$share_path" ]; then
        log_info "  ✓ Repertoire existe"
        log_info "  Contenu:"
        ls -la "$share_path" | head -10
        return 0
    else
        log_error "  ✗ Repertoire introuvable"
        return 1
    fi
}

main() {
    log_header "Testeur de connexions VM Assistant"
    
    detect_netatalk
    detect_gdb
    
    echo ""
    echo "  [1] Tester la connexion Samba"
    echo "  [2] Tester la connexion Netatalk"
    echo "  [3] Tester la connexion SSH"
    echo "  [4] Tester la connexion GDB"
    echo "  [5] Tester le partage local"
    echo "  [6] Tester tout"
    echo "  [0] Quitter"
    echo ""
    read -p "Selectionnez une option: " choice
    
    case "$choice" in
        1)
            read -p "Host Samba: " samba_host
            read -p "Partage Samba: " samba_share
            read -p "Utilisateur Samba: " samba_user
            read -p "Mot de passe Samba (optionnel): " -s samba_pass
            echo ""
            test_samba_connection "$samba_host" "$samba_share" "$samba_user" "$samba_pass"
            ;;
        2)
            read -p "Host Netatalk: " afp_host
            read -p "Partage Netatalk: " afp_share
            test_netatalk_connection "$afp_host" "$afp_share"
            ;;
        3)
            read -p "Host SSH: " ssh_host
            read -p "Port SSH: " ssh_port
            test_ssh_connection "$ssh_host" "${ssh_port:-22}"
            ;;
        4)
            read -p "Port GDB: " gdb_port
            test_gdb_connection "localhost" "${gdb_port:-1234}"
            ;;
        5)
            read -p "Chemin du partage local: " local_path
            test_local_share "${local_path:-/tmp/volatile_hd}"
            ;;
        6)
            echo ""
            log_info "Test du partage local..."
            test_local_share "/tmp/volatile_hd"
            echo ""
            log_info "Test de Netatalk..."
            test_netatalk_connection "localhost" "VM_Test"
            echo ""
            log_info "Test de Samba..."
            test_samba_connection "localhost" "VM_Shares" "guest" ""
            echo ""
            log_info "Test de SSH sur port 2222..."
            test_ssh_connection "localhost" "2222"
            echo ""
            log_info "Test de GDB sur port 1234..."
            test_gdb_connection "localhost" "1234"
            ;;
        *)
            log_info "Au revoir!"
            exit 0
            ;;
    esac
    
    read -p "Appuyez sur Entree pour continuer..."
    main
}

# Initialisation
init_directories 2>/dev/null

# Démarrer le menu
main
