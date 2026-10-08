#!/usr/bin/env bash
# First-run setup on the machine that runs Pulse: asks for the .env values, generates the secrets, starts the
# containers and, when Tailscale is installed, serves Pulse over HTTPS on your tailnet (docs/setup.md, steps 3, 5, 6).
#
#   scripts/setup.sh          # the Proxmox helper script installs it as `pulse-setup`
#
# Safe to run again: it offers the current values as defaults and keeps the existing secrets.
set -euo pipefail
umask 077

[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
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

docker info >/dev/null 2>&1 || die "Docker is not reachable (docs/setup.md, step 2)"
[ -f .env ] || cp .env.example .env

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
# Generated once and kept: Postgres stores its password in the volume on first start. Hex, because compose.yaml puts
# it in DATABASE_URL, where base64's "/" and "+" would break the URL.
[ -n "$(get POSTGRES_PASSWORD)" ] || set_env POSTGRES_PASSWORD "$(openssl rand -hex 24)"
[ -n "$(get BETTER_AUTH_SECRET)" ] || set_env BETTER_AUTH_SECRET "$(openssl rand -base64 32)"

# Tailscale (or any tunnel or proxy on the host) reaches Pulse on a loopback-only port.
if [ ! -f compose.override.yaml ]; then
  cat > compose.override.yaml <<'EOF'
services:
  pulse:
    ports:
      - "127.0.0.1:3000:3000"
EOF
fi

step "Building and starting Pulse (the first build takes a few minutes)"
docker compose up -d --build
if [ -n "$HOST" ] && [ "$APP_URL" = "https://$HOST" ]; then
  tailscale serve --bg 3000
fi

step "Pulse is starting at $APP_URL"
if [ "$DATA_SOURCE" = google ]; then
  echo "Create your account right away with $ADMIN_EMAILS: whoever signs up with it first owns the server."
  echo "Then go through onboarding and Connect Google."
else
  echo 'Open it and choose "Continue with demo data".'
fi
echo "Logs: docker compose logs -f pulse    Change a value: run this again"
