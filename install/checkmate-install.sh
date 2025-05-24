#!/usr/bin/env bash

#Copyright (c) 2021-2025 community-scripts ORG
# Author: Michel Roegl-Brunner (michelroegl-brunner)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://checkmate.so/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

function install_docker() {
  msg_info "Installing Docker"

  # Check if Docker is already installed
  if command -v docker >/dev/null 2>&1; then
    msg_ok "Docker already installed"
  else
    # Install prerequisites
    $STD apt-get update
    $STD apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      gnupg \
      lsb-release

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

    # Install Docker
    $STD apt-get update
    $STD apt-get install -y docker-ce docker-ce-cli containerd.io

    # Install Docker Compose
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    msg_ok "Installed Docker and Docker Compose"
  fi
}

function install_checkmate() {
  msg_info "Installing Checkmate"

  # Create directory for Checkmate
  mkdir -p /opt/checkmate

  # Download the docker-compose.yaml file
  msg_info "Downloading Docker Compose configuration"
  curl -fsSL "https://raw.githubusercontent.com/bluewave-labs/Checkmate/develop/docker/dist-mono/docker-compose.yaml" -o "/opt/checkmate/docker-compose.yaml"

  # Make sure the data directory exists with proper permissions
  mkdir -p /opt/checkmate/data
  chmod 777 /opt/checkmate/data

  # Start Checkmate services
  msg_info "Starting Checkmate services"
  cd /opt/checkmate || exit
  docker-compose up -d

  # Record the installation
  CHECKMATE_VERSION="$(date +%Y%m%d)"
  echo "${CHECKMATE_VERSION}" >"/opt/checkmate_version.txt"

  msg_ok "Installed Checkmate"
}

install_docker
install_checkmate

# Save credentials to a file
{
  echo "Application-Credentials"
  echo "URL: http://$(hostname -I | awk '{print $1}'):8080"
  echo "Email: admin@example.com"
  echo "Password: password"
} >>~/checkmate.creds

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
