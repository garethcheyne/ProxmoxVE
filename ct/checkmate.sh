#!/usr/bin/env bash
# source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

source <(curl -fsSL https://raw.githubusercontent.com/garethcheyne/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2021-2025 bluelabs
# Author: https://bluewavelabs.ca/
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://checkmate.so/

APP="CheckMate"
var_tags="${var_tags:-rss-reader}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/checkmate ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE_INFO=$(curl -fsSL https://api.github.com/repos/bluewave-labs/checkmate/releases/latest)
  RELEASE=$(echo "${RELEASE_INFO}" | grep '"tag_name":' | cut -d'"' -f4)
  RELEASE_ZIP=$(echo "${RELEASE_INFO}" | grep '"zipball_url":' | cut -d'"' -f4)

  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Stopping ${APP}"
    systemctl stop checkmate
    msg_ok "Stopped ${APP}"

    if ! [[ $(dpkg -s rsync 2>/dev/null) ]]; then
      msg_info "Installing Dependencies"
      $STD apt-get update
      $STD apt-get install -y rsync
      msg_ok "Installed Dependencies"
    fi

    msg_info "Updating ${APP} to ${RELEASE}"

    curl -fsSL "${RELEASE_ZIP}" -o "checkmate-${RELEASE}.zip"
    unzip -q checkmate-"${RELEASE}".zip

    rsync -a --exclude 'data/' checkmate-"${RELEASE}"/ /opt/checkmate/

    rm -rf checkmate-"${RELEASE}" checkmate-"${RELEASE}".zip

    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Updated ${APP} to ${RELEASE}"

    msg_info "Starting ${APP}"
    systemctl start commafeed
    msg_ok "Started ${APP}"
    msg_ok "Updated Successfully"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8082${CL}"
