#!/usr/bin/env bash

# Runs inside the container created by ct/pulsehealth.sh: Node, Postgres, Tailscale and a Pulse build in /opt/pulse,
# run by pulse.service without Docker. proxmox/setup.sh (pulse-setup) then fills in .env and starts it.
# License: PolyForm Noncommercial 1.0.0 | https://github.com/adityaongit/pulse/blob/main/LICENSE
# Source: https://github.com/adityaongit/pulse

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y git jq openssl
msg_ok "Installed Dependencies"

NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs
PG_VERSION="18" setup_postgresql
PG_DB_NAME="pulse" PG_DB_USER="pulse" setup_postgresql_db

msg_info "Installing Tailscale"
$STD bash -c "$(curl -fsSL https://tailscale.com/install.sh)"
msg_ok "Installed Tailscale"

# Clone the repo and branch these scripts came from: https://raw.githubusercontent.com/<owner>/<repo>/<branch>/proxmox.
# The engine's own default (or nothing) reaching the container means the default repo; any other URL is an error, so
# a fork never silently installs another repo's code.
REPO=adityasanehi/pulse BRANCH=main
if [[ "${COMMUNITY_SCRIPTS_URL:-}" =~ ^https://raw\.githubusercontent\.com/([^/]+/[^/]+)/([^/]+)/proxmox$ ]]; then
  REPO=${BASH_REMATCH[1]} BRANCH=${BASH_REMATCH[2]}
elif [[ -n "${COMMUNITY_SCRIPTS_URL:-}" && "$COMMUNITY_SCRIPTS_URL" != */community-scripts/* ]]; then
  msg_error "Can't tell which repo to clone from COMMUNITY_SCRIPTS_URL=${COMMUNITY_SCRIPTS_URL}"
  exit 1
fi
msg_info "Cloning ${REPO}@${BRANCH}"
$STD git clone --branch "$BRANCH" "https://github.com/${REPO}.git" /opt/pulse
if [[ ! -x /opt/pulse/proxmox/setup.sh ]]; then
  msg_error "${REPO}@${BRANCH} has no proxmox/setup.sh"
  exit 1
fi
ln -sf /opt/pulse/proxmox/setup.sh /usr/local/bin/pulse-setup
msg_ok "Cloned ${REPO}@${BRANCH} to /opt/pulse"

msg_info "Building Pulse (this takes a few minutes)"
useradd --system --no-create-home --shell /usr/sbin/nologin pulse
$STD /opt/pulse/proxmox/build.sh
msg_ok "Built Pulse"

msg_info "Creating Service"
install -m 600 /opt/pulse/.env.example /opt/pulse/.env
echo "DATABASE_URL=postgres://pulse:${PG_DB_PASS}@localhost:5432/pulse" >>/opt/pulse/.env
# Loopback only: Tailscale (or a proxy in the container) serves it. Values in .env override these.
cat <<EOF >/etc/systemd/system/pulse.service
[Unit]
Description=Pulse
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
User=pulse
WorkingDirectory=/opt/pulse/.next/standalone
Environment=NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=127.0.0.1
EnvironmentFile=/opt/pulse/.env
ExecStart=/usr/bin/node server.js
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
msg_ok "Created Service (pulse-setup enables it)"

motd_ssh
customize
cleanup_lxc
