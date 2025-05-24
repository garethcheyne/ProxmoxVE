#!/usr/bin/env bash
# source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# For testing only
source <(curl -fsSL https://raw.githubusercontent.com/garethcheyne/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2021-2025 bluelabs
# Author: https://bluewavelabs.ca/
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kestra-io/kestra

APP="Kestra"
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
  if [[ ! -d /opt/kestra ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE_INFO=$(curl -fsSL https://github.com/kestra-io/kestra/releases/latest)
  RELEASE=$(echo "${RELEASE_INFO}" | grep '"tag_name":' | cut -d'"' -f4)

  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    /usr/local/bin/update-kestra.sh

    # Update the version file with the new release
    echo "${RELEASE}" >/opt/${APP}_version.txt

    msg_ok "Started ${APP}${CL}"
    msg_ok "Updated Successfully${CL}"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}${CL}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!${CL}"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:52345${CL}"
