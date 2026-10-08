#!/usr/bin/env bash
# First-run setup inside the Proxmox container made by ct/pulsehealth.sh: asks for the .env values, generates the
# session secret, starts pulse.service and serves it over HTTPS on your tailnet (docs/setup.md, steps 3, 5 and 6).
#
#   pulse-setup               # or, from the Proxmox host: pct exec <id> -- /opt/pulse/proxmox/setup.sh
#
# Safe to run again: it offers the current values as defaults and keeps the existing secrets.
set -euo pipefail
umask 077

[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
cd "$(dirname "$(readlink -f "$0")")/.."

step() { printf '\n\033[1;36m%s\033[0m\n' "$*"; }
die() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

get() { grep -E "^$1=" .env | tail -1 | cut -d= -f2- || true; }
# Replaces the variable's line in place (also the commented-out one from .env.example), or appends it.
set_env() {
  k=$1 v=$2 awk 'BEGIN { k = ENVIRON["k"]; v = ENVIRON["v"] }
    !done && $0 ~ "^(# ?)?" k "=" { print k "=" v; done = 1; next } { print }
    END { if (!done) print k "=" v }' .env > .env.tmp
  mv .env.tmp .env
}
# ask VAR "Prompt" [default]: no spaces allowed, since every value here is a URL, an email list or a key.
ask() {
  local reply
  read -r -p "$2${3:+ [$3]}: " reply
  reply=${reply:-${3:-}}
  [[ ! $reply =~ [[:space:]] ]] || die "$2 can't contain spaces"
  printf -v "$1" '%s' "$reply"
}

[ -f /etc/systemd/system/pulse.service ] && [ -f .env ] || die "no pulse.service or .env: install with proxmox/ct/pulsehealth.sh"

HOST=
if command -v tailscale >/dev/null; then
  step "Tailscale"
  tailscale status >/dev/null 2>&1 || tailscale up
  HOST=$(tailscale status --json | jq -r '.Self.DNSName // ""' | sed 's/\.$//') || true
  if [ -n "$HOST" ]; then
    echo "This machine is $HOST. MagicDNS and HTTPS Certificates must be on: https://login.tailscale.com/admin/dns"
  fi
fi

step "Pulse"
ask DATA_SOURCE "Data source (demo = generated data, google = your own)" "$(get DATA_SOURCE)"
[[ $DATA_SOURCE =~ ^(demo|google)$ ]] || die "DATA_SOURCE must be demo or google"
APP_URL=$(get APP_URL)
ask APP_URL "Address you will open Pulse on" "${APP_URL:-${HOST:+https://$HOST}}"
APP_URL=${APP_URL%/}
[[ $APP_URL =~ ^https?:// ]] || die "the address must start with https://"

if [ "$DATA_SOURCE" = google ]; then
  ask ADMIN_EMAILS "Your email (the one you will sign up to Pulse with)" "$(get ADMIN_EMAILS)"
  [ -n "$ADMIN_EMAILS" ] || die "an admin email is required"

  step "Google OAuth client (docs/setup.md, step 4)"
  echo "Authorized redirect URI for the client: $APP_URL/oauth/callback"
  ask GOOGLE_CLIENT_ID "Client ID" "$(get GOOGLE_CLIENT_ID)"
  GOOGLE_CLIENT_SECRET=$(get GOOGLE_CLIENT_SECRET)
  read -r -s -p "Client secret${GOOGLE_CLIENT_SECRET:+ [keep current]}: " reply; echo
  GOOGLE_CLIENT_SECRET=${reply:-$GOOGLE_CLIENT_SECRET}
  [ -n "$GOOGLE_CLIENT_ID" ] && [ -n "$GOOGLE_CLIENT_SECRET" ] || die "the client ID and secret are required"
  [[ ! $GOOGLE_CLIENT_SECRET =~ [[:space:]] ]] || die "the client secret can't contain spaces"
  set_env ADMIN_EMAILS "$ADMIN_EMAILS"
  set_env GOOGLE_CLIENT_ID "$GOOGLE_CLIENT_ID"
  set_env GOOGLE_CLIENT_SECRET "$GOOGLE_CLIENT_SECRET"
fi

set_env DATA_SOURCE "$DATA_SOURCE"
set_env APP_URL "$APP_URL"
[ -n "$(get BETTER_AUTH_SECRET)" ] || set_env BETTER_AUTH_SECRET "$(openssl rand -base64 32)"

step "Starting Pulse"
PORT=$(get PORT); PORT=${PORT:-3000}
systemctl enable -q pulse
systemctl restart pulse
up=
for _ in $(seq 30); do
  if curl -fsS -o /dev/null "http://127.0.0.1:$PORT/healthz" 2>/dev/null; then up=1; break; fi
  sleep 2
done
if [ -z "$up" ]; then
  journalctl -u pulse -n 30 --no-pager >&2
  die "Pulse did not come up; fix what the log above names and run this again"
fi
if [ -n "$HOST" ] && [ "$APP_URL" = "https://$HOST" ]; then
  tailscale serve --bg "$PORT"
fi

step "Pulse is running at $APP_URL"
if [ "$DATA_SOURCE" = google ]; then
  echo "Create your account right away with $ADMIN_EMAILS: whoever signs up with it first owns the server."
  echo "Then go through onboarding and Connect Google."
else
  echo 'Open it and choose "Continue with demo data".'
fi
echo "Logs: journalctl -u pulse -f    Change a value: pulse-setup    Update: update"
