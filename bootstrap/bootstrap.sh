#!/usr/bin/env bash
# bootstrap/bootstrap.sh — VPS provisioning bootstrap
#
# Usage:
#   ./bootstrap/bootstrap.sh --estimated-cost    # read-only cost estimate, no charges
#   ./bootstrap/bootstrap.sh --confirm-charges   # provision real servers (not yet implemented)
#   ./bootstrap/bootstrap.sh --dry-run           # preview intended actions (not yet implemented)

set -euo pipefail

CONFIG_FILE="bootstrap/config.yaml"

usage() {
  echo "Usage: $0 --estimated-cost | --confirm-charges | --dry-run"
  echo ""
  echo "  --estimated-cost   Print cost estimate from config.yaml — no API calls, no charges"
  echo "  --confirm-charges  Provision real servers (requires this flag — not yet implemented)"
  echo "  --dry-run          Preview intended actions — not yet implemented"
  exit 1
}

estimated_cost() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "CONFIG NOT FOUND: ${CONFIG_FILE} does not exist."
    echo ""
    echo "Copy the example and fill in your values:"
    echo "  cp bootstrap/config.yaml.example bootstrap/config.yaml"
    exit 1
  fi

  if ! command -v python3 &>/dev/null; then
    echo "PREREQUISITE MISSING: python3 is required to parse config.yaml"
    exit 1
  fi

  python3 - "${CONFIG_FILE}" <<'PYEOF'
import sys
import re

config_path = sys.argv[1]

# Minimal YAML scalar parser — handles only the fields we need.
# Avoids a PyYAML dependency while remaining correct for config.yaml structure.
def parse_simple_yaml(text):
    result = {}
    current_section = None
    for line in text.splitlines():
        # Skip comments and blanks
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        # Top-level section (no leading spaces, ends with colon)
        top_match = re.match(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*$', line)
        if top_match:
            current_section = top_match.group(1)
            if current_section not in result:
                result[current_section] = {}
            continue
        # Top-level scalar: key: value
        top_scalar = re.match(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*"?([^"#\n]*?)"?\s*(?:#.*)?$', line)
        if top_scalar and not line.startswith(" "):
            result[top_scalar.group(1)] = top_scalar.group(2).strip()
            current_section = None
            continue
        # Nested scalar under current section
        if current_section and line.startswith(" "):
            nested = re.match(r'^\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*"?([^"#\n]*?)"?\s*(?:#.*)?$', line)
            if nested:
                result[current_section][nested.group(1)] = nested.group(2).strip()
    return result

with open(config_path) as f:
    raw = f.read()

cfg = parse_simple_yaml(raw)

provider    = cfg.get("provider", "hetzner").strip().lower()
server_type = ""
count       = 3

if "nodes" in cfg and isinstance(cfg["nodes"], dict):
    count_raw = cfg["nodes"].get("count", "3")
    try:
        count = int(count_raw)
    except ValueError:
        count = 3
    server_type = cfg["nodes"].get("serverType", "").strip().lower()

# Static price table (monthly, approximate). Updated 2026-04.
# Sources: provider public pricing pages.
PRICES = {
    "hetzner": {
        "cx22": ("2 vCPU / 4 GB RAM",  "€3.79"),
        "cx32": ("4 vCPU / 8 GB RAM",  "€8.21"),
        "cx42": ("8 vCPU / 16 GB RAM", "€17.81"),
        "cx52": ("16 vCPU / 32 GB RAM","€33.43"),
    },
    "digitalocean": {
        "s-2vcpu-4gb":  ("2 vCPU / 4 GB RAM",  "$24.00"),
        "s-4vcpu-8gb":  ("4 vCPU / 8 GB RAM",  "$48.00"),
        "s-8vcpu-16gb": ("8 vCPU / 16 GB RAM", "$96.00"),
    },
    "aws-ec2": {
        "t3.small":  ("2 vCPU / 2 GB RAM",  "$16.79"),
        "t3.medium": ("2 vCPU / 4 GB RAM",  "$30.37"),
        "t3.large":  ("2 vCPU / 8 GB RAM",  "$60.74"),
    },
    "generic": {},
}

if provider == "generic":
    print("Estimated monthly cost for this configuration:")
    print(f"  Provider:    generic (bare metal / existing nodes)")
    print(f"  Node count:  {count}")
    print(f"  Cost/node:   $0.00 (you own the hardware)")
    print(f"  Total:       $0.00/mo")
    print("")
    print("Run with --confirm-charges to provision (not yet implemented).")
    sys.exit(0)

if provider not in PRICES:
    print(f"UNKNOWN PROVIDER: '{provider}' is not in the static price table.")
    print(f"Known providers: hetzner, digitalocean, aws-ec2, generic")
    sys.exit(1)

provider_prices = PRICES[provider]

if not server_type:
    # Default to the first (cheapest) option
    server_type = next(iter(provider_prices))

if server_type not in provider_prices:
    known = ", ".join(provider_prices.keys())
    print(f"UNKNOWN SERVER TYPE: '{server_type}' not found for provider '{provider}'.")
    print(f"Known types for {provider}: {known}")
    sys.exit(1)

spec, unit_price = provider_prices[server_type]

# Parse numeric price for total calculation
price_digits = re.sub(r"[^0-9.]", "", unit_price)
currency_sym  = re.sub(r"[0-9. ]", "", unit_price)
try:
    unit_float = float(price_digits)
    total = f"{currency_sym}{unit_float * count:.2f}"
except ValueError:
    total = "unknown"

print("Estimated monthly cost for this configuration:")
print(f"  Provider:    {provider}")
print(f"  Node type:   {server_type} ({spec})")
print(f"  Node count:  {count}")
print(f"  Cost/node:   ~{unit_price}/mo")
print(f"  Total:       ~{total}/mo")
print("")
print("Run with --confirm-charges to provision (real servers, real charges).")
print("VPS provisioning is not yet implemented — see docs/quickstart.md.")
PYEOF
}

if [[ $# -eq 0 ]]; then
  usage
fi

case "$1" in
  --estimated-cost)
    estimated_cost
    ;;
  --confirm-charges|--dry-run)
    echo "BOOTSTRAP NOT IMPLEMENTED: VPS provisioning is not yet available."
    echo ""
    echo "For local development (no cloud account required):"
    echo "  ./cluster/kind/bootstrap.sh"
    echo ""
    echo "For platform deployment on an existing cluster:"
    echo "  ./platform/deploy.sh --cluster-values cluster-values.yaml"
    echo ""
    echo "See docs/quickstart.md for the full walkthrough."
    exit 1
    ;;
  *)
    echo "UNKNOWN FLAG: $1"
    echo ""
    usage
    ;;
esac
