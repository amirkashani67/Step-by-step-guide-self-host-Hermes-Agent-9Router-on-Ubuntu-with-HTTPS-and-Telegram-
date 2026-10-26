#!/usr/bin/env bash
# Stage 1: 9Router (localhost only) + Caddy HTTPS dashboard on Ubuntu 24.04/26.04.
# Usage: sudo bash install.sh
# Safe to re-run: existing secrets in /etc/9router/env are kept.
set -euo pipefail

ROUTER_PORT=20128
ENV_FILE=/etc/9router/env
UNIT_FILE=/etc/systemd/system/9router.service
CADDYFILE=/etc/caddy/Caddyfile

info() { printf '\n==> %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root: sudo bash install.sh"

# ---- input ----------------------------------------------------------------
read -rp "Dashboard domain (example: ai.example.com): " DOMAIN
DOMAIN="${DOMAIN// /}"
[[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]] \
  || die "Invalid domain: $DOMAIN"

# ---- packages -------------------------------------------------------------
info "Installing base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl git ufw openssl ca-certificates caddy

NODE_MAJOR=0
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]')
fi
if [ "$NODE_MAJOR" -lt 20 ]; then
  info "Installing Node.js and npm"
  apt-get install -y nodejs npm
fi
NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]')
[ "$NODE_MAJOR" -ge 20 ] || die "Node.js 20+ is required (found $NODE_MAJOR)"

# ---- firewall (SSH first, so we never lock ourselves out) -----------------
info "Configuring firewall (22, 80, 443 only)"
ufw allow 22/tcp >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null
ufw status | head -n 12

# ---- 9Router --------------------------------------------------------------
info "Installing or updating 9Router"
npm install -g 9router@latest --prefer-online >/dev/null
command -v 9router >/dev/null 2>&1 || die "9router not found after install"
ROUTER_BIN=$(command -v 9router)
echo "9Router version: $(9router --version 2>/dev/null || echo unknown)"

info "Writing configuration (secrets are generated once and kept)"
mkdir -p /etc/9router /var/lib/9router
if [ ! -s "$ENV_FILE" ]; then
  umask 077
  cat > "$ENV_FILE" <<EOF
PORT=$ROUTER_PORT
NODE_ENV=production
DATA_DIR=/var/lib/9router
INITIAL_PASSWORD=$(openssl rand -base64 18 | tr -d '/+=')
JWT_SECRET=$(openssl rand -hex 32)
API_KEY_SECRET=$(openssl rand -hex 32)
MACHINE_ID_SALT=$(openssl rand -hex 16)
REQUIRE_API_KEY=true
AUTH_COOKIE_SECURE=true
EOF
  chmod 600 "$ENV_FILE"
  echo "Created $ENV_FILE"
else
  echo "Kept existing $ENV_FILE"
fi

# ---- systemd service (bound to 127.0.0.1 explicitly) -----------------------
info "Installing systemd service"
cat > "$UNIT_FILE" <<EOF
[Unit]
Description=9Router
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=$ENV_FILE
ExecStart=$ROUTER_BIN --host 127.0.0.1 --port $ROUTER_PORT --no-browser --skip-update --log
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable 9router >/dev/null
systemctl restart 9router

info "Waiting for 9Router to become healthy"
ok=0
for _ in $(seq 1 20); do
  code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:$ROUTER_PORT/dashboard" || true)
  case "$code" in 200|307|308) ok=1; break;; esac
  sleep 3
done
[ "$ok" -eq 1 ] || die "9Router did not respond. Check: journalctl -u 9router -n 50 --no-pager"

# Verify it is NOT exposed on a public interface
if ss -tln | grep -E "[^0-9.]0\.0\.0\.0:$ROUTER_PORT|\[::\]:$ROUTER_PORT" >/dev/null; then
  die "9Router is listening on a public interface. Check the unit file."
fi
echo "9Router listens on 127.0.0.1:$ROUTER_PORT only"

# ---- Caddy HTTPS ----------------------------------------------------------
info "Configuring Caddy for https://$DOMAIN"
cat > "$CADDYFILE" <<EOF
$DOMAIN {
    reverse_proxy 127.0.0.1:$ROUTER_PORT
}
EOF
caddy validate --config "$CADDYFILE" >/dev/null
systemctl enable caddy >/dev/null
systemctl reload caddy || systemctl restart caddy

info "Checking DNS and HTTPS"
if ! getent hosts "$DOMAIN" >/dev/null; then
  echo "WARNING: $DOMAIN does not resolve yet. Add the A record and re-run, or wait."
fi
https_code=""
for _ in $(seq 1 20); do
  https_code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "https://$DOMAIN/" || true)
  case "$https_code" in 200|307|308) break;; esac
  sleep 5
done
case "$https_code" in
  200|307|308) echo "HTTPS OK: https://$DOMAIN (HTTP $https_code)";;
  *) echo "WARNING: HTTPS check returned '$https_code'. Usually DNS not ready or ports 80/443 blocked.";;
esac

# ---- summary --------------------------------------------------------------
cat <<EOF

================================================================
Stage 1 finished.

Dashboard:        https://$DOMAIN/dashboard
Initial password: sudo grep INITIAL_PASSWORD $ENV_FILE
                  (shown only here; change it in the dashboard)

Next steps (manual, in the browser):
  1. Log in and change the password.
  2. Connect providers and create an API key.
  3. Keep the API key out of chats and screenshots.

Check later with:
  systemctl status 9router --no-pager
  ss -tlnp | grep $ROUTER_PORT
================================================================
EOF
