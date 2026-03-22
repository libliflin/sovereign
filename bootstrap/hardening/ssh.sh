#!/usr/bin/env bash
# bootstrap/hardening/ssh.sh — SSH daemon hardening for Ubuntu 22.04 LTS
#
# Run on each node as root via SSH. Enforces:
#   - PasswordAuthentication no (pubkey only)
#   - PermitRootLogin prohibit-password (root login via pubkey only, no password)
#   - PubkeyAuthentication yes
#   - Disables X11 forwarding, TCP forwarding, and other attack surface
#   - Sets idle timeout (ClientAliveInterval + ClientAliveCountMax)
#
# IMPORTANT: Ensure your SSH public key is in /root/.ssh/authorized_keys
# BEFORE running this script. Running this without a key will lock you out.
#
# Usage (called by bootstrap.sh via SSH):
#   ssh root@<node-ip> 'bash -s' < bootstrap/hardening/ssh.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

echo "==> [hardening/ssh] Starting SSH daemon hardening..."

# Ensure we are running as root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: ssh.sh must run as root" >&2
  exit 1
fi

# Guard: ensure at least one authorized key exists before locking down SSH
if [[ ! -f /root/.ssh/authorized_keys ]] || [[ ! -s /root/.ssh/authorized_keys ]]; then
  echo "ERROR: /root/.ssh/authorized_keys is missing or empty." >&2
  echo "  Add your public key first to avoid being locked out." >&2
  exit 1
fi

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP="${SSHD_CONFIG}.sovereign-backup.$(date +%Y%m%d%H%M%S)"

echo "==> [hardening/ssh] Backing up sshd_config to ${BACKUP}..."
cp "$SSHD_CONFIG" "$BACKUP"

echo "==> [hardening/ssh] Applying hardened sshd_config..."

# Apply each setting using sed (idempotent — replaces existing or appends)
apply_setting() {
  local key="$1"
  local value="$2"
  local config="$3"
  # Remove existing setting (commented or uncommented)
  sed -i "/^#*\s*${key}\s/d" "$config"
  # Append the new setting
  echo "${key} ${value}" >> "$config"
}

apply_setting "PasswordAuthentication"    "no"                "$SSHD_CONFIG"
apply_setting "PermitRootLogin"           "prohibit-password" "$SSHD_CONFIG"
apply_setting "PubkeyAuthentication"      "yes"               "$SSHD_CONFIG"
apply_setting "AuthorizedKeysFile"        ".ssh/authorized_keys" "$SSHD_CONFIG"
apply_setting "PermitEmptyPasswords"      "no"                "$SSHD_CONFIG"
apply_setting "ChallengeResponseAuthentication" "no"          "$SSHD_CONFIG"
apply_setting "UsePAM"                    "yes"               "$SSHD_CONFIG"
apply_setting "X11Forwarding"             "no"                "$SSHD_CONFIG"
apply_setting "AllowTcpForwarding"        "no"                "$SSHD_CONFIG"
apply_setting "AllowAgentForwarding"      "no"                "$SSHD_CONFIG"
apply_setting "GatewayPorts"              "no"                "$SSHD_CONFIG"
apply_setting "MaxAuthTries"              "3"                 "$SSHD_CONFIG"
apply_setting "MaxSessions"              "5"                  "$SSHD_CONFIG"
apply_setting "LoginGraceTime"            "30"                "$SSHD_CONFIG"
apply_setting "ClientAliveInterval"       "300"               "$SSHD_CONFIG"
apply_setting "ClientAliveCountMax"       "2"                 "$SSHD_CONFIG"
apply_setting "PrintLastLog"              "yes"               "$SSHD_CONFIG"
apply_setting "Banner"                    "none"              "$SSHD_CONFIG"

# Restrict host key algorithms to modern curves only
apply_setting "HostKeyAlgorithms"         "ssh-ed25519,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384" "$SSHD_CONFIG"
apply_setting "KexAlgorithms"             "curve25519-sha256,ecdh-sha2-nistp256,ecdh-sha2-nistp384" "$SSHD_CONFIG"
apply_setting "Ciphers"                   "aes256-gcm@openssh.com,aes128-gcm@openssh.com,chacha20-poly1305@openssh.com" "$SSHD_CONFIG"
apply_setting "MACs"                      "hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com" "$SSHD_CONFIG"

echo "==> [hardening/ssh] Validating sshd_config syntax..."
sshd -t -f "$SSHD_CONFIG"

echo "==> [hardening/ssh] Restarting SSH daemon..."
systemctl restart ssh

echo "==> [hardening/ssh] SSH hardening complete."
echo "    Password authentication is DISABLED. Pubkey only."
