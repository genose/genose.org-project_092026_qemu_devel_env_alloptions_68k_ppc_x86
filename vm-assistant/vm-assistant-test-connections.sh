#!/bin/bash
echo "=========================================="
echo "  TEST COMPLET DES PARTAGES"
echo "=========================================="
echo ""

# Test 1: Partage local
echo "[1] Test du partage local (~/vm_assistant/shares)..."
test -d "$HOME/vm_assistant/shares" && test -w "$HOME/vm_assistant/shares" && echo "  ✓ Partage local: OK" || echo "  ✗ Partage local: ECHEC"

# Test 2: Samba
echo ""
echo "[2] Test Samba..."
pgrep -x "smbd" &>/dev/null && echo "  ✓ smbd est en cours" || echo "  ✗ smbd n'est pas en cours"
smbclient -L localhost -U% 2>/dev/null | grep -q "VM_Shares" && echo "  ✓ Partages Samba visibles" || echo "  ✗ Partages Samba non visibles"
smbclient //localhost/VM_Shares -U$(whoami) -N -c "ls" 2>/dev/null | grep -q "blocks" && echo "  ✓ Acces VM_Shares: OK" || echo "  ⚠️  Acces VM_Shares: besoin d'authentification"

# Test 3: Netatalk
echo ""
echo "[3] Test Netatalk..."
pgrep -x "afpd" &>/dev/null && echo "  ✓ afpd est en cours" || echo "  ✗ afpd n'est pas en cours"
afpclient -l localhost 2>/dev/null | grep -q "VM_Shares" && echo "  ✓ Partages Netatalk visibles" || echo "  ✗ Partages Netatalk non visibles"

echo ""
echo "[4] Adresses d'acces:"
echo "  Samba:  smb://$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\\.){3}[0-9]*' | grep -Eo '([0-9]*\\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)/VM_Shares"
echo "  AFP:    afp://$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\\.){3}[0-9]*' | grep -Eo '([0-9]*\\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)/VM_Shares"
echo "  Local:  $HOME/vm_assistant/shares"
