#!/bin/bash
# =============================================================================
# VM Assistant - Module Reseau et Partages
# Gestion de Samba, Netatalk, XQuartz et RAMDISK
# Utilise dirname $0 pour etre portable
# Version: 2.0.0 - Corrigé pour macOS avec bonnes pratiques
# =============================================================================

# Obtenir le repertoire du script en cours
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="vm-assistant"
CONFIG_DIR="$HOME/.${SCRIPT_NAME}"
VM_DIR="$CONFIG_DIR/vms"
ISO_DIR="$CONFIG_DIR/isos"
DISK_DIR="$CONFIG_DIR/disks"
SHARE_DIR="/tmp/volatile_hd"

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

# Fonction pour trouver le binaire smbd
find_smbd_bin() {
    if command -v smbd &> /dev/null; then
        echo "$(command -v smbd)"
    elif [ -x "/opt/local/sbin/smbd" ]; then
        echo "/opt/local/sbin/smbd"
    elif [ -x "/usr/local/sbin/smbd" ]; then
        echo "/usr/local/sbin/smbd"
    else
        echo ""
    fi
}

# Fonction pour trouver le binaire nmbd
find_nmbd_bin() {
    if command -v nmbd &> /dev/null; then
        echo "$(command -v nmbd)"
    elif [ -x "/opt/local/sbin/nmbd" ]; then
        echo "/opt/local/sbin/nmbd"
    elif [ -x "/usr/local/sbin/nmbd" ]; then
        echo "/usr/local/sbin/nmbd"
    else
        echo ""
    fi
}

# Fonction pour trouver le binaire afpd
find_afpd_bin() {
    if command -v afpd &> /dev/null; then
        echo "$(command -v afpd)"
    elif [ -x "/opt/local/sbin/afpd" ]; then
        echo "/opt/local/sbin/afpd"
    elif [ -x "/usr/local/sbin/afpd" ]; then
        echo "/usr/local/sbin/afpd"
    else
        echo ""
    fi
}

# Fonction pour créer un répertoire avec les bonnes permissions
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" 2>/dev/null || sudo mkdir -p "$dir" 2>/dev/null
        sudo chown "$(whoami):$(id -gn)" "$dir"
        sudo chmod 775 "$dir"
    fi
    if [ ! -d "$dir" ]; then
        log_error "Impossible de créer: $dir"
        return 1
    fi
    return 0
}

# Fonction pour obtenir l'adresse IP
get_ip_address() {
    local ip=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)
    echo "${ip:-127.0.0.1}"
}

# Configuration de Samba
configure_samba() {
    log_header "Configuration de Samba"

    if ! command -v smbd &> /dev/null; then
        log_error "Samba non installé. Installez via MacPorts: sudo port install samba4"
        return 1
    fi

    local current_user=$(whoami)
    local samba_config=""

    # Gestion du smbd système
    if pgrep -x "smbd" &> /dev/null; then
        local system_smbd=$(ps aux | grep "[s]mbd" | grep -v grep | head -1 | awk '{print $NF}')
        if [[ "$system_smbd" == "/usr/sbin/smbd"* ]]; then
            log_info "smbd système détecté, désactivation..."
            if [ -f "/System/Library/LaunchDaemons/com.apple.smbd.plist" ]; then
                sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.smbd.plist 2>/dev/null || true
                sleep 1
            fi
            sudo killall /usr/sbin/smbd 2>/dev/null || true
            sleep 1
            samba_config="$HOME/.vm-assistant/samba/smb.conf"
            ensure_dir "$(dirname "$samba_config")"
            log_info "Service Samba système désactivé"
        fi
    fi

    # Déterminer le chemin de configuration
    if [ -z "$samba_config" ]; then
        if [ -d "/opt/local/etc/samba" ] && [ -w "/opt/local/etc/samba" ]; then
            samba_config="/opt/local/etc/samba/smb.conf"
        elif [ -d "/usr/local/etc/samba" ] && [ -w "/usr/local/etc/samba" ]; then
            samba_config="/usr/local/etc/samba/smb.conf"
        else
            samba_config="$HOME/.vm-assistant/samba/smb.conf"
            ensure_dir "$(dirname "$samba_config")"
        fi
    fi

    # Sauvegarder la config existante
    if [ -f "$samba_config" ]; then
        cp "$samba_config" "${samba_config}.bak.$(date +%Y%m%d%H%M%S)"
    fi

    ensure_dir "$(dirname "$samba_config")"

    # Configuration du répertoire private Samba
    local samba_private_dir="/tmp/samba_private"
    ensure_dir "$samba_private_dir"
    sudo chmod 1777 "$samba_private_dir"
    sudo chown root:wheel "$samba_private_dir"
    log_info "Répertoire Samba private: $samba_private_dir"

    # Lien symbolique pour Homebrew Samba
    if [ -d "/usr/local/Cellar/samba" ]; then
        local samba_version=$(ls /usr/local/Cellar/samba/ | grep -E '^[0-9]+\.[0-9]+' | sort -V | tail -1)
        if [ -n "$samba_version" ]; then
            local homebrew_samba_private="/usr/local/Cellar/samba/${samba_version}/private"
            if [ ! -L "$homebrew_samba_private" ] && [ ! -d "$homebrew_samba_private" ]; then
                sudo mkdir -p "$(dirname "$homebrew_samba_private")"
                sudo ln -sf "$samba_private_dir" "$homebrew_samba_private"
                log_info "Lien symbolique: $homebrew_samba_private -> $samba_private_dir"
            fi
        fi
    fi

    # Créer la configuration Samba (méthode sécurisée)
    local netbios_name=$(hostname | cut -c1-15)
    local temp_smb=$(mktemp)

    cat > "$temp_smb" << SMBCONF
[global]
   workgroup = WORKGROUP
   server string = VM Assistant Samba Server
   netbios name = $netbios_name
   security = user
   map to guest = bad user
   guest account = $current_user
   dns proxy = no
   private dir = $samba_private_dir
   lock directory = $samba_private_dir
   pid directory = $samba_private_dir
   log file = $samba_private_dir/log.smbd

[VM_Shares]
   comment = Partage VM Assistant
   path = $SHARE_DIR
   browsable = yes
   read only = no
   guest ok = yes
   create mask = 0777
   directory mask = 0777
   force user = $current_user

[VM_Disks]
   comment = Disques des VMs
   path = $DISK_DIR
   browsable = yes
   read only = no
   guest ok = yes
   create mask = 0777
   directory mask = 0777

[VM_ISOs]
   comment = ISOs des VMs
   path = $ISO_DIR
   browsable = yes
   read only = yes
   guest ok = yes
SMBCONF

    cp "$temp_smb" "$samba_config"
    rm "$temp_smb"
    log_info "Configuration Samba: $samba_config"

    # Validation
    ensure_dir "$SHARE_DIR"
    ensure_dir "$DISK_DIR"
    ensure_dir "$ISO_DIR"

    if command -v testparm &> /dev/null; then
        if testparm "$samba_config" 2>/dev/null; then
            log_info "Configuration Samba valide"
        else
            log_error "Configuration Samba invalide"
            log_info "Executez: testparm $samba_config"
            return 1
        fi
    fi

    # smbpasswd
    local smbpasswd_file=""
    if [ -d "/opt/local/private" ]; then
        smbpasswd_file="/opt/local/private/smbpasswd"
    elif [ -d "/usr/local/private" ]; then
        smbpasswd_file="/usr/local/private/smbpasswd"
    else
        smbpasswd_file="$HOME/.vm-assistant/private/smbpasswd"
        ensure_dir "$(dirname "$smbpasswd_file")"
    fi

    if [ ! -f "$smbpasswd_file" ]; then
        sudo touch "$smbpasswd_file"
        sudo chmod 600 "$smbpasswd_file"
    fi

    if command -v pdbedit &> /dev/null; then
        if ! sudo pdbedit -L 2>/dev/null | grep -q "$current_user"; then
            local temp_pass=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
            if (echo "$current_user"; echo "$temp_pass") | sudo smbpasswd -a -s -n "$current_user" 2>/dev/null; then
                log_info "Utilisateur $current_user ajouté à Samba"
            else
                log_warn "Ajoutez manuellement: sudo smbpasswd -a $current_user"
            fi
        fi
    fi

    # Démarrer Samba
    local samba_launchd_plist=""
    if [ -f "/Library/LaunchDaemons/org.macports.smbd.plist" ]; then
        samba_launchd_plist="/Library/LaunchDaemons/org.macports.smbd.plist"
    elif [ -f "/Library/LaunchDaemons/org.samba.smbd.plist" ]; then
        samba_launchd_plist="/Library/LaunchDaemons/org.samba.smbd.plist"
    fi

    if [ -n "$samba_launchd_plist" ]; then
        log_info "Utilisation de launchd pour Samba..."
        if launchctl print "system/org.macports.smbd" &> /dev/null || \
           launchctl print "system/org.samba.smbd" &> /dev/null; then
            sudo launchctl unload "$samba_launchd_plist" 2>/dev/null
            sleep 1
        fi
        sudo launchctl load "$samba_launchd_plist"
        log_info "Samba démarré via launchd"
    else
        local smbd_bin=$(find_smbd_bin)
        local nmbd_bin=$(find_nmbd_bin)
        if [ -z "$smbd_bin" ]; then
            log_error "smbd introuvable"
            return 1
        fi
        log_info "Lancement manuel de Samba..."
        if pgrep -x "smbd" &> /dev/null; then
            sudo killall smbd 2>/dev/null || true
            sudo killall nmbd 2>/dev/null || true
            sleep 1
        fi
        sudo "$smbd_bin" -D -s "$samba_config" -l "$samba_private_dir/log_smbd.log" -p "$samba_private_dir/smbd.pid" &
        if [ -n "$nmbd_bin" ]; then
            sudo "$nmbd_bin" -D -l "$samba_private_dir/log_nmbd.log" -p "$samba_private_dir/nmbd.pid" &
        fi
        log_info "Samba démarré manuellement"
    fi

    sleep 2
    local ip_address=$(get_ip_address)
    log_info "Accès Samba: smb://${ip_address}/VM_Shares"
    return 0
}

# Configuration de Netatalk
configure_netatalk() {
    log_header "Configuration de Netatalk (AFP)"

    if ! command -v afpd &> /dev/null; then
        log_error "Netatalk non installé. Installez via MacPorts: sudo port install netatalk"
        return 1
    fi

    local current_user=$(whoami)
    local netatalk_config=""

    if [ -d "/opt/local/etc/netatalk" ]; then
        netatalk_config="/opt/local/etc/netatalk/afpd.conf"
    elif [ -d "/usr/local/etc/netatalk" ]; then
        netatalk_config="/usr/local/etc/netatalk/afpd.conf"
    else
        netatalk_config="$HOME/.vm-assistant/netatalk/afpd.conf"
        ensure_dir "$(dirname "$netatalk_config")"
    fi

    if [ -f "$netatalk_config" ]; then
        cp "$netatalk_config" "${netatalk_config}.bak.$(date +%Y%m%d%H%M%S)"
    fi

    ensure_dir "$(dirname "$netatalk_config")"

    # Créer la configuration Netatalk
    local temp_netatalk=$(mktemp)
    cat > "$temp_netatalk" << NETATALKCONF
[Global]
   mimic model = RackMac
   vol preset = VM_Shares
   max connections = 10

[VM_Shares]
   path = $SHARE_DIR
   cnidscheme = dbd
   vol size limit = 0
   valid users = $current_user
   rwlist = $current_user

[VM_Disks]
   path = $DISK_DIR
   cnidscheme = dbd
   vol size limit = 0
   valid users = $current_user
   rwlist = $current_user

[VM_ISOs]
   path = $ISO_DIR
   cnidscheme = dbd
   vol size limit = 0
   valid users = $current_user
   rolist = $current_user
NETATALKCONF

    cp "$temp_netatalk" "$netatalk_config"
    rm "$temp_netatalk"

    # AppleVolumes.default
    local apple_volumes_dir="$(dirname "$netatalk_config")"
    local apple_volumes="$apple_volumes_dir/AppleVolumes.default"
    ensure_dir "$apple_volumes_dir"

    cat > "$apple_volumes" << APPLEVOL
$SHARE_DIR "VM RAMDISK" options:usedots,noadouble
$DISK_DIR "VM Disques" options:usedots,noadouble
$ISO_DIR "VM ISOs" options:usedots,noadouble,ro
APPLEVOL

    log_info "Configuration Netatalk: $netatalk_config"

    # Démarrer Netatalk
    local netatalk_launchd_plist=""
    if [ -f "/Library/LaunchDaemons/org.macports.afpd.plist" ]; then
        netatalk_launchd_plist="/Library/LaunchDaemons/org.macports.afpd.plist"
    elif [ -f "/Library/LaunchDaemons/org.netatalk.afpd.plist" ]; then
        netatalk_launchd_plist="/Library/LaunchDaemons/org.netatalk.afpd.plist"
    fi

    if [ -n "$netatalk_launchd_plist" ]; then
        log_info "Utilisation de launchd pour Netatalk..."
        if launchctl print "system/org.macports.afpd" &> /dev/null || \
           launchctl print "system/org.netatalk.afpd" &> /dev/null; then
            sudo launchctl unload "$netatalk_launchd_plist" 2>/dev/null
            sleep 1
        fi
        sudo launchctl load "$netatalk_launchd_plist"
        log_info "Netatalk démarré via launchd"
    else
        local afpd_bin=$(find_afpd_bin)
        if [ -z "$afpd_bin" ]; then
            log_error "afpd introuvable"
            return 1
        fi
        log_info "Lancement manuel de Netatalk..."
        if pgrep -x "afpd" &> /dev/null; then
            sudo killall afpd 2>/dev/null || true
            sleep 1
        fi
        if pgrep -x "cnid_metad" &> /dev/null; then
            sudo killall cnid_metad 2>/dev/null || true
            sleep 1
        fi
        sudo "$afpd_bin" -d -F "$netatalk_config" &
        log_info "Netatalk démarré (PID: $!)"
    fi

    sleep 2
    local ip_address=$(get_ip_address)
    log_info "Accès AFP: afp://${ip_address}/VM_Shares"
    return 0
}

# Test Samba
test_samba() {
    log_header "Test de la connexion Samba"

    if ! pgrep -x "smbd" &> /dev/null; then
        log_warn "Samba (smbd) non en cours d'exécution"
        return 1
    fi
    log_info "Samba (smbd) est en cours d'exécution"

    local smbd_config=""
    if [ -f "$HOME/.vm-assistant/samba/smb.conf" ]; then
        smbd_config="$HOME/.vm-assistant/samba/smb.conf"
    elif [ -f "/opt/local/etc/samba/smb.conf" ]; then
        smbd_config="/opt/local/etc/samba/smb.conf"
    fi

    if [ -n "$smbd_config" ] && command -v testparm &> /dev/null; then
        if testparm "$smbd_config" >/dev/null 2>&1; then
            log_info "Configuration Samba valide"
        else
            log_warn "Configuration Samba invalide: testparm $smbd_config"
        fi
    fi

    local ip_address=$(get_ip_address)
    local share_test=""

    for share in VM_Shares VM_Disks VM_ISOs; do
        if smbclient "//$ip_address/$share" -U$(whoami) -N -c "ls" 2>&1 | grep -q "NT_STATUS_OK\|domain=\|DRW"; then
            log_info "Partage $share: OK"
            share_test="${share_test:+$share_test }$share"
        else
            log_warn "Partage $share: ECHEC"
        fi
    done

    if [ -n "$share_test" ]; then
        log_info "Tests Samba: $share_test - OK"
        return 0
    else
        log_warn "Tests Samba: Aucun partage accessible"
        return 1
    fi
}

test_local_share() {
    log_header "Test du partage local"
    ensure_dir "$SHARE_DIR"

    if [ -w "$SHARE_DIR" ]; then
        log_info "Permissions écriture: OK"
    else
        log_warn "Permissions écriture: ECHEC"
        log_info "Corrigez: sudo chmod 777 $SHARE_DIR"
    fi

    if [ -r "$SHARE_DIR" ]; then
        log_info "Permissions lecture: OK"
    else
        log_warn "Permissions lecture: ECHEC"
    fi

    local test_file="$SHARE_DIR/.vm_test_$$"
    if touch "$test_file" 2>/dev/null; then
        log_info "Création fichier: OK"
        rm -f "$test_file"
    else
        log_warn "Création fichier: ECHEC"
    fi

    local disk_usage=$(df -h "$SHARE_DIR" 2>/dev/null | tail -1 | awk '{print $4}')
    [ -n "$disk_usage" ] && log_info "Espace disponible: $disk_usage"
    return 0
}

list_shares() {
    log_header "Liste des partages configurés"
    echo ""
    echo "=== Partages Samba ==="
    if command -v smbclient &> /dev/null; then
        smbclient -g -L localhost 2>/dev/null | grep -E "VM_|Shares" || echo "Aucun"
    else
        echo "Samba non installé"
    fi
    echo ""
    echo "=== Repertoires locaux ==="
    for dir in "$SHARE_DIR" "$DISK_DIR" "$ISO_DIR"; do
        [ -d "$dir" ] && echo "  $dir ($(du -sh "$dir" 2>/dev/null | cut -f1))"
    done
    return 0
}

configure_xquartz() {
    log_header "Configuration de XQuartz"

    if [ ! -d "/Applications/Utilities/XQuartz.app" ]; then
        log_error "XQuartz non installé"
        log_info "Téléchargez depuis: https://www.xquartz.org"
        return 1
    fi

    [ ! -f "$HOME/.Xauthority" ] && touch "$HOME/.Xauthority" && chmod 600 "$HOME/.Xauthority"
    export DISPLAY=":0"

    xhost +local: &>/dev/null || xhost +local:
    log_info "XQuartz configuré pour les connexions locales"

    if pgrep -x "Xquartz" &>/dev/null; then
        log_info "XQuartz est en cours d'exécution"
    else
        log_warn "XQuartz n'est pas en cours d'exécution"
        log_info "Lancez: open -a XQuartz"
    fi
    return 0
}

configure_ramdisk() {
    log_header "Configuration du RAMDISK"
    ensure_dir "$SHARE_DIR"
    sudo chmod 1777 "$SHARE_DIR"
    sudo chown root:wheel "$SHARE_DIR"

    local disk_usage=$(df -h "$SHARE_DIR" 2>/dev/null | tail -1 | awk '{print $4}')
    [ -n "$disk_usage" ] && log_info "Espace disponible: $disk_usage"
    log_info "RAMDISK configuré: $SHARE_DIR"
    return 0
}

# Main
case "${1:-help}" in
    samba) configure_samba ;;
    netatalk) configure_netatalk ;;
    shares) list_shares ;;
    xquartz) configure_xquartz ;;
    ramdisk) configure_ramdisk ;;
    all)
        configure_xquartz
        configure_ramdisk
        configure_samba
        configure_netatalk
        list_shares
        ;;
    test|test-all)
        test_local_share
        echo ""
        test_samba
        ;;
    test-local) test_local_share ;;
    test-samba) test_samba ;;
    help|*)
        echo "Usage: $0 {samba|netatalk|shares|xquartz|ramdisk|test|test-samba|test-local|all}"
        echo "  samba      - Configurer Samba"
        echo "  netatalk   - Configurer Netatalk (AFP)"
        echo "  shares     - Lister les partages"
        echo "  xquartz    - Configurer XQuartz"
        echo "  ramdisk    - Configurer le RAMDISK"
        echo "  all        - Configurer tout"
        echo "  test       - Tester tous les partages"
        ;;
esac
