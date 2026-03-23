#!/usr/bin/env bash
# bootstrap/providers/cloudflare-dns.sh — Reusable Cloudflare API helper functions
#
# Source this file from scripts that need Cloudflare DNS, Tunnel, or Zone APIs.
#
# Required env vars (set before sourcing):
#   CF_API_TOKEN   — Cloudflare API token (Tunnel:Edit + DNS:Edit permissions)
#   CF_ACCOUNT_ID  — Cloudflare account ID (right sidebar in dashboard)
#   CF_ZONE_ID     — Cloudflare zone ID for your domain (DNS functions only)
#
# Usage:
#   export CF_API_TOKEN="..." CF_ACCOUNT_ID="..." CF_ZONE_ID="..."
#   source bootstrap/providers/cloudflare-dns.sh
#   cf_api GET /zones
#   cf_dns_upsert "*.example.com" CNAME "abc123.cfargotunnel.com"
# ─────────────────────────────────────────────────────────────────────────────

CF_API_BASE="https://api.cloudflare.com/client/v4"

# cf_api METHOD PATH [BODY_JSON]
# ─────────────────────────────────────────────────────────────────────────────
# Make an authenticated Cloudflare API call. Prints the full JSON response.
# Exits non-zero if the API returns success=false.
#
# Examples:
#   cf_api GET /zones
#   cf_api POST /accounts/abc/cfd_tunnel '{"name":"sovereign"}'
#   cf_api DELETE /zones/xyz/dns_records/rec123
cf_api() {
  local method="$1"
  local path="$2"
  local body="${3:-}"

  if [[ -z "${CF_API_TOKEN:-}" ]]; then
    echo "ERROR: CF_API_TOKEN is not set" >&2
    return 1
  fi

  local curl_args=(-s -X "$method" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json")

  if [[ -n "$body" ]]; then
    curl_args+=(-d "$body")
  fi

  local response
  response="$(curl "${curl_args[@]}" "${CF_API_BASE}${path}")"

  # Check success field using python3 json (avoids jq dependency)
  local success
  success="$(printf '%s' "$response" | \
    python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("success","false"))')"

  if [[ "$success" != "True" && "$success" != "true" ]]; then
    echo "ERROR: Cloudflare API call failed: $method $path" >&2
    printf '%s\n' "$response" >&2
    return 1
  fi

  printf '%s\n' "$response"
}

# cf_json_field RESPONSE FIELD
# ─────────────────────────────────────────────────────────────────────────────
# Extract a top-level result field from a Cloudflare API response.
# For nested fields use cf_json_path.
#
# Example:
#   tunnel_id="$(cf_json_field "$response" "id")"
cf_json_field() {
  local response="$1"
  local field="$2"
  printf '%s' "$response" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['${field}'])"
}

# cf_json_path RESPONSE PYTHON_EXPR
# ─────────────────────────────────────────────────────────────────────────────
# Extract an arbitrary field from a Cloudflare API response using a Python
# expression against d['result'].
#
# Example:
#   secret="$(cf_json_path "$response" "d['result']['credentials_file']['TunnelSecret']")"
cf_json_path() {
  local response="$1"
  local expr="$2"
  printf '%s' "$response" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(${expr})"
}

# cf_tunnel_create NAME SECRET_BASE64
# ─────────────────────────────────────────────────────────────────────────────
# Create a Cloudflare Tunnel and return the full JSON response.
# Requires: CF_API_TOKEN, CF_ACCOUNT_ID
#
# Arguments:
#   NAME           — tunnel name (e.g. "sovereign-prod")
#   SECRET_BASE64  — 32-byte random secret, base64-encoded
#                    (generate with: openssl rand -base64 32 | tr -d '\n')
#
# The response result contains:
#   .id                     — tunnel ID
#   .credentials_file       — credentials JSON (write to /etc/cloudflared/credentials.json)
#
# Example:
#   secret="$(openssl rand -base64 32 | tr -d '\n')"
#   response="$(cf_tunnel_create "sovereign" "$secret")"
#   tunnel_id="$(cf_json_field "$response" "id")"
cf_tunnel_create() {
  local name="$1"
  local secret="$2"

  if [[ -z "${CF_ACCOUNT_ID:-}" ]]; then
    echo "ERROR: CF_ACCOUNT_ID is not set" >&2
    return 1
  fi

  local body
  body="$(python3 -c "import json; print(json.dumps({'name': '${name}', 'tunnel_secret': '${secret}'}))")"

  cf_api POST "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel" "$body"
}

# cf_tunnel_delete TUNNEL_ID
# ─────────────────────────────────────────────────────────────────────────────
# Delete a Cloudflare Tunnel by ID. Requires: CF_API_TOKEN, CF_ACCOUNT_ID.
cf_tunnel_delete() {
  local tunnel_id="$1"

  if [[ -z "${CF_ACCOUNT_ID:-}" ]]; then
    echo "ERROR: CF_ACCOUNT_ID is not set" >&2
    return 1
  fi

  cf_api DELETE "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${tunnel_id}"
}

# cf_dns_upsert NAME TYPE CONTENT [PROXIED]
# ─────────────────────────────────────────────────────────────────────────────
# Create or update a DNS record in the zone. If a record with the same name
# and type already exists, it is updated. Otherwise a new record is created.
# Requires: CF_API_TOKEN, CF_ZONE_ID
#
# Arguments:
#   NAME     — DNS name (e.g. "*.example.com" or "node1.example.com")
#   TYPE     — record type: A, AAAA, CNAME, TXT, etc.
#   CONTENT  — record value (e.g. IP address or CNAME target)
#   PROXIED  — "true" or "false" (default: "false")
#
# Example:
#   cf_dns_upsert "*.sovereign-autarky.dev" CNAME "abc123.cfargotunnel.com" "true"
#   cf_dns_upsert "node1.sovereign-autarky.dev" A "1.2.3.4"
cf_dns_upsert() {
  local name="$1"
  local type="$2"
  local content="$3"
  local proxied="${4:-false}"

  if [[ -z "${CF_ZONE_ID:-}" ]]; then
    echo "ERROR: CF_ZONE_ID is not set" >&2
    return 1
  fi

  # Check if record already exists
  local existing_response
  existing_response="$(curl -s \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "${CF_API_BASE}/zones/${CF_ZONE_ID}/dns_records?type=${type}&name=${name}")"

  local existing_id
  existing_id="$(printf '%s' "$existing_response" | \
    python3 -c "
import sys, json
d = json.load(sys.stdin)
records = d.get('result', [])
print(records[0]['id'] if records else '')
" 2>/dev/null || true)"

  local body
  body="$(python3 -c "
import json
print(json.dumps({
    'type': '${type}',
    'name': '${name}',
    'content': '${content}',
    'proxied': ${proxied},
    'ttl': 1
}))
")"

  if [[ -n "$existing_id" ]]; then
    echo "  Updating existing DNS record: ${name} ${type} → ${content}" >&2
    cf_api PUT "/zones/${CF_ZONE_ID}/dns_records/${existing_id}" "$body" >/dev/null
  else
    echo "  Creating DNS record: ${name} ${type} → ${content}" >&2
    cf_api POST "/zones/${CF_ZONE_ID}/dns_records" "$body" >/dev/null
  fi
}

# cf_dns_delete NAME TYPE
# ─────────────────────────────────────────────────────────────────────────────
# Delete a DNS record by name and type. No-op if the record does not exist.
# Requires: CF_API_TOKEN, CF_ZONE_ID
cf_dns_delete() {
  local name="$1"
  local type="$2"

  if [[ -z "${CF_ZONE_ID:-}" ]]; then
    echo "ERROR: CF_ZONE_ID is not set" >&2
    return 1
  fi

  local existing_response
  existing_response="$(curl -s \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    "${CF_API_BASE}/zones/${CF_ZONE_ID}/dns_records?type=${type}&name=${name}")"

  local existing_id
  existing_id="$(printf '%s' "$existing_response" | \
    python3 -c "
import sys, json
d = json.load(sys.stdin)
records = d.get('result', [])
print(records[0]['id'] if records else '')
" 2>/dev/null || true)"

  if [[ -n "$existing_id" ]]; then
    echo "  Deleting DNS record: ${name} ${type}" >&2
    cf_api DELETE "/zones/${CF_ZONE_ID}/dns_records/${existing_id}" >/dev/null
  else
    echo "  DNS record not found (already deleted?): ${name} ${type}" >&2
  fi
}

# cf_zone_lookup DOMAIN
# ─────────────────────────────────────────────────────────────────────────────
# Look up the Cloudflare zone ID for a domain. Prints the zone ID to stdout.
# Requires: CF_API_TOKEN
#
# This is a convenience function for when you don't have the zone ID handy.
# For production scripts, set CF_ZONE_ID directly from config.yaml.
cf_zone_lookup() {
  local domain="$1"

  local response
  response="$(curl -s \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    "${CF_API_BASE}/zones?name=${domain}&status=active")"

  python3 -c "
import sys, json
d = json.load(sys.stdin)
records = d.get('result', [])
if not records:
    import sys
    print('ERROR: No active Cloudflare zone found for domain: ${domain}', file=sys.stderr)
    sys.exit(1)
print(records[0]['id'])
" <<< "$response"
}
