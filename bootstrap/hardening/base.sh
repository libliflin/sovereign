#!/usr/bin/env bash
# bootstrap/hardening/base.sh — Base OS hardening for Ubuntu 22.04 LTS
#
# Run on each node as root via SSH. Installs and enables:
#   - unattended-upgrades: automatic security updates
#   - fail2ban: brute-force protection for SSH and other services
#   - auditd: system call auditing (CIS benchmark requirement)
#   - Removes unnecessary packages: telnet, rsh-client, talk
#
# Usage (called by bootstrap.sh via SSH):
#   ssh root@<node-ip> 'bash -s' < bootstrap/hardening/base.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

echo "==> [hardening/base] Starting base OS hardening..."

# Ensure we are running as root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: base.sh must run as root" >&2
  exit 1
fi

echo "==> [hardening/base] Updating package lists..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

echo "==> [hardening/base] Installing security packages..."
apt-get install -y -qq \
  unattended-upgrades \
  apt-listchanges \
  fail2ban \
  auditd \
  audispd-plugins

echo "==> [hardening/base] Removing unnecessary packages..."
apt-get remove -y -qq --purge \
  telnet \
  rsh-client \
  talk \
  ntalk \
  2>/dev/null || true
apt-get autoremove -y -qq

echo "==> [hardening/base] Configuring unattended-upgrades..."
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Download-Upgradeable-Packages "1";
EOF

cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
  "${distro_id}:${distro_codename}";
  "${distro_id}:${distro_codename}-security";
  "${distro_id}ESMApps:${distro_codename}-apps-security";
  "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Mail "";
EOF

echo "==> [hardening/base] Configuring fail2ban..."
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
mode     = aggressive
port     = ssh
logpath  = %(sshd_log)s
backend  = %(sshd_backend)s
maxretry = 3
EOF

echo "==> [hardening/base] Configuring auditd..."
# Append sovereign audit rules (CIS benchmark subset)
cat > /etc/audit/rules.d/sovereign.rules <<'EOF'
# Sovereign Platform — auditd rules (CIS benchmark subset)
# Monitor privilege escalation
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope
# Monitor authentication events
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock/ -p wa -k logins
# Monitor system administration
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
# Monitor network config changes
-w /etc/hosts -p wa -k system-locale
-w /etc/sysconfig/network -p wa -k system-locale
# Immutable (must be last line)
-e 2
EOF

echo "==> [hardening/base] Enabling and starting services..."
systemctl enable --now unattended-upgrades
systemctl enable --now fail2ban
systemctl enable --now auditd

echo "==> [hardening/base] Base hardening complete."
