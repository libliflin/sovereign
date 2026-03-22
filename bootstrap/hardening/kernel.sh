#!/usr/bin/env bash
# bootstrap/hardening/kernel.sh — Kernel sysctl hardening (CIS benchmark subset)
#
# Run on each node as root via SSH. Applies sysctl settings from:
#   - CIS Ubuntu Linux 22.04 Benchmark (Level 1 and 2)
#   - NIST SP 800-123 guidelines
#
# Settings applied:
#   - tcp_syncookies:       SYN flood protection
#   - rp_filter:            Reverse path filtering (spoofing protection)
#   - dmesg_restrict:       Restrict dmesg to root only
#   - suid_dumpable:        Disable core dumps from setuid programs
#   - accept_redirects:     Disable ICMP redirect acceptance
#   - send_redirects:       Disable ICMP redirect sending
#   - accept_source_route:  Disable IP source routing
#   - log_martians:         Log packets with impossible addresses
#
# Usage (called by bootstrap.sh via SSH):
#   ssh root@<node-ip> 'bash -s' < bootstrap/hardening/kernel.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

echo "==> [hardening/kernel] Applying CIS benchmark sysctl settings..."

# Ensure we are running as root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: kernel.sh must run as root" >&2
  exit 1
fi

SYSCTL_FILE="/etc/sysctl.d/99-sovereign-hardening.conf"

cat > "$SYSCTL_FILE" <<'EOF'
# Sovereign Platform — Kernel Hardening (CIS benchmark subset)
# Applied by bootstrap/hardening/kernel.sh

# ── Network: SYN flood protection ──────────────────────────────────────────
net.ipv4.tcp_syncookies = 1

# ── Network: Reverse path filtering (anti-spoofing) ───────────────────────
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# ── Network: Disable ICMP redirect acceptance (prevent MITM routing) ──────
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# ── Network: Disable ICMP redirect sending ────────────────────────────────
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# ── Network: Disable IP source routing ───────────────────────────────────
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# ── Network: Log martian packets (impossible source addresses) ────────────
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# ── Network: Ignore broadcast ICMP (Smurf attack protection) ─────────────
net.ipv4.icmp_echo_ignore_broadcasts = 1

# ── Network: Ignore bogus ICMP error responses ────────────────────────────
net.ipv4.icmp_ignore_bogus_error_responses = 1

# ── Network: Disable IPv6 router advertisements (we manage routes) ─────────
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# ── Kernel: Restrict dmesg to root (information disclosure) ───────────────
kernel.dmesg_restrict = 1

# ── Kernel: Disable core dumps from setuid programs ──────────────────────
fs.suid_dumpable = 0

# ── Kernel: Restrict ptrace to parent processes only ─────────────────────
kernel.yama.ptrace_scope = 1

# ── Kernel: Randomise memory layout (ASLR) ───────────────────────────────
kernel.randomize_va_space = 2

# ── Kernel: Restrict /proc/kallsyms (kernel symbol information) ──────────
kernel.kptr_restrict = 2

# ── Kernel: Disable magic SysRq key (prevent crash-via-keyboard) ─────────
kernel.sysrq = 0

# ── VM: Disable overcommit (prevent memory exhaustion attacks) ────────────
vm.overcommit_memory = 0
EOF

echo "==> [hardening/kernel] Applying settings with sysctl..."
sysctl -p "$SYSCTL_FILE" 2>&1 | grep -v "^$" || true

echo "==> [hardening/kernel] Verifying key settings..."
FAILED=0

check_sysctl() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(sysctl -n "$key" 2>/dev/null || echo "MISSING")"
  if [[ "$actual" != "$expected" ]]; then
    echo "  WARN: $key = $actual (expected $expected)" >&2
    FAILED=$((FAILED + 1))
  fi
}

check_sysctl "net.ipv4.tcp_syncookies"       "1"
check_sysctl "net.ipv4.conf.all.rp_filter"   "1"
check_sysctl "kernel.dmesg_restrict"         "1"
check_sysctl "fs.suid_dumpable"              "0"
check_sysctl "kernel.randomize_va_space"     "2"

if [[ "$FAILED" -gt 0 ]]; then
  echo "==> [hardening/kernel] $FAILED settings could not be verified (may need reboot)."
else
  echo "==> [hardening/kernel] All key settings verified."
fi

echo "==> [hardening/kernel] Kernel hardening complete."
