#!/usr/bin/env bash

# Runs inside the container created by ct/pulsehealth.sh: Docker, Tailscale and a Pulse checkout in /opt/pulse.
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

setup_docker

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
if [[ ! -x /opt/pulse/scripts/setup.sh ]]; then
  msg_error "${REPO}@${BRANCH} has no scripts/setup.sh"
  exit 1
fi
ln -sf /opt/pulse/scripts/setup.sh /usr/local/bin/pulse-setup
msg_ok "Cloned ${REPO}@${BRANCH} to /opt/pulse"

motd_ssh
customize
cleanup_lxc
