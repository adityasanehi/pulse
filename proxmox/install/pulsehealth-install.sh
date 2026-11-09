#!/usr/bin/env bash

# Runs inside the container created by ct/pulsehealth.sh: Docker, Tailscale, an upstream Pulse checkout in /opt/pulse
# and pulse-setup.
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

# Pulse itself comes straight from upstream, so `update` gets its changes without syncing this fork. Only the
# Proxmox scripts and pulse-setup live here, fetched from the repo and branch these scripts came from.
msg_info "Cloning adityaongit/pulse"
$STD git clone https://github.com/adityaongit/pulse.git /opt/pulse
msg_ok "Cloned adityaongit/pulse to /opt/pulse"

msg_info "Installing pulse-setup"
curl -fsSL "${COMMUNITY_SCRIPTS_URL%/proxmox}/scripts/setup.sh" -o /usr/local/bin/pulse-setup
chmod +x /usr/local/bin/pulse-setup
msg_ok "Installed pulse-setup"

motd_ssh
customize
cleanup_lxc
