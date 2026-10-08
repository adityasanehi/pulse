#!/usr/bin/env bash
# Creates a Proxmox LXC container for Pulse with the community-scripts engine (https://community-scripts.org).
# Run it in the Proxmox host's shell:
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/adityasanehi/pulse/main/proxmox/ct/pulsehealth.sh)"
#
# The engine fetches install/pulsehealth-install.sh from COMMUNITY_SCRIPTS_URL and runs it in the new container.
# To run a fork or branch (branch names without a slash), export COMMUNITY_SCRIPTS_URL=<its raw base>/proxmox first.
# The slug is "pulsehealth" because community-scripts already has an unrelated "pulse".
export COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/adityasanehi/pulse/main/proxmox}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# License: PolyForm Noncommercial 1.0.0 | https://github.com/adityaongit/pulse/blob/main/LICENSE
# Source: https://github.com/adityaongit/pulse

APP="Pulse Health"
var_tags="${var_tags:-health}"
var_cpu="${var_cpu:-2}"
# The Next.js build needs the memory; running Pulse and Postgres takes under 1 GB.
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_hostname="${var_hostname:-pulse}"
# Tailscale needs /dev/net/tun (docs/setup.md, step 3).
var_tun="${var_tun:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/pulse ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  cd /opt/pulse

  # Migrations run at boot; a dump first means a bad one can be undone by hand. Kept: the last 10.
  msg_info "Backing up Postgres"
  install -d -m 700 backups
  runuser -u postgres -- pg_dump -Fc pulse >"backups/pre-update-$(date +%Y%m%d-%H%M%S).dump"
  ls -1t backups/pre-update-*.dump | tail -n +11 | xargs -r rm -f
  msg_ok "Backed up Postgres to /opt/pulse/backups"

  # ponytail: builds in place, so Pulse is down for the build and a failed build leaves it down (no rollback).
  # Build in a second checkout and swap if that ever matters.
  msg_info "Updating Pulse"
  $STD git pull --ff-only
  systemctl stop pulse
  $STD proxmox/build.sh
  if systemctl is-enabled -q pulse; then systemctl start pulse; fi
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Pulse still needs its .env. Configure and start it with:${CL}"
echo -e "${TAB}${BGN}pct exec ${CTID} -- /opt/pulse/proxmox/setup.sh${CL}"
read -r -p "${TAB}Run it now? <Y/n> " prompt
if [[ ! "${prompt,,}" =~ ^(n|no)$ ]]; then
  pct exec "$CTID" -- /opt/pulse/proxmox/setup.sh
fi
